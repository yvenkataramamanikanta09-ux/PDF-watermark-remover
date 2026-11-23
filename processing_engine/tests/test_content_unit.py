"""Tokenizer, PDFium object replay and byte-splicing units (no worker process)."""
from contextlib import closing
from pathlib import Path
import tempfile
import unittest

import pypdfium2 as pdfium
from pypdf import PdfReader, PdfWriter
from pypdf.generic import (ArrayObject, DecodedStreamObject, DictionaryObject, FloatObject,
                           NameObject, NumberObject)

from pdf_watermark_engine.content import (ContentSyntaxError, Name, analyze_page, operator_sequence,
                                          removal_edit, splice, text_dependency_blocked, tokenize, walk)
from pdf_watermark_engine.editing import mapping_error
from pdf_watermark_engine.geometry import GeometryError, PageGeometry, effective_crop_box, pdf_rect_to_unit
from pdf_watermark_engine.rendering import page_objects
from fixtures import create_fixture


def single_page(path, content: bytes, *, extra_resources=None):
    writer = PdfWriter()
    page = writer.add_blank_page(600, 800)
    font = writer._add_object(DictionaryObject({
        NameObject("/Type"): NameObject("/Font"), NameObject("/Subtype"): NameObject("/Type1"),
        NameObject("/BaseFont"): NameObject("/Helvetica")}))
    resources = DictionaryObject({NameObject("/Font"): DictionaryObject({NameObject("/F1"): font})})
    resources.update(extra_resources(writer) if extra_resources else {})
    page[NameObject("/Resources")] = resources
    stream = DecodedStreamObject()
    stream.set_data(content)
    page[NameObject("/Contents")] = writer._add_object(stream)
    with Path(path).open("wb") as output:
        writer.write(output)
    writer.close()
    return path


class ContentUnitTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="pdfwm_unit_")
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)

    def analyze(self, path):
        with PdfReader(path, strict=True) as reader:
            page = reader.pages[0]
            content = analyze_page(page)
            with pdfium.PdfDocument(path) as document, closing(document[0]) as pdf_page:
                objects = page_objects(pdf_page)
            return content, objects, mapping_error(content, objects, page)

    def test_tokenizer_keeps_offsets_strings_and_inline_images(self):
        data = (b"% comment\nq 1 0 0 1 10 20 cm /Name#20X Do (a\\(b\\) \\101\\\n) Tj <4142 4> Tj\n"
                b"BI /W 2 /H 1 /CS /RGB /BPC 8 ID \x00EI\xff\x01\x02 EI Q")
        operations = tokenize([data], None)
        self.assertEqual(operator_sequence(operations),
                         [b"q", b"cm", b"Do", b"Tj", b"Tj", b"INLINE IMAGE", b"Q"])
        self.assertEqual(operations[2].operands, [Name("Name X")])
        self.assertEqual(operations[3].operands, [b"a(b) A"])
        self.assertEqual(operations[4].operands, [b"AB@"])
        image = operations[5]
        self.assertTrue(data[image.start:image.end].startswith(b"BI") and data[image.start:image.end].endswith(b"EI"))
        for bad in (b"(unterminated Tj", b"<4G> Tj", b"[1 2 Tj", b") Tj"):
            with self.subTest(bad=bad), self.assertRaises(ContentSyntaxError):
                tokenize([bad], None)

    def test_replay_matches_pdfium_objects_on_varied_content(self):
        content = (b"q 1 0 0 1 50 600 cm 0 0 200 100 re W n /Sh1 sh Q\n"
                   b"BT /F1 14 Tf 2 Tc 5 Tw 16 TL 60 560 Td (Spaced) Tj T* (Second) ' 1 2 (third) \" ET\n"
                   b"BT /F1 12 Tf 60 500 Td [(Kern) -300 (ed)] TJ [-200] TJ () Tj ET\n"
                   b"10 10 m 10 10 m f 10 10 m 20 20 l 30 30 m S 1 1 m h n\n"
                   b"q 30 0 0 30 300 600 cm BI /W 2 /H 2 /CS /RGB /BPC 8 ID \xff\x00\x00\x00\xff\x00"
                   b"\x00\x00\xff\xff\xff\x00 EI Q\n/Missing Do /Artifact /Nope BDC 0 0 5 5 re f EMC EMC\n")

        def shading(writer):
            function = DictionaryObject({
                NameObject("/FunctionType"): NumberObject(2), NameObject("/N"): FloatObject(1),
                NameObject("/Domain"): ArrayObject([FloatObject(0), FloatObject(1)]),
                NameObject("/C0"): ArrayObject([FloatObject(1), FloatObject(0), FloatObject(0)]),
                NameObject("/C1"): ArrayObject([FloatObject(0), FloatObject(0), FloatObject(1)])})
            return {NameObject("/Shading"): DictionaryObject({NameObject("/Sh1"): writer._add_object(DictionaryObject({
                NameObject("/ShadingType"): NumberObject(2), NameObject("/ColorSpace"): NameObject("/DeviceRGB"),
                NameObject("/Coords"): ArrayObject([FloatObject(0), FloatObject(0), FloatObject(200), FloatObject(0)]),
                NameObject("/Function"): function}))})}

        path = single_page(self.root / "varied.pdf", content, extra_resources=shading)
        parsed, objects, error = self.analyze(path)
        self.assertIsNone(error)
        self.assertEqual([site.kind for site in parsed.sites],
                         ["shading", "text", "text", "text", "text", "path", "image", "path"])
        self.assertEqual(len(objects), 8)

    def test_fixture_pages_map_exactly(self):
        path = create_fixture(self.root / "fixture.pdf", page_count=2, artifact="inline", overlay=True)
        with PdfReader(path, strict=True) as reader, pdfium.PdfDocument(path) as document:
            for index, page in enumerate(reader.pages):
                content = analyze_page(page)
                with closing(document[index]) as pdf_page:
                    self.assertIsNone(mapping_error(content, page_objects(pdf_page), page))
                self.assertEqual(sum(site.watermark_artifact for site in content.sites), 2)

    def test_removal_edits_preserve_line_advance_operators(self):
        data = b"BT /F1 9 Tf 1 0 0 1 5 5 Tm (a) Tj (b) ' 3 4 (c) \" ET 0 0 9 9 re f /X Do"
        content = analyze_page_from_bytes(data)
        texts = [index for index, site in enumerate(content.sites) if site.kind == "text"]
        edits = [removal_edit(content, content.sites[index]) for index in texts[1:]]
        edited = splice(content, edits)[0]
        self.assertEqual(operator_sequence(tokenize([edited], None)),
                         [b"BT", b"Tf", b"Tm", b"Tj", b"T*", b"Tw", b"Tc", b"T*", b"ET", b"re", b"f", b"Do"])
        path_site = next(site for site in content.sites if site.kind == "path")
        self.assertTrue(splice(content, [removal_edit(content, path_site)])[0].endswith(b"9 9 re n /X Do"))

    def test_text_position_dependency_blocks_partial_line_removal(self):
        content = analyze_page_from_bytes(b"BT /F1 9 Tf 10 10 Td (A) Tj (B) Tj 0 -12 Td (C) Tj (D) Tj ET")
        # Removing A would shift B; removing D (last on its line) is independent.
        self.assertEqual(text_dependency_blocked(content, {0}), {0})
        self.assertEqual(text_dependency_blocked(content, {0, 1}), set())
        self.assertEqual(text_dependency_blocked(content, {3}), set())
        self.assertEqual(text_dependency_blocked(content, {2}), {2})

    def test_unit_rect_and_effective_crop(self):
        geometry = PageGeometry(1, (0, 0, 600, 800), (100, 100, 500, 700), 90)
        self.assertEqual(pdf_rect_to_unit(geometry, (0, 0, 50, 50), render_box="cropBox"), None)
        unit = pdf_rect_to_unit(geometry, (50, 650, 300, 900), render_box="cropBox")
        for actual, expected in zip(unit, (11 / 12, 0.0, 1.0, 0.5)):
            self.assertAlmostEqual(actual, expected)
        self.assertEqual(effective_crop_box((0, 0, 600, 800), (-5, 900, 700, 10)), (0, 10, 600, 800))
        with self.assertRaises(GeometryError):
            effective_crop_box((0, 0, 600, 800), (601, 0, 700, 800))


def analyze_page_from_bytes(data):
    from pdf_watermark_engine.content import PageContent
    font = DictionaryObject({NameObject("/F1"): DictionaryObject()})
    resources = DictionaryObject({NameObject("/Font"): font})
    content = PageContent([data])
    content.operations = tokenize([data], resources)
    content.sites, _ = walk(content.operations, resources)
    return content


if __name__ == "__main__":
    unittest.main()

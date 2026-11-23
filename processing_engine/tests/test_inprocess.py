"""The engine's in-process mode (used on Android, where no worker process can be started)."""

from pathlib import Path
import os
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

import pypdfium2 as pdfium
from pypdf import PdfWriter
from pypdf.generic import DecodedStreamObject, DictionaryObject, NameObject

from pdf_watermark_engine import storage
from pdf_watermark_engine.api import PdfWatermarkEngine
from pdf_watermark_engine.models import EngineFailure, Limits, ManualSelection, Outcome

BODY = "Quarterly report"
OVERLAY = "DRAFT"


def make_pdf(path: Path, *, pages: int = 2, overlay: bool = False) -> Path:
    writer = PdfWriter()
    font = writer._add_object(DictionaryObject({
        NameObject("/Type"): NameObject("/Font"), NameObject("/Subtype"): NameObject("/Type1"),
        NameObject("/BaseFont"): NameObject("/Helvetica")}))
    for number in range(1, pages + 1):
        page = writer.add_blank_page(612, 792)
        content = f"BT /F1 12 Tf 72 720 Td ({BODY} {number}) Tj ET\n"
        if overlay:
            content += f"BT /F1 48 Tf 1 0 0 1 200 380 Tm ({OVERLAY}) Tj ET\n"
        stream = DecodedStreamObject()
        stream.set_data(content.encode())
        page[NameObject("/Resources")] = DictionaryObject(
            {NameObject("/Font"): DictionaryObject({NameObject("/F1"): font})})
        page[NameObject("/Contents")] = writer._add_object(stream)
    with path.open("wb") as handle:
        writer.write(handle)
    return path


def texts(path: Path) -> list[str]:
    result = []
    with pdfium.PdfDocument(path) as document:
        for index in range(len(document)):
            page = document[index]
            textpage = page.get_textpage()
            result.append(textpage.get_text_range())
            textpage.close()
            page.close()
    return result


class InProcessTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="pdfwm_inproc_tests_")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.jobs = self.root / "jobs"
        self.jobs.mkdir()
        self.engine = PdfWatermarkEngine(temporary_root=self.jobs, isolation="inprocess")

    def test_rejects_unknown_isolation(self):
        with self.assertRaises(ValueError):
            PdfWatermarkEngine(isolation="thread")

    def test_does_not_start_a_worker_process_or_change_the_working_directory(self):
        source = make_pdf(self.root / "a.pdf", overlay=True)
        before = os.getcwd()
        with mock.patch.object(subprocess, "Popen", side_effect=AssertionError("worker started")):
            result = self.engine.analyze(source, self.root / "preview.png")
        self.assertEqual(os.getcwd(), before)
        self.assertEqual(result.outcome, Outcome.NONE_DETECTED, result.code)
        self.assertTrue((self.root / "preview.png").read_bytes().startswith(b"\x89PNG"))
        self.assertEqual(list(self.jobs.iterdir()), [], "job folder leaked")

    def test_area_removal_matches_process_mode(self):
        source = make_pdf(self.root / "b.pdf", pages=3, overlay=True)
        analysis = self.engine.analyze(source, self.root / "p.png")
        preview = analysis.preview
        selection = ManualSelection(
            document_id="sha256:" + analysis.source_sha256, source_sha256=analysis.source_sha256,
            source_size=analysis.source_size, page_number=1, geometry_sha256=preview["geometry_sha256"],
            render_box="cropBox", raster_width=preview["width"], raster_height=preview["height"],
            rect=(0.30, 0.44, 0.62, 0.56))
        results = {}
        for isolation in ("inprocess", "process"):
            engine = PdfWatermarkEngine(temporary_root=self.jobs, isolation=isolation)
            output = self.root / f"{isolation}.pdf"
            result = engine.remove(source, output, mode="area", selection=selection,
                                   expected_sha256=analysis.source_sha256)
            self.assertEqual(result.outcome, Outcome.REMOVED, (isolation, result.code))
            self.assertEqual(result.pages_changed, [1, 2, 3])
            for number, text in enumerate(texts(output), start=1):
                self.assertNotIn(OVERLAY, text)
                self.assertIn(f"{BODY} {number}", text)
            results[isolation] = result
        a, b = results["inprocess"], results["process"]
        self.assertEqual((a.removed_count, a.removed_by_kind, a.code), (b.removed_count, b.removed_by_kind, b.code))
        self.assertEqual(list(self.jobs.iterdir()), [])

    def test_failures_are_results_not_exceptions(self):
        broken = self.root / "broken.pdf"
        broken.write_bytes(b"%PDF-1.7\n1 0 obj << >> endobj\n%%EOF\n")
        result = self.engine.detect(broken)
        self.assertEqual(result.outcome, Outcome.INVALID_PDF)
        self.assertEqual(result.code, "invalid_pdf_structure")
        missing = self.engine.detect(self.root / "missing.pdf")
        self.assertEqual(missing.outcome, Outcome.INVALID_PDF)

    def test_source_is_never_modified(self):
        source = make_pdf(self.root / "c.pdf", overlay=True)
        before = source.read_bytes()
        self.engine.analyze(source, self.root / "pc.png")
        self.assertEqual(source.read_bytes(), before)


class PublishFallbackTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="pdfwm_publish_tests_")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.staged = self.root / "staged.bin"
        self.staged.write_bytes(b"payload")

    def test_hard_link_failure_is_an_error_by_default(self):
        with mock.patch.object(os, "link", side_effect=PermissionError("no links")):
            with self.assertRaises(OSError):
                storage.publish_exclusive(self.staged, self.root / "out.bin", 1024)
        self.assertEqual(sorted(p.name for p in self.root.iterdir()), ["staged.bin"])

    def test_rename_fallback_publishes_when_links_are_refused(self):
        with mock.patch.object(os, "link", side_effect=PermissionError("no links")):
            storage.publish_exclusive(self.staged, self.root / "out.bin", 1024, rename_fallback=True)
        self.assertEqual((self.root / "out.bin").read_bytes(), b"payload")
        self.assertEqual(sorted(p.name for p in self.root.iterdir()), ["out.bin", "staged.bin"])

    def test_rename_fallback_never_overwrites(self):
        out = self.root / "out.bin"
        out.write_bytes(b"existing")
        with self.assertRaises(EngineFailure):
            storage.publish_exclusive(self.staged, out, 1024, rename_fallback=True)
        self.assertEqual(out.read_bytes(), b"existing")


if __name__ == "__main__":
    unittest.main()

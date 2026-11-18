from dataclasses import replace
from pathlib import Path
import json
import tempfile
import unittest

import pypdfium2 as pdfium
from pypdf import PdfReader, PdfWriter
from pypdf.generic import (ArrayObject, DictionaryObject, NameObject,
                           NumberObject, RectangleObject, TextStringObject)

from pdf_watermark_engine.api import PdfWatermarkEngine
from pdf_watermark_engine.document import Graph, load_document
from pdf_watermark_engine.geometry import PageGeometry, pdf_to_normalized
from pdf_watermark_engine.models import Limits, ManualSelection, Outcome
from fixtures import create_fixture, watermark_rect
from verification import observations, sha256, structure


class EngineTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="pdfwm_tests_")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.jobs = self.root / "jobs"
        self.jobs.mkdir()
        self.engine = PdfWatermarkEngine(temporary_root=self.jobs)
        self.source = self.root / "source.pdf"
        self.output = self.root / "output.pdf"

    def tearDown(self):
        self.assertEqual(list(self.jobs.iterdir()), [], "Intermediate files leaked")
        self.assertEqual(list(self.root.glob(".pdfwm_*")), [], "Publication staging leaked")

    def fixture(self, **kwargs):
        return create_fixture(self.source, **kwargs)

    def mutate(self, edit):
        target = self.root / "mutated.pdf"
        with PdfReader(self.source, strict=True) as reader:
            writer = PdfWriter(clone_from=reader)
            try:
                edit(writer)
                writer.write(target)
            finally:
                writer.close()
        self.source = target

    def remove(self, **kwargs):
        digest = sha256(self.source)
        result = self.engine.remove(self.source, self.output, **kwargs)
        self.assertEqual(sha256(self.source), digest)
        return result

    def selection(self, report, rect=None, render_box="cropBox"):
        page = report.pages[0]
        geometry = PageGeometry(**{key: page[key] for key in
                                  ("page_number", "media_box", "crop_box", "rotation", "user_unit")})
        if rect is None:
            region = pdf_to_normalized(geometry, watermark_rect(geometry.crop_box), render_box=render_box)
            rect = (region.left, region.top, region.right, region.bottom)
        box = geometry.crop_box if render_box == "cropBox" else geometry.media_box
        width, height = round(box[2] - box[0]), round(box[3] - box[1])
        if geometry.rotation in (90, 270):
            width, height = height, width
        return ManualSelection(report.document_id, report.source_sha256, report.source_size,
                               1, page["geometry_sha256"], render_box, width, height, rect)

    def test_detection_is_read_only_and_explicit(self):
        self.fixture()
        digest = sha256(self.source)
        report = self.engine.detect(self.source)
        self.assertEqual(report.outcome, Outcome.SUPPORTED_DETECTED)
        self.assertEqual((report.supported_count, report.removed_count), (1, 0))
        self.assertEqual(report.document_id, "sha256:" + digest)
        self.assertEqual(sha256(self.source), digest)
        self.assertFalse(self.output.exists())

    def test_real_removal_preserves_text_images_links_annotations_and_pixels(self):
        self.fixture()
        clean = create_fixture(self.root / "expected.pdf", watermarks=False)
        before = observations(self.source)
        result = self.remove()
        self.assertEqual(result.outcome, Outcome.REMOVED, result.to_dict())
        self.assertEqual(result.removed_count, 1)
        after = observations(self.output)
        self.assertEqual(after, observations(clean))
        self.assertNotEqual(before[0]["pixels"], after[0]["pixels"])
        self.assertEqual(before[0]["text"], after[0]["text"])
        self.assertIn(pdfium.raw.FPDF_ANNOT_WATERMARK, before[0]["annotation_types"])
        self.assertNotIn(pdfium.raw.FPDF_ANNOT_WATERMARK, after[0]["annotation_types"])
        self.assertEqual(after[0]["annotation_types"], [pdfium.raw.FPDF_ANNOT_LINK,
                                                      pdfium.raw.FPDF_ANNOT_TEXT,
                                                      pdfium.raw.FPDF_ANNOT_STAMP])
        self.assertEqual(structure(self.source), structure(self.output))
        self.assertEqual(result.output_sha256, sha256(self.output))
        self.assertNotIn(b"(WATERMARK)", self.output.read_bytes())

    def test_multipage_all_rotations_and_crop_boxes(self):
        options = dict(page_count=4, rotations=[0, 90, 180, 270],
                       crops=[(0, 0, 600, 800), (30, 70, 550, 750),
                              (100, 120, 510, 710), (20, 40, 580, 780)])
        self.fixture(**options)
        clean = create_fixture(self.root / "expected.pdf", watermarks=False, **options)
        result = self.remove()
        self.assertEqual(result.outcome, Outcome.REMOVED, result.to_dict())
        self.assertEqual((result.page_count, result.removed_count), (4, 4))
        self.assertEqual(observations(self.output), observations(clean))
        self.assertEqual(structure(self.source), structure(self.output))

    def test_nested_page_tree_preserved(self):
        self.fixture(page_count=3, nested_pages=True)
        result = self.remove()
        self.assertEqual(result.outcome, Outcome.REMOVED, result.to_dict())
        with PdfReader(self.output) as reader:
            self.assertEqual(reader.root_object["/Pages"]["/Kids"][0].get_object()["/Type"], "/Pages")
        self.assertEqual(structure(self.source), structure(self.output))

    def test_shared_appearance_survives_partial_manual_removal(self):
        self.fixture(page_count=2)
        selection = self.selection(self.engine.detect(self.source))
        result = self.remove(selection=selection)
        self.assertEqual(result.outcome, Outcome.REMOVED, result.to_dict())
        self.assertEqual(result.removed_count, 1)
        before, after = observations(self.source), observations(self.output)
        self.assertNotIn(pdfium.raw.FPDF_ANNOT_WATERMARK, after[0]["annotation_types"])
        self.assertEqual(before[1], after[1])

    def test_no_watermark_is_never_success_and_produces_no_output(self):
        self.fixture(watermarks=False)
        result = self.remove()
        self.assertEqual(result.outcome, Outcome.NONE_DETECTED)
        self.assertEqual(result.removed_count, 0)
        self.assertFalse(self.output.exists())

    def test_ordinary_note_containing_watermark_word_is_preserved(self):
        self.fixture(watermarks=False)
        self.assertEqual(self.engine.detect(self.source).candidates, [])

    def test_custom_watermark_stamp_is_ambiguous_not_removed(self):
        self.fixture(watermarks=False, stamp_hint=True)
        result = self.remove()
        self.assertEqual(result.outcome, Outcome.UNSUPPORTED)
        self.assertEqual(result.candidates[0]["reason"], "ambiguous_custom_stamp_name")
        self.assertFalse(self.output.exists())

    def test_supported_and_unsupported_candidates_are_reported_separately(self):
        self.fixture(stamp_hint=True)
        result = self.remove()
        self.assertEqual(result.outcome, Outcome.REMOVED, result.to_dict())
        self.assertEqual((result.removed_count, result.unsupported_count), (1, 1))
        self.assertEqual(structure(self.source), structure(self.output))

    def test_state_dictionary_appearance_is_unsupported(self):
        self.fixture(malformed_appearance=True)
        result = self.remove()
        self.assertEqual(result.outcome, Outcome.UNSUPPORTED)
        self.assertEqual(result.candidates[0]["reason"], "unsupported_normal_appearance")
        self.assertFalse(self.output.exists())

    def test_empty_appearance_is_not_claimed_as_supported(self):
        self.fixture()
        self.mutate(lambda writer: writer.pages[0]["/Annots"][-1].get_object()["/AP"]["/N"].set_data(b""))
        result = self.remove()
        self.assertEqual(result.outcome, Outcome.UNSUPPORTED)
        self.assertEqual(result.candidates[0]["reason"], "empty_normal_appearance")

    def test_appearance_matrix_must_be_invertible(self):
        self.fixture()
        self.mutate(lambda writer: writer.pages[0]["/Annots"][-1].get_object()["/AP"]["/N"].__setitem__(
            NameObject("/Matrix"), ArrayObject([NumberObject(0)] * 6)))
        self.assertEqual(self.remove().outcome, Outcome.UNSUPPORTED)

    def test_string_subtype_is_not_a_supported_pdf_name(self):
        self.fixture()
        self.mutate(lambda writer: writer.pages[0]["/Annots"][-1].get_object().__setitem__(
            NameObject("/Subtype"), TextStringObject("/Watermark")))
        self.assertEqual(self.remove().outcome, Outcome.UNSUPPORTED)

    def test_document_timestamp_marker_prevents_removal(self):
        self.fixture()
        self.mutate(lambda writer: writer.root_object.__setitem__(NameObject("/Timestamp"),
            DictionaryObject({NameObject("/Type"): NameObject("/DocTimeStamp")})))
        self.assertEqual(self.remove().code, "signed_or_certified_document_not_modified")

    def test_fixed_print_hidden_locked_interactive_and_dependent_objects_refused(self):
        variants = [("/FixedPrint", DictionaryObject()), ("/F", NumberObject(2)),
                    ("/F", NumberObject(128)), ("/F", NumberObject(16)),
                    ("/A", DictionaryObject()), ("/StructParent", NumberObject(0)),
                    ("/OC", DictionaryObject()), ("/IRT", DictionaryObject())]
        for field, value in variants:
            with self.subTest(field=field, value=str(value)):
                self.source = self.root / "source.pdf"
                self.fixture()
                self.mutate(lambda writer: writer.pages[0]["/Annots"][-1].get_object().__setitem__(NameObject(field), value))
                self.assertEqual(self.remove().outcome, Outcome.UNSUPPORTED)
                self.assertFalse(self.output.exists())

    def test_shared_annotation_reference_is_unsupported(self):
        self.fixture()
        self.mutate(lambda writer: writer.pages[0]["/Annots"].append(writer.pages[0]["/Annots"][-1]))
        result = self.remove()
        self.assertEqual(result.outcome, Outcome.UNSUPPORTED)
        self.assertEqual(result.unsupported_count, 2)

    def test_absent_annotation_name_does_not_break_object_absence_check(self):
        self.fixture(page_count=2)
        def edit(writer):
            for page in writer.pages:
                del page["/Annots"][-1].get_object()["/NM"]
        self.mutate(edit)
        self.assertEqual(self.remove().removed_count, 2)

    def test_outside_crop_annotation_is_not_removed(self):
        self.fixture(crops=[(50, 50, 550, 750)])
        self.mutate(lambda writer: writer.pages[0]["/Annots"][-1].get_object().__setitem__(NameObject("/Rect"), RectangleObject((0, 0, 600, 800))))
        self.assertEqual(self.remove().outcome, Outcome.UNSUPPORTED)

    def test_signed_markers_prevent_modification(self):
        self.fixture(signed=True)
        result = self.remove()
        self.assertEqual(result.outcome, Outcome.UNSUPPORTED)
        self.assertEqual(result.code, "signed_or_certified_document_not_modified")
        self.assertFalse(self.output.exists())

    def test_password_required_is_explicit(self):
        self.fixture(encrypted=True)
        result = self.remove()
        self.assertEqual(result.outcome, Outcome.PASSWORD_REQUIRED)
        self.assertFalse(self.output.exists())

    def test_empty_malformed_and_truncated_inputs(self):
        for data in (b"", b"not a PDF", b"%PDF-1.7\n1 0 obj << >> endobj\n%%EOF", b"%PDF-1.7\ntruncated"):
            with self.subTest(data=data):
                self.source.write_bytes(data)
                self.assertEqual(self.remove().outcome, Outcome.INVALID_PDF)
                self.assertFalse(self.output.exists())

    def test_missing_input_is_invalid(self):
        self.assertEqual(self.engine.detect(self.source).outcome, Outcome.INVALID_PDF)

    def test_existing_and_same_output_are_never_modified(self):
        self.fixture()
        self.output.write_bytes(b"keep existing output")
        self.assertEqual(self.remove().outcome, Outcome.FAILED)
        self.assertEqual(self.output.read_bytes(), b"keep existing output")
        self.assertEqual(self.engine.remove(self.source, self.source).code, "unsafe_or_existing_output")

    def test_missing_output_directory_fails_without_publication(self):
        self.fixture()
        self.output = self.root / "absent" / "output.pdf"
        self.assertEqual(self.remove().outcome, Outcome.FAILED)
        self.assertFalse(self.output.exists())

    def test_revision_mismatch_fails_before_processing(self):
        self.fixture()
        self.assertEqual(self.remove(expected_sha256="0" * 64).code, "document_revision_mismatch")
        self.assertFalse(self.output.exists())

    def test_manual_mapping_matches_native_render_rotations_and_cropping(self):
        for rotation in (0, 90, 180, 270):
            for box in ("cropBox", "mediaBox"):
                with self.subTest(rotation=rotation, box=box):
                    self.source = self.root / f"manual-{rotation}-{box}.pdf"
                    self.output = self.root / f"result-{rotation}-{box}.pdf"
                    self.fixture(rotations=[rotation], crops=[(30, 70, 550, 750)])
                    selection = self.selection(self.engine.detect(self.source), render_box=box)
                    self.assertEqual(self.remove(selection=selection).outcome, Outcome.REMOVED)

    def test_manual_partial_overlap_does_not_delete_whole_annotation(self):
        self.fixture()
        selection = self.selection(self.engine.detect(self.source), rect=(.4, .4, .6, .55))
        self.assertEqual(self.remove(selection=selection).outcome, Outcome.NONE_DETECTED)
        self.assertFalse(self.output.exists())

    def test_manual_area_over_ordinary_content_does_not_redact(self):
        self.fixture(watermarks=False)
        selection = self.selection(self.engine.detect(self.source), rect=(0, 0, 1, 1))
        self.assertEqual(self.remove(selection=selection).outcome, Outcome.NONE_DETECTED)
        self.assertFalse(self.output.exists())

    def test_manual_stale_identity_revision_and_geometry_rejected(self):
        self.fixture()
        original = self.selection(self.engine.detect(self.source))
        for changes in ({"document_id": "session-document-1"}, {"source_sha256": "0" * 64},
                        {"source_size": original.source_size + 1}, {"geometry_sha256": "0" * 64}):
            with self.subTest(changes=changes):
                self.assertEqual(self.remove(selection=replace(original, **changes)).outcome, Outcome.FAILED)
                self.assertFalse(self.output.exists())

    def test_manual_ambiguous_invalid_and_page_two_coordinates_rejected(self):
        self.fixture(page_count=2)
        original = self.selection(self.engine.detect(self.source))
        for changes in ({"render_box": "auto"}, {"coordinate_space": "pdfBottomLeft"},
                        {"raster_width": 500}, {"rect": (0, 0, 0, 1)},
                        {"rect": (-.1, 0, 1, 1)}, {"rect": (0, 0, .01, 1)},
                        {"page_number": 2}):
            with self.subTest(changes=changes):
                self.assertEqual(self.remove(selection=replace(original, **changes)).outcome, Outcome.FAILED)
                self.assertFalse(self.output.exists())

    def test_original_stage_five_unbound_payload_is_not_accepted(self):
        with self.assertRaises((TypeError, KeyError, ValueError)):
            ManualSelection.from_dict({"documentId": "session-document-1", "bounds": [0, 0, 1, 1]})

    def test_input_page_annotation_object_and_output_limits(self):
        self.fixture(page_count=2)
        for changes in ({"max_input_bytes": 100}, {"max_pages": 1},
                        {"max_annotations": 1}, {"max_objects": 10},
                        {"max_output_bytes": 100}, {"max_decoded_stream_bytes": 100}):
            with self.subTest(changes=changes):
                self.engine = PdfWatermarkEngine(replace(Limits(), **changes), temporary_root=self.jobs)
                result = self.remove()
                self.assertIn(result.outcome, (Outcome.FAILED, Outcome.INVALID_PDF))
                self.assertFalse(self.output.exists())

    def test_worker_wall_timeout_cleans_job_and_never_publishes(self):
        self.fixture()
        self.engine = PdfWatermarkEngine(Limits(timeout_seconds=.000001), temporary_root=self.jobs)
        self.assertEqual(self.remove().code, "processing_timeout")
        self.assertFalse(self.output.exists())

    def test_graph_digest_is_repeatable(self):
        self.fixture()
        reader, _, graph = load_document(self.source, Limits())
        try:
            first = graph.digest(reader)
            self.assertEqual(first, graph.digest(reader))
            self.assertEqual(first, Graph(Limits()).digest(reader))
        finally:
            reader.close()

    def test_results_do_not_expose_pdf_text_or_parser_errors(self):
        self.fixture()
        serialized = json.dumps(self.engine.detect(self.source).to_dict())
        for sensitive in ("Ordinary report", "Discussion:", "https://example.com/keep", str(self.source)):
            self.assertNotIn(sensitive, serialized)

    def test_fixture_bytes_are_reproducible(self):
        self.fixture(page_count=2, rotations=[0, 90], encrypted=True)
        duplicate = create_fixture(self.root / "duplicate.pdf", page_count=2, rotations=[0, 90], encrypted=True)
        self.assertEqual(sha256(self.source), sha256(duplicate))


if __name__ == "__main__":
    unittest.main()

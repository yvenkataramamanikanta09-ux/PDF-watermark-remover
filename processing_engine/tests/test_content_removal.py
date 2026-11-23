"""Acrobat watermark artifacts, selected-area removal, previews and robustness."""
from contextlib import closing
from dataclasses import replace
import json
import os
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

import pypdfium2 as pdfium
from PIL import Image
from pypdf import PdfReader, PdfWriter
from pypdf.generic import ArrayObject, FloatObject, NameObject, RectangleObject

import pdf_watermark_engine
from pdf_watermark_engine import editing
from pdf_watermark_engine.api import PdfWatermarkEngine
from pdf_watermark_engine.core import run_job
from pdf_watermark_engine.geometry import PageGeometry, pdf_to_normalized
from pdf_watermark_engine.models import EngineFailure, EngineResult, Limits, ManualSelection, Outcome
from fixtures import (ARTIFACT_SELECTION, OVERLAY_SELECTION, create_fixture, create_marker_fixture,
                      selection_rect, watermark_rect)
from verification import observations, sha256

CROPS = [None, (30, 70, 550, 750), (20, 40, 580, 780)]


def geometry_of(page):
    return PageGeometry(**{key: page[key] for key in
                           ("page_number", "media_box", "crop_box", "rotation", "user_unit")})


class InProcessWorker:
    """Runs the worker protocol in this process so tests can patch internals."""
    returncode = 0
    pid = 1

    def poll(self):
        return 0

    def kill(self):
        pass

    def communicate(self, request=None, timeout=None):
        if request is None:
            return "", None
        request = json.loads(request)
        previous = os.getcwd()
        os.chdir(request["job"])
        try:
            try:
                result = run_job(request, Limits(**request["limits"]))
            except EngineFailure as error:
                result = EngineResult(error.outcome, error.code)
        finally:
            os.chdir(previous)
        return json.dumps(result.to_dict()), None


class ContentRemovalTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="pdfwm_content_tests_")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.jobs = self.root / "jobs"
        self.jobs.mkdir()
        self.engine = PdfWatermarkEngine(Limits(timeout_seconds=180), temporary_root=self.jobs)
        self.source = self.root / "source.pdf"
        self.output = self.root / "output.pdf"
        self.preview = self.root / "preview.png"

    def tearDown(self):
        self.assertEqual(list(self.jobs.iterdir()), [], "Intermediate files leaked")
        self.assertEqual(list(self.root.glob(".pdfwm_*")), [], "Publication staging leaked")

    def remove(self, **kwargs):
        digest = sha256(self.source)
        result = self.engine.remove(self.source, self.output, **kwargs)
        self.assertEqual(sha256(self.source), digest)
        return result

    def area_selection(self, canonical=OVERLAY_SELECTION, source=None):
        """Select through the engine's own preview contract, as the app does."""
        preview = self.root / f"preview-{len(list(self.root.glob('preview-*.png')))}.png"
        report = self.engine.analyze(source or self.source, preview)
        self.assertIn(report.outcome, (Outcome.NONE_DETECTED, Outcome.SUPPORTED_DETECTED), report.to_dict())
        geometry = geometry_of(report.pages[0])
        rect = pdf_to_normalized(geometry, selection_rect(geometry.crop_box, canonical), render_box="cropBox")
        return ManualSelection(report.document_id, report.source_sha256, report.source_size, 1,
                               report.preview["geometry_sha256"], report.preview["render_box"],
                               report.preview["width"], report.preview["height"],
                               (rect.left, rect.top, rect.right, rect.bottom))

    # --- Acrobat-style watermark artifacts -------------------------------------------

    def test_acrobat_artifact_detected_analyzed_and_removed(self):
        options = dict(page_count=3, rotations=[0, 90, 270], crops=CROPS, watermarks=False)
        for kind in ("separate", "named", "inline"):
            with self.subTest(kind=kind):
                self.source = create_fixture(self.root / f"artifact-{kind}.pdf", artifact=kind, **options)
                self.output = self.root / f"artifact-{kind}-out.pdf"
                clean = create_fixture(self.root / f"artifact-{kind}-clean.pdf", **options)
                objects_per_page = 2 if kind == "inline" else 1
                detected = self.engine.detect(self.source)
                self.assertEqual(detected.outcome, Outcome.SUPPORTED_DETECTED, detected.to_dict())
                self.assertEqual((detected.supported_count, detected.artifact_count), (0, 3 * objects_per_page))
                self.assertEqual([page["watermark_artifact_count"] for page in detected.pages],
                                 [objects_per_page] * 3)
                preview = self.root / f"artifact-{kind}.png"
                analyzed = self.engine.analyze(self.source, preview)
                self.assertEqual((analyzed.outcome, analyzed.artifact_count),
                                 (Outcome.SUPPORTED_DETECTED, 3 * objects_per_page))
                self.assertTrue(preview.is_file())
                before = observations(self.source)
                result = self.remove()
                self.assertEqual(result.outcome, Outcome.REMOVED, result.to_dict())
                self.assertEqual(result.removed_by_kind, {"watermark_artifact": 3 * objects_per_page})
                self.assertEqual((result.removed_count, result.pages_changed), (3 * objects_per_page, [1, 2, 3]))
                after, expected = observations(self.output), observations(clean)
                # Pixel-identical (annotations drawn) and text-identical to the same
                # document generated without the watermark.
                self.assertEqual(after, expected)
                for page_before, page_after in zip(before, after):
                    self.assertNotEqual(page_before["pixels"], page_after["pixels"])
                    self.assertIn("CONFIDENTIAL", page_before["text"])
                    self.assertNotIn("CONFIDENTIAL", page_after["text"])
                    self.assertIn("Ordinary report page", page_after["text"])
                self.assertNotIn(b"(CONFIDENTIAL)", self.output.read_bytes())
                self.assertEqual(self.engine.detect(self.output).outcome, Outcome.NONE_DETECTED)

    def test_artifact_and_watermark_annotation_removed_together(self):
        self.source = create_fixture(self.source, page_count=2, artifact="separate")
        clean = create_fixture(self.root / "clean.pdf", page_count=2, watermarks=False)
        detected = self.engine.detect(self.source)
        self.assertEqual((detected.supported_count, detected.artifact_count), (2, 2))
        result = self.remove()
        self.assertEqual(result.outcome, Outcome.REMOVED, result.to_dict())
        self.assertEqual(result.removed_by_kind, {"watermark_artifact": 2, "watermark_annotation": 2})
        self.assertEqual(observations(self.output), observations(clean))

    def test_artifact_first_page_only(self):
        self.source = create_fixture(self.source, page_count=3, watermarks=False, artifact="separate")
        result = self.remove(apply_to="first_page")
        self.assertEqual(result.outcome, Outcome.REMOVED, result.to_dict())
        self.assertEqual((result.removed_count, result.pages_changed), (1, [1]))
        before, after = observations(self.source), observations(self.output)
        self.assertNotEqual(before[0]["pixels"], after[0]["pixels"])
        self.assertEqual(before[1:], after[1:])

    def test_signed_artifact_document_is_not_modified(self):
        self.source = create_fixture(self.source, watermarks=False, artifact="separate", signed=True)
        result = self.remove()
        self.assertEqual((result.outcome, result.code),
                         (Outcome.UNSUPPORTED, "signed_or_certified_document_not_modified"))
        self.assertFalse(self.output.exists())

    # --- selected area ----------------------------------------------------------------

    def test_area_removes_rotated_text_and_image_overlay_on_three_pages(self):
        options = dict(page_count=3, rotations=[90, 90, 90], crops=CROPS, watermarks=False)
        self.source = create_fixture(self.source, overlay=True, **options)
        clean = create_fixture(self.root / "clean.pdf", **options)
        selection = self.area_selection()
        result = self.remove(mode="area", selection=selection, preview_png=self.preview)
        self.assertEqual(result.outcome, Outcome.REMOVED, result.to_dict())
        self.assertEqual(result.removed_by_kind, {"area_object": 6})
        self.assertEqual((result.removed_count, result.pages_changed), (6, [1, 2, 3]))
        before, after, expected = observations(self.source), observations(self.output), observations(clean)
        self.assertEqual(after, expected)
        for page_before, page_after in zip(before, after):
            self.assertIn("DRAFT", page_before["text"])
            self.assertNotIn("DRAFT", page_after["text"])
            self.assertIn("Blue chart must survive", page_after["text"])
        # The preview shows the processed page in the same frame as the selection.
        self.assertEqual(result.preview["path"], str(self.preview))
        self.assertEqual((result.preview["width"], result.preview["height"]),
                         (selection.raster_width, selection.raster_height))
        self.assertEqual(result.preview["geometry_sha256"], selection.geometry_sha256)
        with Image.open(self.preview) as image:
            self.assertEqual(image.size, (selection.raster_width, selection.raster_height))

    def test_area_partial_overlap_objects_are_kept(self):
        self.source = create_fixture(self.source, page_count=2, watermarks=False, overlay=True)
        # Fully contains the overlay image only; the rotated text and chart cross it.
        result = self.remove(mode="area", selection=self.area_selection((290, 370, 350, 430)))
        self.assertEqual(result.outcome, Outcome.REMOVED, result.to_dict())
        self.assertEqual(result.removed_by_kind, {"area_object": 2})
        for page in observations(self.output):
            self.assertIn("DRAFT COPY", page["text"])
        with pdfium.PdfDocument(self.output) as document, closing(document[0]) as page:
            kinds = [pdfium.raw.FPDFPageObj_GetType(pdfium.raw.FPDFPage_GetObject(page, index))
                     for index in range(pdfium.raw.FPDFPage_CountObjects(page))]
        self.assertEqual(kinds.count(pdfium.raw.FPDF_PAGEOBJ_IMAGE), 1)  # body image only
        self.assertEqual(kinds.count(pdfium.raw.FPDF_PAGEOBJ_PATH), 10)  # whole chart kept

    def test_area_apply_to_first_page_versus_all_pages(self):
        self.source = create_fixture(self.source, page_count=3, watermarks=False, overlay=True)
        selection = self.area_selection()
        first = self.remove(mode="area", selection=selection, apply_to="first_page")
        self.assertEqual(first.outcome, Outcome.REMOVED, first.to_dict())
        self.assertEqual((first.removed_count, first.pages_changed), (2, [1]))
        before, after = observations(self.source), observations(self.output)
        self.assertNotEqual(before[0]["pixels"], after[0]["pixels"])
        self.assertEqual(before[1:], after[1:])
        self.output = self.root / "all.pdf"
        every = self.remove(mode="area", selection=selection, apply_to="all_pages")
        self.assertEqual((every.removed_count, every.pages_changed), (6, [1, 2, 3]))

    def test_area_with_nothing_fully_inside_is_none_detected(self):
        self.source = create_fixture(self.source, watermarks=False, overlay=True)
        for canonical in ((100, 250, 190, 350), (500, 100, 590, 200)):
            with self.subTest(canonical=canonical):
                result = self.remove(mode="area", selection=self.area_selection(canonical))
                self.assertEqual((result.outcome, result.code),
                                 (Outcome.NONE_DETECTED, "no_removable_objects_in_selection"))
                self.assertEqual((result.removed_count, result.removed_by_kind), (0, {}))
                self.assertFalse(self.output.exists())

    def test_area_removes_watermark_and_stamp_annotations_inside(self):
        self.source = create_fixture(self.source, page_count=2)
        clean = create_fixture(self.root / "clean.pdf", page_count=2, watermarks=False)
        result = self.remove(mode="area", selection=self.area_selection((140, 310, 460, 450)))
        self.assertEqual(result.outcome, Outcome.REMOVED, result.to_dict())
        self.assertEqual(result.removed_by_kind, {"area_annotation": 2})
        self.assertEqual(observations(self.output), observations(clean))
        self.output = self.root / "stamp.pdf"
        result = self.remove(mode="area", selection=self.area_selection((370, 640, 550, 720)))
        self.assertEqual(result.removed_by_kind, {"area_annotation": 2}, result.to_dict())
        for page in observations(self.output):
            self.assertNotIn(pdfium.raw.FPDF_ANNOT_STAMP, page["annotation_types"])

    def test_area_requires_valid_selection_and_mode(self):
        self.source = create_fixture(self.source, watermarks=False, overlay=True)
        selection = self.area_selection()
        self.assertEqual(self.remove(mode="area").code, "area_selection_required")
        self.assertEqual(self.remove(mode="erase", selection=selection).code, "invalid_mode_or_scope")
        self.assertEqual(self.remove(mode="area", selection=selection, apply_to="odd_pages").code,
                         "invalid_mode_or_scope")
        for changes in ({"geometry_sha256": "0" * 64}, {"source_sha256": "0" * 64},
                        {"raster_width": selection.raster_width + 40}, {"page_number": 2}):
            with self.subTest(changes=changes):
                result = self.remove(mode="area", selection=replace(selection, **changes))
                self.assertEqual(result.outcome, Outcome.FAILED)
        self.assertFalse(self.output.exists())

    def test_area_refuses_signed_and_encrypted_documents(self):
        self.source = create_fixture(self.source, watermarks=False, overlay=True, signed=True)
        selection = self.area_selection()
        result = self.remove(mode="area", selection=selection)
        self.assertEqual((result.outcome, result.code),
                         (Outcome.UNSUPPORTED, "signed_or_certified_document_not_modified"))
        self.assertFalse(self.output.exists())
        self.source = create_fixture(self.root / "encrypted.pdf", watermarks=False, overlay=True, encrypted=True)
        result = self.remove(mode="area", selection=selection)
        self.assertEqual(result.outcome, Outcome.PASSWORD_REQUIRED)
        self.assertFalse(self.output.exists())
        self.assertEqual(self.engine.analyze(self.source, self.root / "locked.png").outcome,
                         Outcome.PASSWORD_REQUIRED)
        self.assertFalse((self.root / "locked.png").exists())

    def test_forced_validation_failure_publishes_nothing(self):
        self.source = create_fixture(self.source, page_count=2, watermarks=False, overlay=True)
        selection = self.area_selection()
        original_splice = editing.splice

        def tampering_splice(content, edits):
            # Simulate a faulty edit that also drops body text outside the selection.
            changed = original_splice(content, edits)
            return {stream: data.replace(b"(Ordinary report page", b"(Altered report page")
                    for stream, data in changed.items()}

        for target, expected in ((tampering_splice, "content_outside_selection_changed"),):
            with patch("pdf_watermark_engine.api.subprocess.Popen", return_value=InProcessWorker()), \
                    patch("pdf_watermark_engine.api.windows_job", return_value=lambda: None), \
                    patch("pdf_watermark_engine.editing.splice", target):
                result = self.remove(mode="area", selection=selection, preview_png=self.preview)
            self.assertEqual((result.outcome, result.code), (Outcome.FAILED, expected))
            self.assertFalse(self.output.exists())
            self.assertFalse(self.preview.exists())

    def test_forced_text_change_inside_but_render_equal_is_rejected(self):
        self.source = create_fixture(self.source, watermarks=False, overlay=True)
        selection = self.area_selection()
        from pdf_watermark_engine import rendering
        original = rendering.text_characters
        calls = []

        def drifting_text(page):
            characters = original(page)
            calls.append(1)
            if len(calls) % 2 == 0 and characters:  # the processed page's text moved
                unicode, box = characters[0]
                characters[0] = (unicode, (box[0] + 3, box[1], box[2] + 3, box[3]))
            return characters

        with patch("pdf_watermark_engine.api.subprocess.Popen", return_value=InProcessWorker()), \
                patch("pdf_watermark_engine.api.windows_job", return_value=lambda: None), \
                patch("pdf_watermark_engine.editing.text_characters", drifting_text):
            result = self.remove(mode="area", selection=selection)
        self.assertEqual((result.outcome, result.code), (Outcome.FAILED, "text_outside_selection_changed"))
        self.assertFalse(self.output.exists())

    def test_in_process_worker_matches_subprocess_result(self):
        self.source = create_fixture(self.source, watermarks=False, overlay=True)
        selection = self.area_selection()
        with patch("pdf_watermark_engine.api.subprocess.Popen", return_value=InProcessWorker()), \
                patch("pdf_watermark_engine.api.windows_job", return_value=lambda: None):
            result = self.remove(mode="area", selection=selection)
        self.assertEqual(result.outcome, Outcome.REMOVED, result.to_dict())
        self.assertEqual(result.removed_by_kind, {"area_object": 2})

    def test_area_mode_fifty_pages_within_worker_timeout(self):
        self.source = create_fixture(self.source, page_count=50, watermarks=False, overlay=True)
        selection = self.area_selection()
        start = time.perf_counter()
        result = self.remove(mode="area", selection=selection)
        elapsed = time.perf_counter() - start
        print(f"\n[timing] 50-page area removal: {elapsed:.1f} s", file=sys.stderr)
        self.assertEqual(result.outcome, Outcome.REMOVED, result.to_dict())
        self.assertEqual((result.removed_count, result.pages_changed), (100, list(range(1, 51))))
        self.assertLess(elapsed, 180)

    # --- preview frame, robustness ------------------------------------------------------

    def test_analyze_preview_frame_is_effective_crop_box_with_rotation(self):
        marker = (100.0, 500.0, 140.0, 540.0)
        cases = [(rotation, crop) for rotation in (0, 90, 180, 270)
                 for crop in ((0, 0, 600, 800), (40, 60, 560, 760))]
        cases += [(90, (-50, -50, 560, 760)), (0, (30, 70, 650, 900))]  # crop beyond media
        for number, (rotation, crop) in enumerate(cases):
            with self.subTest(rotation=rotation, crop=crop):
                source = create_marker_fixture(self.root / f"marker-{number}.pdf", rotation=rotation,
                                               crop=crop, marker=marker)
                preview = self.root / f"marker-{number}.png"
                report = self.engine.analyze(source, preview, long_edge=800)
                self.assertEqual(report.outcome, Outcome.NONE_DETECTED, report.to_dict())
                page = report.pages[0]
                geometry = geometry_of(page)
                info = report.preview
                self.assertEqual((info["page_number"], info["render_box"], info["path"]),
                                 (1, "cropBox", str(preview)))
                self.assertEqual(info["geometry_sha256"], page["geometry_sha256"])
                self.assertEqual(max(info["width"], info["height"]), 800)
                with Image.open(preview) as opened:
                    image = opened.convert("L")
                self.assertEqual(image.size, (info["width"], info["height"]))
                dark = image.point(lambda value: 255 if value < 128 else 0).getbbox()
                rect = pdf_to_normalized(geometry, marker, render_box="cropBox")
                expected = (rect.left * info["width"], rect.top * info["height"],
                            rect.right * info["width"], rect.bottom * info["height"])
                for actual, wanted in zip(dark, expected):
                    self.assertAlmostEqual(actual, wanted, delta=2)
                # A selection built from this preview, as the app builds it, passes validation.
                selection = ManualSelection(report.document_id, report.source_sha256, report.source_size, 1,
                                            info["geometry_sha256"], "cropBox", info["width"], info["height"],
                                            (rect.left, rect.top, rect.right, rect.bottom))
                output = self.root / f"marker-{number}-out.pdf"
                result = self.engine.remove(source, output, mode="area", selection=selection)
                self.assertEqual(result.outcome, Outcome.REMOVED, result.to_dict())
                self.assertEqual(result.removed_by_kind, {"area_object": 1})

    def test_existing_preview_path_is_never_overwritten(self):
        self.source = create_fixture(self.source, watermarks=False)
        self.preview.write_bytes(b"keep")
        result = self.engine.analyze(self.source, self.preview)
        self.assertEqual((result.outcome, result.code), (Outcome.FAILED, "unsafe_or_existing_preview"))
        self.assertEqual(self.preview.read_bytes(), b"keep")
        result = self.engine.analyze(self.source, self.root / "preview.jpg")
        self.assertEqual(result.code, "unsafe_or_existing_preview")

    def test_trailing_bytes_after_eof_are_accepted(self):
        create_fixture(self.root / "plain.pdf")
        data = (self.root / "plain.pdf").read_bytes() + b"\r\n\x00\x00" + b"PRINTER JUNK " * 150
        self.source.write_bytes(data)
        detected = self.engine.detect(self.source)
        self.assertEqual(detected.outcome, Outcome.SUPPORTED_DETECTED, detected.to_dict())
        self.assertEqual(detected.source_sha256, sha256(self.source))
        self.assertGreater(detected.checks["trailing_bytes_after_eof_ignored"], 0)
        result = self.remove()
        self.assertEqual(result.outcome, Outcome.REMOVED, result.to_dict())
        with PdfReader(self.output, strict=True) as reader:
            self.assertEqual(len(reader.pages), 1)
        self.source.write_bytes((self.root / "plain.pdf").read_bytes()[:-200] + b"x" * 5000)
        self.assertEqual(self.engine.detect(self.source).outcome, Outcome.INVALID_PDF)

    def test_crop_box_beyond_media_box_is_intersected(self):
        create_fixture(self.root / "plain.pdf", page_count=2, rotations=[0, 90])
        with PdfReader(self.root / "plain.pdf", strict=True) as reader:
            writer = PdfWriter(clone_from=reader)
            writer.pages[0].cropbox = RectangleObject((-20, -30, 640, 830))
            writer.pages[1].cropbox = RectangleObject((300, 400, 900, 1000))
            writer.write(self.source)
            writer.close()
        detected = self.engine.detect(self.source)
        self.assertEqual(detected.outcome, Outcome.SUPPORTED_DETECTED, detected.to_dict())
        self.assertEqual([page["crop_box"] for page in detected.pages],
                         [[0.0, 0.0, 600.0, 800.0], [300.0, 400.0, 600.0, 800.0]])
        result = self.remove()
        self.assertEqual(result.outcome, Outcome.REMOVED, result.to_dict())
        # Page 2's watermark straddles its visible crop and is reported, not removed.
        self.assertEqual(result.removed_count, 1)
        with PdfReader(self.source, strict=True) as reader:
            disjoint = PdfWriter(clone_from=reader)
            disjoint.pages[0].cropbox = RectangleObject((700, 900, 800, 1000))
            disjoint.write(self.root / "disjoint.pdf")
            disjoint.close()
        self.assertEqual(self.engine.detect(self.root / "disjoint.pdf").outcome, Outcome.INVALID_PDF)

    def test_inherited_media_box_and_high_precision_reals(self):
        create_fixture(self.root / "plain.pdf", page_count=2, artifact="separate")
        with PdfReader(self.root / "plain.pdf", strict=True) as reader:
            writer = PdfWriter(clone_from=reader)
            pages = writer._root_object["/Pages"].get_object()
            pages[NameObject("/MediaBox")] = RectangleObject((0, 0, 600, 800))
            pages[NameObject("/Rotate")] = writer.pages[0]["/Rotate"]
            for page in writer.pages:
                # Inherited from /Pages, as many producers write them.
                del page["/MediaBox"]
                del page["/Rotate"]
                link = page["/Annots"][0].get_object()
                link[NameObject("/C")] = ArrayObject([FloatObject("0.123456789"), FloatObject("1008.789063"),
                                                      FloatObject("0.5")])
            writer.write(self.source)
            writer.close()
        with pdfium.PdfDocument(self.source) as document, closing(document[0]) as page:
            # PDFium's FPDFPage_GetMediaBox ignores inheritance; pypdfium2 falls back to Letter.
            self.assertEqual(page.get_mediabox(), (0, 0, 612, 792))
        detected = self.engine.detect(self.source)
        self.assertEqual(detected.outcome, Outcome.SUPPORTED_DETECTED, detected.to_dict())
        self.assertEqual(detected.pages[0]["media_box"], [0.0, 0.0, 600.0, 800.0])
        # Reals are written by pypdf with 8 significant digits; the graph check
        # compares at that precision instead of failing every such document.
        result = self.remove()
        self.assertEqual(result.outcome, Outcome.REMOVED, result.to_dict())
        self.assertEqual(result.removed_by_kind, {"watermark_annotation": 2, "watermark_artifact": 2})

    def test_relative_temporary_root_is_made_absolute(self):
        self.source = create_fixture(self.source)
        previous = os.getcwd()
        os.chdir(self.root)
        try:
            engine = PdfWatermarkEngine(temporary_root="jobs")
            self.assertTrue(engine.temporary_root.is_absolute())
            self.assertEqual(engine.detect("source.pdf").outcome, Outcome.SUPPORTED_DETECTED)
            self.assertEqual(engine.remove("source.pdf", "relative-out.pdf").outcome, Outcome.REMOVED)
        finally:
            os.chdir(previous)
        self.assertTrue((self.root / "relative-out.pdf").is_file())

    def test_public_exports_and_result_roundtrip(self):
        self.assertIs(pdf_watermark_engine.PdfWatermarkEngine, PdfWatermarkEngine)
        self.assertIs(pdf_watermark_engine.EngineFailure, EngineFailure)
        result = EngineResult(Outcome.REMOVED, "x", removed_count=3, artifact_count=2,
                              removed_by_kind={"area_object": 3}, pages_changed=[1, 4],
                              preview={"page_number": 1, "width": 10, "height": 20})
        self.assertEqual(EngineResult.from_dict(json.loads(json.dumps(result.to_dict()))), result)
        self.assertEqual(Limits(timeout_seconds=300).timeout_seconds, 300)
        with self.assertRaises(ValueError):
            Limits(timeout_seconds=301)


if __name__ == "__main__":
    unittest.main()

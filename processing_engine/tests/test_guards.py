from contextlib import closing
import ctypes
from dataclasses import asdict
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
from unittest.mock import Mock

import pypdfium2 as pdfium

from pdf_watermark_engine.api import PdfWatermarkEngine
from pdf_watermark_engine.geometry import PageGeometry, pdf_to_normalized
from pdf_watermark_engine.models import EngineFailure, EngineResult, Limits, Outcome
from pdf_watermark_engine.storage import BoundedWriter, publish_exclusive, snapshot_input
from fixtures import create_fixture, watermark_rect


class GuardTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="pdfwm_guard_tests_")
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)

    def test_unreadable_source_has_explicit_invalid_outcome(self):
        source = self.root / "source.pdf"
        source.write_bytes(b"fixture")
        with patch.object(Path, "open", side_effect=PermissionError("secret source path")):
            with self.assertRaises(EngineFailure) as caught:
                snapshot_input(source, self.root / "copy.pdf", Limits())
        self.assertEqual(caught.exception.outcome, Outcome.INVALID_PDF)
        self.assertEqual(str(caught.exception), "unreadable_input")

    def test_bounded_writer_refuses_partial_overflow(self):
        target = io.BytesIO()
        bounded = BoundedWriter(target, 4)
        bounded.write(b"abc")
        with self.assertRaises(EngineFailure):
            bounded.write(b"de")
        self.assertEqual(target.getvalue(), b"abc")

    def test_publication_failure_removes_temporary_copy(self):
        source, output = self.root / "validated.pdf", self.root / "public.pdf"
        source.write_bytes(b"validated fixture")
        with patch("pdf_watermark_engine.storage.os.link", side_effect=OSError("no hard links")):
            with self.assertRaises(OSError):
                publish_exclusive(source, output, 100)
        self.assertFalse(output.exists())
        self.assertEqual(list(self.root.glob(".pdfwm_*")), [])

    def test_publication_is_exclusive_and_bounded(self):
        source, output = self.root / "validated.pdf", self.root / "public.pdf"
        source.write_bytes(b"validated fixture")
        with self.assertRaises(EngineFailure):
            publish_exclusive(source, output, 2)
        self.assertFalse(output.exists())
        publish_exclusive(source, output, 100)
        self.assertEqual(output.read_bytes(), source.read_bytes())
        with self.assertRaises(EngineFailure):
            publish_exclusive(source, output, 100)
        self.assertEqual(list(self.root.glob(".pdfwm_*")), [])

    def test_hardlinked_destination_cannot_modify_original(self):
        source = create_fixture(self.root / "source.pdf")
        output = self.root / "alias.pdf"
        os.link(source, output)
        before = source.read_bytes()
        result = PdfWatermarkEngine().remove(source, output)
        self.assertEqual(result.code, "unsafe_or_existing_output")
        self.assertEqual(before, source.read_bytes())

    def test_invalid_limits_rejected(self):
        for kwargs in ({"max_pages": 0}, {"max_pages": True}, {"max_pages": 1.5},
                       {"memory_mb": 1}, {"render_long_edge": 5000},
                       {"timeout_seconds": float("nan")}):
            with self.subTest(kwargs=kwargs), self.assertRaises(ValueError):
                Limits(**kwargs)

    def test_exact_outcome_names_roundtrip_without_success_alias(self):
        self.assertEqual(len(Outcome), 7)
        for outcome in Outcome:
            original = EngineResult(outcome, "test")
            self.assertEqual(EngineResult.from_dict(original.to_dict()), original)

    def test_independent_pdfium_coordinate_oracle_all_rotations_and_crop(self):
        crop = (30, 70, 550, 750)
        path = create_fixture(self.root / "oracle.pdf", page_count=4,
                              rotations=[0, 90, 180, 270], crops=[crop] * 4)
        with pdfium.PdfDocument(path) as document:
            for index, rotation in enumerate((0, 90, 180, 270)):
                with self.subTest(rotation=rotation), closing(document[index]) as page:
                    width, height = (round(value) for value in page.get_size())
                    x0, y0, x1, y1 = watermark_rect(crop)
                    positions = []
                    for x, y in ((x0, y0), (x0, y1), (x1, y0), (x1, y1)):
                        px, py = ctypes.c_int(), ctypes.c_int()
                        success = pdfium.raw.FPDF_PageToDevice(page, 0, 0, width, height, 0,
                                                              x, y, ctypes.byref(px), ctypes.byref(py))
                        self.assertTrue(success)
                        positions.append((px.value / width, py.value / height))
                    expected = (min(p[0] for p in positions), min(p[1] for p in positions),
                                max(p[0] for p in positions), max(p[1] for p in positions))
                    rect = pdf_to_normalized(PageGeometry(index + 1, (0, 0, 600, 800), crop, rotation),
                                             (x0, y0, x1, y1), render_box="cropBox")
                    for actual, wanted in zip(asdict(rect).values(), expected):
                        self.assertAlmostEqual(actual, wanted, delta=1 / min(width, height))

    def test_cli_json_and_exit_status(self):
        source = create_fixture(self.root / "ordinary.pdf", watermarks=False)
        process = subprocess.run([sys.executable, "-m", "pdf_watermark_engine", "detect", str(source)],
                                 capture_output=True, text=True, timeout=35)
        self.assertEqual(process.returncode, 0, process.stderr)
        result = json.loads(process.stdout)
        self.assertEqual(result["outcome"], Outcome.NONE_DETECTED.value)
        self.assertEqual(result["removed_count"], 0)
        self.assertEqual(process.stderr, "")

    def fake_worker(self, response):
        worker = Mock()
        worker.returncode = 0
        worker.poll.return_value = 0
        worker.pid = 1
        worker.communicate.side_effect = response
        return worker

    def test_source_revision_is_rechecked_after_worker_completes(self):
        source = create_fixture(self.root / "source.pdf")
        jobs = self.root / "jobs"
        jobs.mkdir()
        def response(*args, **kwargs):
            source.write_bytes(b"Externally replaced document")
            return json.dumps(EngineResult(Outcome.SUPPORTED_DETECTED, "fixture").to_dict()), None
        worker = self.fake_worker(response)
        with patch("pdf_watermark_engine.api.subprocess.Popen", return_value=worker), \
                patch("pdf_watermark_engine.api.windows_job", return_value=lambda: None):
            result = PdfWatermarkEngine(temporary_root=jobs).detect(source)
        self.assertEqual(result.code, "source_changed_during_processing")
        self.assertEqual(list(jobs.iterdir()), [])

    def test_worker_cannot_report_success_with_zero_removals(self):
        source = create_fixture(self.root / "source.pdf")
        output = self.root / "result.pdf"
        def response(*args, **kwargs):
            return json.dumps(EngineResult(Outcome.REMOVED, "fixture", removed_count=0).to_dict()), None
        with patch("pdf_watermark_engine.api.subprocess.Popen", return_value=self.fake_worker(response)), \
                patch("pdf_watermark_engine.api.windows_job", return_value=lambda: None):
            result = PdfWatermarkEngine().remove(source, output)
        self.assertEqual(result.code, "invalid_success_result")
        self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()

"""The Android adapter (android/app/src/main/python/pdfwm_mobile.py), run here on the host.

On a phone the same module runs inside the app through Chaquopy. These tests prove the
adapter's JSON contract and the engine behaviour behind it; they do not prove that the
Android packaging works (that needs the APK on a device).
"""

import json
from pathlib import Path
import shutil
import sys
import tempfile
import time
import unittest

ADAPTER_DIR = Path(__file__).resolve().parents[2] / "android" / "app" / "src" / "main" / "python"
sys.path.insert(0, str(ADAPTER_DIR))

import pdfwm_mobile  # noqa: E402
from test_inprocess import BODY, OVERLAY, make_pdf, texts  # noqa: E402


class MobileAdapterTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="pdfwm_mobile_tests_")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)

    def job(self, source: Path | None = None) -> Path:
        path = self.root / f"job-{len(list(self.root.glob('job-*')))}"
        path.mkdir()
        if source is not None:
            shutil.copyfile(source, path / "original.pdf")
        return path

    def test_info_reports_versions_and_phone_limits(self):
        info = json.loads(pdfwm_mobile.info())
        self.assertEqual(info["max_file_bytes"], 40 * 1024 * 1024)
        self.assertEqual(info["max_pages"], 100)
        for key in ("python", "pypdf", "pypdfium2", "pillow"):
            self.assertTrue(info[key])

    def test_analyze_returns_the_job_description(self):
        source = make_pdf(self.root / "doc.pdf", pages=3, overlay=True)
        job = self.job(source)
        reply = json.loads(pdfwm_mobile.analyze(str(job), "doc.pdf"))
        self.assertEqual(reply["job_id"], job.name)
        self.assertEqual((reply["filename"], reply["status"], reply["page_count"]), ("doc.pdf", "ready", 3))
        self.assertFalse(reply["detection"]["auto_available"])
        self.assertEqual(reply["preview"]["coordinate_space"], "renderedPageTopLeft")
        self.assertTrue((job / "preview.png").read_bytes().startswith(b"\x89PNG"))
        self.assertTrue((job / "state.json").is_file())
        self.assertEqual(len(reply["sha256"]), 64)

    def test_area_removal_end_to_end(self):
        source = make_pdf(self.root / "doc.pdf", pages=3, overlay=True)
        job = self.job(source)
        pdfwm_mobile.analyze(str(job), "doc.pdf")
        area = json.dumps({"left": 0.30, "top": 0.44, "right": 0.62, "bottom": 0.56})
        reply = json.loads(pdfwm_mobile.remove(str(job), "area", area, "all_pages"))
        self.assertEqual(reply["status"], "succeeded", reply)
        self.assertEqual(reply["result"]["pages_changed"], [1, 2, 3])
        self.assertEqual(reply["result"]["outcome"], "watermark_removed_successfully")
        # The reply is the whole job again, so the app keeps its page count, name and detection.
        self.assertEqual((reply["filename"], reply["page_count"], reply["job_id"]), ("doc.pdf", 3, job.name))
        for number, text in enumerate(texts(job / "processed.pdf"), start=1):
            self.assertNotIn(OVERLAY, text)
            self.assertIn(f"{BODY} {number}", text)
        self.assertTrue((job / "result.png").is_file())
        # The user can try again on the same job: previous outputs are replaced, not refused.
        again = json.loads(pdfwm_mobile.remove(str(job), "area", area, "first_page"))
        self.assertEqual((again["status"], again["result"]["pages_changed"]), ("succeeded", [1]))

    def test_area_with_nothing_inside_is_nothing_removed(self):
        source = make_pdf(self.root / "doc.pdf", pages=2, overlay=True)
        job = self.job(source)
        pdfwm_mobile.analyze(str(job), "doc.pdf")
        area = json.dumps({"left": 0.05, "top": 0.85, "right": 0.30, "bottom": 0.95})
        reply = json.loads(pdfwm_mobile.remove(str(job), "area", area, "all_pages"))
        self.assertEqual(reply["status"], "nothing_removed")
        self.assertFalse((job / "processed.pdf").exists())

    def test_bad_inputs_become_errors_not_exceptions(self):
        job = self.job()
        self.assertEqual(json.loads(pdfwm_mobile.remove(str(job), "auto", "{}", "all_pages"))["error"]["kind"],
                         "not_found")
        bad = self.root / "bad.pdf"
        bad.write_bytes(b"%PDF-1.7\nnot really\n%%EOF\n")
        reply = json.loads(pdfwm_mobile.analyze(str(self.job(bad)), "bad.pdf"))
        self.assertEqual(reply["error"]["kind"], "rejected")
        self.assertIn("readable PDF", reply["error"]["message"])
        missing = json.loads(pdfwm_mobile.analyze(str(self.job()), "none.pdf"))
        self.assertEqual(missing["error"]["kind"], "not_found")
        source = make_pdf(self.root / "ok.pdf", overlay=True)
        job = self.job(source)
        pdfwm_mobile.analyze(str(job), "ok.pdf")
        reply = json.loads(pdfwm_mobile.remove(str(job), "area", '{"left": "x"}', "all_pages"))
        self.assertEqual(reply["error"]["code"], "invalid_area")

    def test_self_test_passes(self):
        reply = json.loads(pdfwm_mobile.self_test(str(self.root)))
        self.assertTrue(reply["ok"], reply["steps"])
        self.assertEqual([s["ok"] for s in reply["steps"]], [True] * len(reply["steps"]))
        self.assertFalse((self.root / "selftest").exists(), "self-test left files behind")

    def test_purge_removes_only_old_entries(self):
        old, new = self.job(), self.job()
        past = time.time() - 7200
        import os
        os.utime(old, (past, past))
        self.assertEqual(pdfwm_mobile.purge(str(self.root), 3600), 1)
        self.assertFalse(old.exists())
        self.assertTrue(new.exists())
        self.assertEqual(pdfwm_mobile.purge(str(self.root / "missing"), 1), 0)


if __name__ == "__main__":
    unittest.main()

"""Entry points the Android app calls (through Chaquopy) to remove watermarks on the phone.

Everything here runs inside the app's own process, offline. Kotlin passes plain strings and
gets JSON back, so the Dart and Kotlin layers never depend on the engine's Python types.

A *job* is one folder created by the app under its cache directory:

    <job_dir>/original.pdf   a private copy of the PDF the user picked (never modified)
    <job_dir>/preview.png    page one, rendered by PDFium (what the user draws the area on)
    <job_dir>/state.json     what `remove` needs to bind the area to that exact preview
    <job_dir>/processed.pdf  the cleaned PDF (after a successful removal)
    <job_dir>/result.png     page one of the cleaned PDF
"""

from __future__ import annotations

import json
import os
import shutil
import sys
import time
from pathlib import Path

# Limits tuned for a phone: the engine runs in the app process, so a runaway document
# could take the whole app down. The app shows these limits before a file is accepted.
MAX_INPUT_BYTES = 40 * 1024 * 1024
MAX_PAGES = 100

MESSAGES = {
    "supported_watermark_detected": "Watermark detected.",
    "watermark_removed_successfully": "Watermark removed. Everything else on the pages was checked and is unchanged.",
    "no_supported_watermark_detected": "Nothing removable was found in the chosen scope.",
    "unsupported_watermark_structure": "This watermark uses a structure that can't be removed safely.",
    "invalid_or_unreadable_pdf": "This file isn't a readable PDF.",
    "password_required": "This PDF is password protected. Remove the password and try again.",
    "processing_failed": "Processing failed. The original file is unchanged.",
}


def _limits():
    from pdf_watermark_engine.models import Limits

    return Limits(max_input_bytes=MAX_INPUT_BYTES, max_pages=MAX_PAGES, max_decoded_stream_bytes=48 * 1024 * 1024)


def _engine(job_dir: Path):
    from pdf_watermark_engine.api import PdfWatermarkEngine

    work = job_dir / "work"
    work.mkdir(parents=True, exist_ok=True)
    return PdfWatermarkEngine(_limits(), temporary_root=work, isolation="inprocess")


def _error(kind: str, code: str, message: str) -> str:
    return json.dumps({"error": {"kind": kind, "code": code, "message": message}})


def info() -> str:
    """Versions and limits; also proves that the native libraries load."""
    import PIL
    import pypdf
    import pypdfium2

    return json.dumps({
        "python": sys.version.split()[0],
        "pypdf": pypdf.__version__,
        "pypdfium2": pypdfium2.version.PYPDFIUM_INFO.version if hasattr(pypdfium2, "version") else "?",
        "pillow": PIL.__version__,
        "max_file_bytes": MAX_INPUT_BYTES,
        "max_pages": MAX_PAGES,
    })


def analyze(job_dir: str, filename: str) -> str:
    """Detect watermarks in `<job_dir>/original.pdf` and render page one. Returns the job (JSON)."""
    job = Path(job_dir)
    source = job / "original.pdf"
    if not source.is_file():
        return _error("not_found", "source_missing", "This PDF is no longer available. Choose it again.")
    try:
        preview = job / "preview.png"
        preview.unlink(missing_ok=True)
        result = _engine(job).analyze(source, preview, long_edge=1024)
    except Exception:  # the engine returns results; this only guards adapter bugs
        return _error("failed", "internal_error", MESSAGES["processing_failed"])
    outcome = result.outcome.value
    if outcome in ("invalid_or_unreadable_pdf", "password_required", "processing_failed") or not result.preview:
        return _error("rejected", result.code, MESSAGES.get(outcome, MESSAGES["processing_failed"]))
    description = {
        "job_id": job.name,
        "filename": filename,
        "size": result.source_size,
        "sha256": result.source_sha256,
        "page_count": result.page_count or 0,
        "status": "ready",
        "detection": {
            "outcome": outcome,
            "code": result.code,
            "supported_count": result.supported_count,
            "unsupported_count": result.unsupported_count,
            "artifact_count": result.artifact_count,
            "auto_available": result.supported_count + result.artifact_count > 0,
        },
        "preview": {"width": result.preview["width"], "height": result.preview["height"],
                    "coordinate_space": "renderedPageTopLeft"},
        "result": _result_block(None, None, None, 0, {}, []),
    }
    state = {
        "sha256": result.source_sha256,
        "size": result.source_size,
        "geometry_sha256": result.preview["geometry_sha256"],
        "preview_width": result.preview["width"],
        "preview_height": result.preview["height"],
        "description": description,
    }
    (job / "state.json").write_text(json.dumps(state), encoding="utf-8")
    return json.dumps(description)


def _result_block(mode, outcome, code, removed, by_kind, pages):
    return {
        "mode": mode, "outcome": outcome, "code": code,
        "message": MESSAGES.get(outcome) if outcome else None,
        "removed_count": removed, "removed_by_kind": by_kind, "pages_changed": pages,
    }


def remove(job_dir: str, mode: str, area_json: str, apply_to: str) -> str:
    """Remove watermarks (mode "auto") or everything inside an area (mode "area")."""
    from pdf_watermark_engine.models import ManualSelection, Outcome

    job = Path(job_dir)
    try:
        state = json.loads((job / "state.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return _error("not_found", "job_missing", "This document is no longer available. Choose it again.")
    selection = None
    if mode == "area":
        try:
            area = json.loads(area_json)
            selection = ManualSelection(
                document_id="sha256:" + state["sha256"], source_sha256=state["sha256"],
                source_size=state["size"], page_number=1, geometry_sha256=state["geometry_sha256"],
                render_box="cropBox", raster_width=state["preview_width"], raster_height=state["preview_height"],
                rect=(float(area["left"]), float(area["top"]), float(area["right"]), float(area["bottom"])))
        except (ValueError, KeyError, TypeError):
            return _error("rejected", "invalid_area", "The selected area isn't valid. Select it again.")
    output, result_preview = job / "processed.pdf", job / "result.png"
    output.unlink(missing_ok=True)
    result_preview.unlink(missing_ok=True)
    try:
        result = _engine(job).remove(
            job / "original.pdf", output, mode=mode, selection=selection, apply_to=apply_to,
            expected_sha256=state["sha256"], preview_png=result_preview)
    except Exception:
        return _error("failed", "internal_error", MESSAGES["processing_failed"])

    outcome = result.outcome
    if outcome == Outcome.REMOVED and output.is_file():
        status = "succeeded"
    elif outcome in (Outcome.NONE_DETECTED, Outcome.UNSUPPORTED):
        status = "nothing_removed"
    else:
        status = "failed"
    description = state["description"]
    description["status"] = status
    description["result"] = _result_block(mode, outcome.value, result.code, result.removed_count,
                                          result.removed_by_kind, result.pages_changed)
    return json.dumps(description)


def purge(root: str, older_than_seconds: float) -> int:
    """Delete job folders (and anything else) under `root` that are older than the given age."""
    base = Path(root)
    if not base.is_dir():
        return 0
    cutoff = time.time() - older_than_seconds
    removed = 0
    for entry in base.iterdir():
        try:
            if entry.stat().st_mtime < cutoff:
                shutil.rmtree(entry, ignore_errors=True) if entry.is_dir() else entry.unlink(missing_ok=True)
                removed += 1
        except OSError:
            continue
    return removed


# ---------------------------------------------------------------- self test

_SELF_TEST_BODY = "Self-test page"
_SELF_TEST_MARK = "CONFIDENTIAL"


def _self_test_pdf(path: Path) -> None:
    """A two-page PDF with an Acrobat-style watermark layer, made with pypdf only."""
    from pypdf import PdfWriter
    from pypdf.generic import (ArrayObject, DecodedStreamObject, DictionaryObject, FloatObject, NameObject)

    writer = PdfWriter()
    font = writer._add_object(DictionaryObject({
        NameObject("/Type"): NameObject("/Font"), NameObject("/Subtype"): NameObject("/Type1"),
        NameObject("/BaseFont"): NameObject("/Helvetica")}))
    fonts = DictionaryObject({NameObject("/F1"): font})
    form = DecodedStreamObject()
    form.set_data(f"BT /F1 40 Tf 150 400 Td ({_SELF_TEST_MARK}) Tj ET".encode())
    form.update({
        NameObject("/Type"): NameObject("/XObject"), NameObject("/Subtype"): NameObject("/Form"),
        NameObject("/BBox"): ArrayObject([FloatObject(0), FloatObject(0), FloatObject(612), FloatObject(792)]),
        NameObject("/Resources"): DictionaryObject({NameObject("/Font"): fonts})})
    form_ref = writer._add_object(form)
    for number in (1, 2):
        page = writer.add_blank_page(612, 792)
        content = DecodedStreamObject()
        content.set_data((f"BT /F1 12 Tf 72 720 Td ({_SELF_TEST_BODY} {number}) Tj ET\n"
                          "/Artifact <</Subtype /Watermark /Type /Pagination>> BDC q /Fm0 Do Q EMC\n").encode())
        page[NameObject("/Resources")] = DictionaryObject({
            NameObject("/Font"): fonts,
            NameObject("/XObject"): DictionaryObject({NameObject("/Fm0"): form_ref})})
        page[NameObject("/Contents")] = writer._add_object(content)
    with path.open("wb") as handle:
        writer.write(handle)


def self_test(work_dir: str) -> str:
    """Run the whole engine once on a generated PDF; proves PDFium, pypdf and Pillow work here."""
    import pypdfium2 as pdfium

    started = time.time()
    steps = []
    job = Path(work_dir) / "selftest"
    shutil.rmtree(job, ignore_errors=True)
    job.mkdir(parents=True)

    def step(name, ok, detail=""):
        steps.append({"name": name, "ok": bool(ok), "detail": detail})
        return ok

    try:
        source = job / "sample.pdf"
        _self_test_pdf(source)
        step("create sample PDF", source.is_file())
        shutil.move(str(source), str(job / "original.pdf"))
        analysis = json.loads(analyze(str(job), "sample.pdf"))
        if not step("analyze and render page 1", "error" not in analysis, json.dumps(analysis.get("error", ""))):
            raise RuntimeError("analyze failed")
        step("watermark layer detected", analysis["detection"]["auto_available"],
             f"{analysis['detection']['artifact_count']} object(s)")
        outcome = json.loads(remove(str(job), "auto", "{}", "all_pages"))
        if not step("remove watermark", outcome.get("status") == "succeeded",
                    json.dumps(outcome.get("error") or outcome["result"].get("code"))):
            raise RuntimeError("remove failed")
        with pdfium.PdfDocument(job / "processed.pdf") as document:
            texts = []
            for index in range(len(document)):
                page = document[index]
                textpage = page.get_textpage()
                texts.append(textpage.get_text_range())
                textpage.close()
                page.close()
        step("watermark text gone, page text kept",
             all(_SELF_TEST_MARK not in t and f"{_SELF_TEST_BODY} {i}" in t for i, t in enumerate(texts, 1)))
        step("result preview rendered", (job / "result.png").is_file())
    except Exception as error:  # a failed step is already recorded; keep the cause short
        steps.append({"name": "stopped", "ok": False, "detail": type(error).__name__})
    finally:
        shutil.rmtree(job, ignore_errors=True)
    return json.dumps({"ok": bool(steps) and all(s["ok"] for s in steps), "steps": steps,
                       "seconds": round(time.time() - started, 1), "versions": json.loads(info())})

"""Processing adapter that bridges the FastAPI backend with the existing
`pdf_watermark_engine` package.

Provides two public functions used by `backend.app.main`:
* `inspect(pdf_path: Path) -> Tuple[bool, str | None, int, Dict[int, int]]`
* `run(job_id: str) -> None`

The adapter uses the real engine implementation – **no fake removal**.
"""

import traceback
from pathlib import Path
from typing import Dict, Tuple

from ..config import settings
from ..database import SessionLocal
from ..models import Job, JobStatus, update_job_status, get_job

# Import the actual engine package (installed as a local module)
from processing_engine.pdf_watermark_engine import PdfWatermarkEngine, EngineResult, EngineFailure, Outcome


def _load_engine() -> PdfWatermarkEngine:
    """Create a PdfWatermarkEngine instance with default limits.
    The temporary root is the backend's TMP_DIR to keep all temporary files
    together.
    """
    return PdfWatermarkEngine(temporary_root=settings.TMP_DIR)


def inspect(pdf_path: Path) -> Tuple[bool, str | None, int, Dict[int, int]]:
    """Inspect a PDF for removable watermarks.

    Returns:
        can_remove (bool): True if the engine reports a supported watermark.
        reason (str | None): Human‑readable message if not removable.
        page_count (int): Number of pages in the document.
        rotation (dict[int, int]): Mapping of page index → rotation degrees.
    """
    engine = _load_engine()
    try:
        result: EngineResult = engine.detect(pdf_path)
    except EngineFailure as err:
        # Engine could not even read the PDF – treat as unsupported
        return False, err.code, 0, {}
    except Exception:
        # Unexpected failure – log stack trace for debugging (but do not expose)
        traceback.print_exc()
        return False, "internal_error", 0, {}

    can_remove = result.outcome == Outcome.SUPPORTED_DETECTED
    reason = None if can_remove else result.message
    page_count = result.page_count or 0
    # Build a simple rotation map; the engine puts rotation info per page in `pages`
    rotation: Dict[int, int] = {}
    for idx, page in enumerate(result.pages):
        rotation[idx] = page.get("rotation", 0)
    return can_remove, reason, page_count, rotation


def run(job_id: str) -> None:
    """Execute watermark removal for the given job.

    The function is intended to be called as a FastAPI background task.
    It updates the job status in the database and writes the processed PDF
    to `<TMP_DIR>/<job_id>/processed.pdf`.
    """
    db = SessionLocal()
    job = get_job(db, job_id)
    if not job:
        # No such job – nothing to do
        db.close()
        return

    # Update status to RUNNING (in case this was called directly)
    update_job_status(db, job_id, JobStatus.RUNNING)
    src_path = Path(settings.settings.TMP_DIR) / job_id / "original.pdf"
    dst_path = Path(settings.settings.TMP_DIR) / job_id / "processed.pdf"

    engine = _load_engine()
    try:
        # No selection object is passed – we let the engine decide based on any
        # detectable watermark. If the UI later wants to pass a specific rectangle,
        # that can be added here.
        result: EngineResult = engine.remove(src_path, dst_path)
    except EngineFailure as err:
        # Mark the job as FAILED and store the engine's code for diagnostics
        update_job_status(db, job_id, JobStatus.FAILED, detail=err.code)
        db.close()
        return
    except Exception:
        traceback.print_exc()
        update_job_status(db, job_id, JobStatus.FAILED, detail="internal_error")
        db.close()
        return

    # Successful removal – the engine already wrote the output file.
    if result.outcome == Outcome.REMOVED and dst_path.is_file():
        update_job_status(db, job_id, JobStatus.SUCCESS)
    else:
        # Engine reported success but no file – treat as failure
        update_job_status(db, job_id, JobStatus.FAILED, detail="no_output")
    db.close()

from __future__ import annotations

from dataclasses import asdict
import json
import logging
import os
from pathlib import Path
import subprocess
import sys
import tempfile

from .isolation import windows_job
from .models import APPLY_TO, REMOVAL_MODES, EngineFailure, EngineResult, Limits, ManualSelection, Outcome
from .storage import file_sha256, publish_exclusive, snapshot_input


def _unsafe_destination(path: Path, suffix: str, *others: Path) -> bool:
    return (path.exists() or path.is_symlink() or path.suffix.lower() != suffix or
            any(other is not None and path.resolve() == other.resolve() for other in others))


ISOLATIONS = ("process", "inprocess")


def _run_in_process(request, limits: Limits) -> EngineResult:
    """Run a job in the calling process. Used on Android, which cannot start a Python worker.

    There is no memory limit and no hard timeout here: the caller (the app) bounds the
    input size and page count, and a native PDFium call cannot be interrupted anyway.
    """
    from .core import run_job

    previous = logging.root.manager.disable
    logging.disable(logging.CRITICAL)  # parser warnings must never expose document data
    try:
        result = run_job(request, limits, in_process=True)
    except EngineFailure as error:
        result = EngineResult(error.outcome, error.code)
    except (MemoryError, RecursionError):
        result = EngineResult(Outcome.FAILED, "memory_or_depth_limit")
    except Exception:
        result = EngineResult(Outcome.FAILED, "parser_or_validation_failed")
    finally:
        logging.disable(previous)
    # Same round trip as the worker protocol, so both modes return identical types.
    return EngineResult.from_dict(json.loads(json.dumps(result.to_dict(), allow_nan=False)))


class PdfWatermarkEngine:
    """Run detection, preview analysis and removal in an isolated worker.

    Public methods never raise :class:`EngineFailure`; they return an
    :class:`EngineResult` whose ``outcome`` and ``code`` explain the result.

    ``isolation="process"`` (default) runs each job in a resource-limited worker
    process. ``isolation="inprocess"`` runs it in the calling process; it exists for
    Android, where the engine is embedded in the app and no worker can be started.
    """

    def __init__(self, limits: Limits | None = None, *, temporary_root: str | Path | None = None,
                 isolation: str = "process"):
        if isolation not in ISOLATIONS:
            raise ValueError("isolation must be 'process' or 'inprocess'")
        self.isolation = isolation
        self.limits = limits or Limits()
        # Relative roots break the worker's job-directory check on Python 3.11,
        # where tempfile.mkdtemp(dir=relative) returns a relative path.
        self.temporary_root = Path(temporary_root).resolve() if temporary_root is not None else None

    def detect(self, source: str | Path, *, expected_sha256: str | None = None) -> EngineResult:
        return self._run("detect", source, expected_sha256=expected_sha256)

    def analyze(self, source: str | Path, preview_png: str | Path, *, long_edge: int = 1024,
                expected_sha256: str | None = None) -> EngineResult:
        """Detect, and publish a PNG of page one (crop box, rotation, annotations)."""
        return self._run("analyze", source, preview=preview_png, long_edge=long_edge,
                         expected_sha256=expected_sha256)

    def remove(self, source: str | Path, output: str | Path, *, mode: str = "auto",
               selection: ManualSelection | None = None, apply_to: str = "all_pages",
               expected_sha256: str | None = None, preview_png: str | Path | None = None) -> EngineResult:
        return self._run("remove", source, output=output, mode=mode, selection=selection,
                         apply_to=apply_to, expected_sha256=expected_sha256, preview=preview_png)

    def _run_in_worker(self, request, job: Path) -> EngineResult:
        """Run the job in a resource-limited worker process started inside ``job``."""
        environment = dict(os.environ)
        environment["PYTHONPATH"] = str(Path(__file__).resolve().parent.parent)
        arguments = [sys.executable, "-m", "pdf_watermark_engine.worker"]
        kwargs = {"stdin": subprocess.PIPE, "stdout": subprocess.PIPE,
                  "stderr": subprocess.DEVNULL, "text": True, "encoding": "utf-8",
                  "cwd": job, "env": environment}
        if os.name == "nt":
            kwargs["creationflags"] = subprocess.CREATE_NO_WINDOW
        process = subprocess.Popen(arguments, **kwargs)
        close_job = None
        try:
            if os.name == "nt":
                # Worker waits on stdin until this guard has been attached.
                close_job = windows_job(process.pid, self.limits.memory_mb)
            try:
                stdout, _ = process.communicate(json.dumps(request), timeout=self.limits.timeout_seconds)
            except subprocess.TimeoutExpired:
                process.kill()
                process.communicate()
                raise EngineFailure(Outcome.FAILED, "processing_timeout") from None
            if process.returncode != 0 or len(stdout) > 4 * 1024 * 1024:
                raise EngineFailure(Outcome.FAILED, "worker_failed_or_resource_limit")
            return EngineResult.from_dict(json.loads(stdout))
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate()
            if close_job:
                close_job()

    def _run(self, action, source, *, output=None, mode="auto", selection=None, apply_to="all_pages",
             expected_sha256=None, preview=None, long_edge=1024):
        result = None
        in_process = self.isolation == "inprocess"
        try:
            if mode not in REMOVAL_MODES or apply_to not in APPLY_TO:
                raise EngineFailure(Outcome.FAILED, "invalid_mode_or_scope")
            if selection is not None and not isinstance(selection, ManualSelection):
                raise EngineFailure(Outcome.FAILED, "invalid_or_ambiguous_manual_mapping")
            if action == "remove" and mode == "area" and selection is None:
                raise EngineFailure(Outcome.FAILED, "area_selection_required")
            if isinstance(long_edge, bool) or not isinstance(long_edge, int) or not 16 <= long_edge <= 4096:
                raise EngineFailure(Outcome.FAILED, "invalid_preview_size")
            original = Path(source).absolute()
            destination = Path(output).absolute() if output is not None else None
            preview_path = Path(preview).absolute() if preview is not None else None
            if original.is_symlink():
                raise EngineFailure(Outcome.INVALID_PDF, "symlink_input_not_supported")
            if destination is not None and _unsafe_destination(destination, ".pdf", original):
                raise EngineFailure(Outcome.FAILED, "unsafe_or_existing_output")
            if preview_path is not None and _unsafe_destination(preview_path, ".png", original, destination):
                raise EngineFailure(Outcome.FAILED, "unsafe_or_existing_preview")
            with tempfile.TemporaryDirectory(prefix="pdfwm_", dir=self.temporary_root) as directory:
                job = Path(directory).resolve()
                sha256, size = snapshot_input(original, job / "input.pdf", self.limits)
                if expected_sha256 is not None and expected_sha256 != sha256:
                    raise EngineFailure(Outcome.FAILED, "document_revision_mismatch")
                request = {"action": action, "job": str(job), "sha256": sha256, "size": size,
                           "limits": asdict(self.limits),
                           "selection": asdict(selection) if selection is not None else None,
                           "mode": mode, "apply_to": apply_to, "long_edge": long_edge,
                           "preview": preview_path is not None}
                if self.isolation == "inprocess":
                    result = _run_in_process(request, self.limits)
                else:
                    result = self._run_in_worker(request, job)
                current_sha, current_size = file_sha256(original, self.limits.max_input_bytes)
                if (current_sha, current_size) != (sha256, size):
                    raise EngineFailure(Outcome.FAILED, "source_changed_during_processing")
                result.checks["original_hash_unchanged"] = True
                removed = result.outcome == Outcome.REMOVED
                if removed and (action != "remove" or destination is None or result.removed_count <= 0 or
                                result.removed_count != sum(result.removed_by_kind.values() or [0]) or
                                not result.pages_changed):
                    raise EngineFailure(Outcome.FAILED, "invalid_success_result")
                wants_preview = preview_path is not None and (action == "analyze" or removed)
                if wants_preview and (result.preview is None or not (job / "preview.png").is_file()):
                    if action == "analyze" and result.outcome in (Outcome.INVALID_PDF, Outcome.PASSWORD_REQUIRED,
                                                                  Outcome.FAILED):
                        return result
                    raise EngineFailure(Outcome.FAILED, "preview_not_rendered")
                if not wants_preview:
                    result.preview = None
                published_preview = False
                try:
                    if wants_preview:
                        publish_exclusive(job / "preview.png", preview_path, self.limits.max_output_bytes,
                                          rename_fallback=in_process)
                        published_preview = True
                        result.preview["path"] = str(preview_path)
                    if removed:
                        staged = job / "processed.pdf"
                        processed_sha, _ = file_sha256(staged, self.limits.max_output_bytes)
                        publish_exclusive(staged, destination, self.limits.max_output_bytes,
                                          rename_fallback=in_process)
                        result.output_path = str(destination)
                        result.output_sha256 = processed_sha
                        result.checks["exclusive_validated_output"] = True
                except BaseException:
                    if published_preview:
                        # Only ever our own exclusively created file.
                        preview_path.unlink(missing_ok=True)
                    raise
                return result
        except EngineFailure as error:
            return EngineResult(error.outcome, error.code)
        except (OSError, ValueError, TypeError, KeyError):
            return EngineResult(Outcome.FAILED, "io_configuration_or_worker_error")

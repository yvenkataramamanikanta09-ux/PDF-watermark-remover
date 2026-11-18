from __future__ import annotations

from dataclasses import asdict
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

from .isolation import windows_job
from .models import EngineFailure, EngineResult, Limits, ManualSelection, Outcome
from .storage import file_sha256, publish_exclusive, snapshot_input


class PdfWatermarkEngine:
    def __init__(self, limits: Limits | None = None, *, temporary_root: str | Path | None = None):
        self.limits = limits or Limits()
        self.temporary_root = temporary_root

    def detect(self, source: str | Path, *, expected_sha256: str | None = None) -> EngineResult:
        return self._run("detect", source, None, None, expected_sha256)

    def remove(self, source: str | Path, output: str | Path, *,
               selection: ManualSelection | None = None,
               expected_sha256: str | None = None) -> EngineResult:
        return self._run("remove", source, output, selection, expected_sha256)

    def _run(self, action, source, output, selection, expected_sha256):
        result = None
        try:
            original = Path(source).absolute()
            destination = Path(output).absolute() if output is not None else None
            if original.is_symlink():
                raise EngineFailure(Outcome.INVALID_PDF, "symlink_input_not_supported")
            if destination is not None:
                if (original.resolve() == destination.resolve() or destination.exists() or
                        destination.is_symlink() or destination.suffix.lower() != ".pdf"):
                    raise EngineFailure(Outcome.FAILED, "unsafe_or_existing_output")
            with tempfile.TemporaryDirectory(prefix="pdfwm_", dir=self.temporary_root) as directory:
                job = Path(directory)
                sha256, size = snapshot_input(original, job / "input.pdf", self.limits)
                if expected_sha256 is not None and expected_sha256 != sha256:
                    raise EngineFailure(Outcome.FAILED, "document_revision_mismatch")
                request = {"action": action, "job": str(job), "sha256": sha256, "size": size,
                           "limits": asdict(self.limits),
                           "selection": asdict(selection) if selection is not None else None}
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
                    result = EngineResult.from_dict(json.loads(stdout))
                finally:
                    if process.poll() is None:
                        process.kill()
                        process.communicate()
                    if close_job:
                        close_job()
                current_sha, current_size = file_sha256(original, self.limits.max_input_bytes)
                if (current_sha, current_size) != (sha256, size):
                    raise EngineFailure(Outcome.FAILED, "source_changed_during_processing")
                result.checks["original_hash_unchanged"] = True
                if result.outcome == Outcome.REMOVED:
                    if action != "remove" or destination is None or result.removed_count <= 0:
                        raise EngineFailure(Outcome.FAILED, "invalid_success_result")
                    staged = job / "processed.pdf"
                    processed_sha, _ = file_sha256(staged, self.limits.max_output_bytes)
                    publish_exclusive(staged, destination, self.limits.max_output_bytes)
                    result.output_path = str(destination)
                    result.output_sha256 = processed_sha
                    result.checks["exclusive_validated_output"] = True
                return result
        except EngineFailure as error:
            return EngineResult(error.outcome, error.code)
        except (OSError, ValueError, TypeError, KeyError):
            return EngineResult(Outcome.FAILED, "io_configuration_or_worker_error")

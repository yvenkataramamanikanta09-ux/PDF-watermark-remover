from __future__ import annotations

import hashlib
import os
from pathlib import Path
import tempfile

from .models import EngineFailure, Limits, Outcome

CHUNK = 1024 * 1024


def file_sha256(path: Path, max_bytes: int) -> tuple[str, int]:
    digest = hashlib.sha256()
    size = 0
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(CHUNK), b""):
            size += len(chunk)
            if size > max_bytes:
                raise EngineFailure(Outcome.FAILED, "input_size_limit")
            digest.update(chunk)
    return digest.hexdigest(), size


def snapshot_input(source: Path, target: Path, limits: Limits) -> tuple[str, int]:
    if source.is_symlink() or not source.is_file():
        raise EngineFailure(Outcome.INVALID_PDF, "unreadable_input")
    digest = hashlib.sha256()
    size = 0
    try:
        original = source.open("rb")
    except OSError:
        raise EngineFailure(Outcome.INVALID_PDF, "unreadable_input") from None
    with original, target.open("xb") as output:
        before = os.fstat(original.fileno())
        if before.st_size <= 0:
            raise EngineFailure(Outcome.INVALID_PDF, "empty_input")
        if before.st_size > limits.max_input_bytes:
            raise EngineFailure(Outcome.FAILED, "input_size_limit")
        for chunk in iter(lambda: original.read(CHUNK), b""):
            size += len(chunk)
            if size > limits.max_input_bytes:
                raise EngineFailure(Outcome.FAILED, "input_size_limit")
            digest.update(chunk)
            output.write(chunk)
        after = os.fstat(original.fileno())
        if (before.st_size, before.st_mtime_ns, before.st_ino) != (after.st_size, after.st_mtime_ns, after.st_ino):
            raise EngineFailure(Outcome.FAILED, "source_changed_during_snapshot")
    if size != before.st_size:
        raise EngineFailure(Outcome.FAILED, "source_changed_during_snapshot")
    return digest.hexdigest(), size


class BoundedWriter:
    def __init__(self, stream, maximum: int):
        self.stream = stream
        self.maximum = maximum

    def write(self, data):
        if self.stream.tell() + len(data) > self.maximum:
            raise EngineFailure(Outcome.FAILED, "output_size_limit")
        return self.stream.write(data)

    def __getattr__(self, name):
        return getattr(self.stream, name)


def publish_exclusive(staged: Path, output: Path, maximum: int) -> None:
    """Same-directory staging + atomic exclusive hard link; never overwrite."""
    if output.exists() or output.is_symlink() or not output.parent.is_dir():
        raise EngineFailure(Outcome.FAILED, "output_exists_or_directory_unavailable")
    descriptor, temporary = tempfile.mkstemp(prefix=".pdfwm_", suffix=".tmp", dir=output.parent)
    temporary = Path(temporary)
    published = False
    try:
        with os.fdopen(descriptor, "wb") as target, staged.open("rb") as source:
            count = 0
            for chunk in iter(lambda: source.read(CHUNK), b""):
                count += len(chunk)
                if count > maximum:
                    raise EngineFailure(Outcome.FAILED, "output_size_limit")
                target.write(chunk)
            target.flush()
            os.fsync(target.fileno())
        # Both files are on the destination filesystem. Unsupported hard links
        # fail safely instead of falling back to an incomplete public PDF.
        os.link(temporary, output)
        published = True
    finally:
        temporary.unlink(missing_ok=True)
    if not published:
        raise EngineFailure(Outcome.FAILED, "atomic_publication_failed")

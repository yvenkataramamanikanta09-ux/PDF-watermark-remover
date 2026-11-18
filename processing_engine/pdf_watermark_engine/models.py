from __future__ import annotations

from dataclasses import asdict, dataclass, field
from enum import StrEnum
import math
from typing import Any


class Outcome(StrEnum):
    SUPPORTED_DETECTED = "supported_watermark_detected"
    REMOVED = "watermark_removed_successfully"
    NONE_DETECTED = "no_supported_watermark_detected"
    UNSUPPORTED = "unsupported_watermark_structure"
    INVALID_PDF = "invalid_or_unreadable_pdf"
    PASSWORD_REQUIRED = "password_required"
    FAILED = "processing_failed"


MESSAGES = {
    Outcome.SUPPORTED_DETECTED: "Supported watermark detected",
    Outcome.REMOVED: "Watermark removed successfully",
    Outcome.NONE_DETECTED: "No supported watermark detected",
    Outcome.UNSUPPORTED: "Unsupported watermark structure",
    Outcome.INVALID_PDF: "Invalid or unreadable PDF",
    Outcome.PASSWORD_REQUIRED: "Password required",
    Outcome.FAILED: "Processing failed",
}


@dataclass(frozen=True)
class Limits:
    max_input_bytes: int = 64 * 1024 * 1024
    max_output_bytes: int = 128 * 1024 * 1024
    max_pages: int = 100
    max_objects: int = 50_000
    max_annotations: int = 2_000
    max_graph_depth: int = 64
    max_decoded_stream_bytes: int = 64 * 1024 * 1024
    max_appearance_bytes: int = 2 * 1024 * 1024
    memory_mb: int = 768
    timeout_seconds: float = 30.0
    render_long_edge: int = 1024

    def __post_init__(self) -> None:
        for name, value in asdict(self).items():
            if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or value <= 0:
                raise ValueError(f"Invalid processing limit: {name}")
            if name != "timeout_seconds" and not isinstance(value, int):
                raise ValueError(f"Integer limit required: {name}")
        if not 128 <= self.memory_mb <= 8192 or self.render_long_edge > 4096:
            raise ValueError("Unsafe memory/render limit")


@dataclass(frozen=True)
class ManualSelection:
    """An attested preview frame, not Stage 5's unbound session-only payload.

    render_box must be explicitly supplied by a verified renderer contract; it
    must never be inferred solely from a raster's aspect ratio.
    """

    document_id: str
    source_sha256: str
    source_size: int
    page_number: int
    geometry_sha256: str
    render_box: str
    raster_width: int
    raster_height: int
    rect: tuple[float, float, float, float]
    coordinate_space: str = "renderedPageTopLeft"

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> ManualSelection:
        expected = set(cls.__dataclass_fields__)
        if set(data) - expected:
            raise ValueError("Unknown manual selection fields")
        data = dict(data)
        data["rect"] = tuple(data["rect"])
        return cls(**data)


@dataclass
class EngineResult:
    outcome: Outcome
    code: str
    source_sha256: str | None = None
    source_size: int | None = None
    document_id: str | None = None
    page_count: int | None = None
    supported_count: int = 0
    unsupported_count: int = 0
    removed_count: int = 0
    output_path: str | None = None
    output_sha256: str | None = None
    candidates: list[dict[str, Any]] = field(default_factory=list)
    pages: list[dict[str, Any]] = field(default_factory=list)
    checks: dict[str, Any] = field(default_factory=dict)

    @property
    def message(self) -> str:
        return MESSAGES[self.outcome]

    def to_dict(self) -> dict[str, Any]:
        result = asdict(self)
        result["outcome"] = self.outcome.value
        result["message"] = self.message
        return result

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> EngineResult:
        data = dict(data)
        data.pop("message", None)
        data["outcome"] = Outcome(data["outcome"])
        return cls(**data)


class EngineFailure(Exception):
    def __init__(self, outcome: Outcome, code: str):
        # No parser exception strings, document contents, or filesystem paths.
        self.outcome = outcome
        self.code = code
        super().__init__(code)

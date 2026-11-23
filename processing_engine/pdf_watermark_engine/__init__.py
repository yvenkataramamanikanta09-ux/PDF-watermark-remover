"""Local PDF watermark engine: annotations, Acrobat watermark artifacts, selected areas."""

from .api import PdfWatermarkEngine
from .models import EngineFailure, EngineResult, Limits, ManualSelection, Outcome

__all__ = ["EngineFailure", "EngineResult", "Limits", "ManualSelection", "Outcome", "PdfWatermarkEngine"]

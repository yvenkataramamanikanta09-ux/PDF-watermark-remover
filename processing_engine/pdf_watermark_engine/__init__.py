"""Local, annotation-only engine. No Flutter, HTTP, or removal UI integration."""

from .models import EngineResult, Limits, ManualSelection, Outcome

__all__ = ["EngineResult", "Limits", "ManualSelection", "Outcome"]

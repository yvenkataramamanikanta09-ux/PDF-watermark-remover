from __future__ import annotations

import argparse
import json
from pathlib import Path

from .api import PdfWatermarkEngine
from .models import EngineResult, ManualSelection, Outcome


def main(argv=None):
    parser = argparse.ArgumentParser(description="Conservative PDF watermark-annotation engine; no redaction.")
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("detect", "remove"):
        command = commands.add_parser(name)
        command.add_argument("input", type=Path)
        command.add_argument("--expected-sha256")
        if name == "remove":
            command.add_argument("output", type=Path)
            command.add_argument("--selection", type=Path)
    args = parser.parse_args(argv)
    engine = PdfWatermarkEngine()
    if args.command == "detect":
        result = engine.detect(args.input, expected_sha256=args.expected_sha256)
    else:
        try:
            selection = None
            if args.selection:
                if args.selection.stat().st_size > 16 * 1024:
                    raise ValueError("selection too large")
                selection = ManualSelection.from_dict(json.loads(args.selection.read_text(encoding="utf-8")))
            result = engine.remove(args.input, args.output, selection=selection,
                                   expected_sha256=args.expected_sha256)
        except (OSError, TypeError, ValueError, KeyError):
            result = EngineResult(Outcome.FAILED, "invalid_manual_selection_file")
    print(json.dumps(result.to_dict(), indent=2, allow_nan=False))
    return 0 if result.outcome in (Outcome.REMOVED, Outcome.SUPPORTED_DETECTED,
                                  Outcome.NONE_DETECTED, Outcome.UNSUPPORTED) else 2


if __name__ == "__main__":
    raise SystemExit(main())

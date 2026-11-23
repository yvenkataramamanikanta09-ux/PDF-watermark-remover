from __future__ import annotations

import argparse
import json
from pathlib import Path

from .api import PdfWatermarkEngine
from .models import APPLY_TO, REMOVAL_MODES, EngineResult, Limits, ManualSelection, Outcome


def main(argv=None):
    parser = argparse.ArgumentParser(description="Conservative PDF watermark engine; no redaction.")
    parser.add_argument("--timeout", type=float, default=None, help="worker timeout in seconds (max 300)")
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("detect", "analyze", "remove"):
        command = commands.add_parser(name)
        command.add_argument("input", type=Path)
        command.add_argument("--expected-sha256")
        if name == "analyze":
            command.add_argument("preview", type=Path, help="new .png path for the page-one preview")
            command.add_argument("--long-edge", type=int, default=1024)
        if name == "remove":
            command.add_argument("output", type=Path)
            command.add_argument("--selection", type=Path)
            command.add_argument("--mode", choices=REMOVAL_MODES, default="auto")
            command.add_argument("--apply-to", choices=APPLY_TO, default="all_pages")
            command.add_argument("--preview", type=Path)
    args = parser.parse_args(argv)
    try:
        engine = PdfWatermarkEngine(Limits(timeout_seconds=args.timeout) if args.timeout else None)
    except ValueError:
        print(json.dumps(EngineResult(Outcome.FAILED, "invalid_limits").to_dict(), indent=2))
        return 2
    if args.command == "detect":
        result = engine.detect(args.input, expected_sha256=args.expected_sha256)
    elif args.command == "analyze":
        result = engine.analyze(args.input, args.preview, long_edge=args.long_edge,
                                expected_sha256=args.expected_sha256)
    else:
        try:
            selection = None
            if args.selection:
                if args.selection.stat().st_size > 16 * 1024:
                    raise ValueError("selection too large")
                selection = ManualSelection.from_dict(json.loads(args.selection.read_text(encoding="utf-8")))
            result = engine.remove(args.input, args.output, mode=args.mode, selection=selection,
                                   apply_to=args.apply_to, expected_sha256=args.expected_sha256,
                                   preview_png=args.preview)
        except (OSError, TypeError, ValueError, KeyError):
            result = EngineResult(Outcome.FAILED, "invalid_manual_selection_file")
    print(json.dumps(result.to_dict(), indent=2, allow_nan=False))
    return 0 if result.outcome in (Outcome.REMOVED, Outcome.SUPPORTED_DETECTED,
                                  Outcome.NONE_DETECTED, Outcome.UNSUPPORTED) else 2


if __name__ == "__main__":
    raise SystemExit(main())

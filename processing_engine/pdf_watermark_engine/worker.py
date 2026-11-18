"""Private stdin/stdout worker protocol; not a network endpoint."""
import json
import logging
import sys


def main() -> None:
    # No parser/native renderer imports or PDF reads before receiving the guarded
    # parent's bounded request. Parser warnings never expose document data.
    logging.disable(logging.CRITICAL)
    try:
        request = json.loads(sys.stdin.read(64 * 1024))
        from .models import EngineFailure, EngineResult, Limits, Outcome
        from .isolation import posix_limits
        limits = Limits(**request["limits"])
        posix_limits(limits.memory_mb, limits.timeout_seconds)
        from .core import run_job
        try:
            result = run_job(request, limits)
        except EngineFailure as error:
            result = EngineResult(error.outcome, error.code)
        except (MemoryError, RecursionError):
            result = EngineResult(Outcome.FAILED, "memory_or_depth_limit")
        except Exception:
            result = EngineResult(Outcome.FAILED, "parser_or_validation_failed")
        sys.stdout.write(json.dumps(result.to_dict(), allow_nan=False))
    except BaseException:
        sys.exit(2)


if __name__ == "__main__":
    main()

# Stage 6A verification

Verified on 2026-11-14 on Windows 11 with Python 3.14.5. This is a separate
local engine; Flutter integration is not included.

## Executed checks

| Check | Actual result |
| --- | --- |
| `processing_engine/.venv/Scripts/python.exe -m unittest discover -s processing_engine/tests -v` | **66 tests passed**, 81.999 seconds; no failures or skips. |
| Geometry unit tests | 19 passed: rotations, crop/media frames, negative origins, UserUnit, bounds, raster aspect, stale geometry and invalid coordinates. |
| Engine integration tests | 36 passed: actual native rendering/removal, ordinary content preservation, all outcomes, manual scope, multipage/nested page trees, malformed/encrypted/signed inputs and limits. |
| Storage/protocol/independent-oracle tests | 11 passed: publication safety, cleanup, unreadable input, hard-link aliases, source mutation, zero-removal rejection, CLI JSON and native PDFium coordinate mapping. |
| `processing_engine/.venv/Scripts/python.exe -m pip check` | No broken requirements found. |
| Python source AST check | All 19 implementation/test/demo Python files parsed. |
| `processing_engine/.venv/Scripts/python.exe processing_engine/tools/generate_demo.py` | Four real watermark annotations removed; all four pages independently verified. |
| PNG review | All four before/after pages visually inspected; red watermark removed, underlying blue chart and other content retained. |
| Existing project SHA-256 comparison | 176 baseline files checked. An earlier check found only this stage's root `README.md` edit. The final check found 173 unchanged files plus `README.md`, `pubspec.yaml` and `pubspec.lock` changed. The two dependency manifests changed outside the Stage 6A edits and were left untouched. Flutter sources/tests/assets/design references and platform configuration still match. |

The full local test transcript is `../build/stage-six-a-tests.log`. The 66 test
methods include additional table-driven subcases. Flutter analyze/test, Android
build and emulator checks were not rerun for this Python-only stage; the
previously reported 170 Flutter tests are a baseline, not a new Stage 6A run.
The POSIX isolation branch was not executed on this Windows host.

At the final check, `pubspec.yaml` included `http: ^1.2.0` and no longer listed
`pdfx`; `pubspec.lock` also changed. No Flutter dependency command or manifest
edit was performed by this Stage 6A implementation. These concurrent changes
are outside the engine file inventory. Review their intended scope before
relying on the previous Flutter dependency/test baseline; current Flutter
compatibility is not asserted by the Python test results.

## Actual before-and-after evidence

The demonstration is locally generated, deterministic and contains four pages
rotated 0, 90, 180 and 270 degrees. Pages two through four use offset crop boxes.
Each page contains selectable ordinary text, an embedded RGB image, a blue chart
under the watermark, a link, a review note and an ordinary approval stamp.

| Evidence | Before | After |
| --- | --- | --- |
| PDF | [Original fixture](../output/pdf/stage6a-before.pdf) | [Processed output](../output/pdf/stage6a-after.pdf) |
| Bytes | 10,312 | 9,041 |
| Pages | 4 | 4 |
| Explicit `/Watermark` annotations | 4 | **0** |
| Ordinary annotations | 12 | **12** |

Original SHA-256 before and after processing:

```text
25fdd93323ede06d1502c1c0959645bd33d16b41d0572c10bece1d0394cb9aaf
```

Processed SHA-256:

```text
87986e81af909f837c82fee73196ffb9a27fdedb72d4db33c78faa27d50d0fcb
```

Automated PDFium checks independently confirm watermark annotation absence,
page count, rotations, boxes and unchanged extracted text. **Every processed
page is pixel-identical, with ordinary annotations enabled, to a separately
generated fixture containing the same content without watermark annotations.**
Every source page differs visibly from its processed page. Additional checks
compare raw content/image bytes, links/notes/stamps and the full logical
non-watermark graph. The engine also checks all underlying page renders and
rejects output if preservation cannot be established.

The [machine-readable evidence](../output/pdf/stage6a-evidence.json) records
versions, all checks, counts, rectangles, crop boxes, rotations and hashes.
The [comparison image](../output/pdf/stage6a-comparison.png) shows all four pages.
No white rectangles, redactions or rasterized replacement pages were used.

## Changed files

- Updated root `README.md` with the separate engine and evidence links.
- Added `processing_engine/.gitignore`, `pyproject.toml`, `README.md`,
  `DEPENDENCIES.md`, this verification report and `CHANGED_FILES.txt`.
- Added `processing_engine/pdf_watermark_engine/`: `__init__.py`, `__main__.py`,
  `api.py`, `worker.py`, `isolation.py`, `models.py`, `storage.py`, `document.py`,
  `annotations.py`, `geometry.py`, `rendering.py`, `core.py`, `cli.py`.
- Added `processing_engine/tests/`: `fixtures.py`, `verification.py`,
  `test_geometry.py`, `test_engine.py`, `test_guards.py`.
- Added `processing_engine/tools/generate_demo.py`.
- Added `processing_engine/third_party/` notice copies for pypdf 7.1.0,
  pypdfium2 5.15.2/PDFium and Pillow 12.3.0, copied from installed distributions.
- Added four evidence artifacts under `output/pdf/`: the original PDF,
  processed PDF, comparison PNG and JSON verification manifest.

The [exact file inventory](CHANGED_FILES.txt) includes all notice files. The
local `.venv`, generated Python caches/egg metadata and `build/` logs are
development artifacts, not application source changes. Automatic approval
review rejected workspace cleanup commands with `blocked by policy`. Eight
generated verification intermediates remain under `../tmp/pdfs/stage6a/` and
`../tmp/pdfs/stage6a-final-verification/`. These contain only locally generated
fixtures and reproduced evidence. Engine-owned job/staging cleanup passed its
automated tests; this restriction affected manual workspace cleanup only.

## Limits before integration

Success is restricted to eligible **`/Subtype /Watermark` annotation objects**.
It does not cover ordinary/custom stamps, flattened text/image/vector
watermarks, OCG layers, fixed-print/dependent/hidden/locked annotation forms,
encryption or signed-document rewriting. Some valid but unusual PDFs may fail
strict parsing or preservation checks; no output is published in those cases.
These tests establish the supported fixture scope and do not establish
universal PDF conformance, all-viewer equivalence or production sandboxing.

Manual selection filters supported annotation rectangles on page one; it is
not an arbitrary content eraser. Stage 5's session-only identity and raster do
not yet establish an engine-safe frame. Before Stage 6B, bind selections to the
full source SHA-256/size and verified crop/media/rotation metadata, isolate
public-input workers, implement owned-artifact retention/cancellation and review
the shipped dependency notices. See [the integration proposal](README.md#recommended-stage-6b-architecture-not-implemented)
and [licensing evaluation](DEPENDENCIES.md).

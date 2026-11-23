# Verification

## 0.2.0: watermark artifacts, area mode and preview (2026-11-18)

Verified on Windows 10 Pro 10.0.19045 with Python 3.13.2 (64-bit) in a fresh
`processing_engine/.venv`. Installed: pypdf 7.1.0, pypdfium2 5.15.2 (PDFium
159.0.8149.0@sourcebuild-toolchained) and Pillow 12.3.0. Python 3.11 was not
available on this host. All sources were parsed with
`ast.parse(..., feature_version=(3, 11))`, but they were not executed on 3.11.

| Command | Actual result |
| --- | --- |
| `python -m venv processing_engine/.venv`, then `processing_engine/.venv/Scripts/python.exe -m pip install -e "./processing_engine[verify]"` | Installed pdf-watermark-engine 0.2.0 with the three pinned dependencies. |
| `processing_engine/.venv/Scripts/python.exe -m pip check` | No broken requirements found. |
| Baseline before any change: `processing_engine/.venv/Scripts/python.exe -m unittest discover -s processing_engine/tests` | 66 tests, OK, 97.9 s. |
| Final: `processing_engine/.venv/Scripts/python.exe -m unittest discover -s processing_engine/tests -v` | **94 tests, OK, 329.5 s**, no failures and no skips. That is the 66 existing tests unchanged, plus 22 in `test_content_removal.py` and 6 in `test_content_unit.py`. |
| 50-page area removal (`test_area_mode_fifty_pages_within_worker_timeout`, `Limits(timeout_seconds=180)`) | 4.3 s in the final suite run (6.5 s in an earlier run) for 100 objects on 50 pages. This covers the worker and validation of 50 × 2 renders and text pages, timed around `remove()`. |
| The same 50-page document with **default** `Limits()` (30 s timeout), in a separate script | `analyze` took 2.0 s. `remove(mode="area")` took 4.7 s and removed 100 objects. The default timeout of 30 s was therefore not changed. |
| AST check of all 23 engine, test and tool Python files with `feature_version=(3, 11)` | All parsed. |
| `grep -i "fitz\|pymupdf"` over the engine sources and `pyproject.toml` | No matches. |

New automated coverage (`tests/test_content_removal.py`, `tests/test_content_unit.py`):

- **Acrobat watermark artifacts.** Three styles are tested: a Form XObject in
  an appended content stream with an inline `/Artifact` dictionary, the same
  with a named `/Properties` entry, and text objects inside the body stream.
  The pages use rotations 0/90/270 and offset crop boxes. `detect` and
  `analyze` report `artifact_count`. Automatic removal produces pages that are
  **pixel-identical** (annotations drawn) and text-identical to the same
  fixture generated without the watermark. `(CONFIDENTIAL)` is absent from the
  output bytes, and a second `detect` finds nothing.
- **Artifact edge cases.** An artifact together with a `/Watermark` annotation
  is removed in one output. `apply_to="first_page"` leaves pages 2 and 3
  identical. A signed document is refused.
- **Area removal of overlays.** A rotated, semi-transparent text overlay and an
  image overlay on 3 pages (rotation 90 with different crops) are removed using
  a selection built from `analyze`'s own preview. The output is pixel-identical
  and text-identical to the clean fixture. The remove preview has the
  selection's frame and size.
- **Area edge cases.**
  - Partial overlap: only the fully contained image goes. The rotated text and
    all 10 chart paths are kept.
  - `first_page` versus `all_pages` behave as expected.
  - Areas with nothing fully inside return `no_removable_objects_in_selection`
    and produce no output.
  - `/Watermark` and `/Stamp` annotations inside the selection are removed.
  - An invalid mode, scope or selection fails.
  - Signed documents return `unsupported`, encrypted ones `password_required`.
- **Forced validation failures** run through an in-process worker so the
  internals can be patched:
  - A tampered splice that also changes body text outside the selection gives
    `processing_failed`/`content_outside_selection_changed`. No PDF or preview
    is published.
  - Text that moves outside the selection while the render stays equal gives
    `text_outside_selection_changed`.
- **Preview frame.** A black marker at a known PDF point is found in the
  `analyze` PNG within 2 px of `pdf_to_normalized(...)`. This holds for
  rotations 0/90/180/270 × {full crop, offset crop} and for two crop boxes that
  extend beyond the media box. A `ManualSelection` built from that preview
  removes exactly the marker. Existing or non-`.png` preview paths are refused
  and left untouched.
- **Robustness.**
  - Junk after `%%EOF` is accepted, and `source_sha256` is the hash of the
    original bytes. A file with no `%%EOF` in its last 4 KiB is still invalid.
  - A crop box beyond the media box is intersected. A disjoint crop box is
    still invalid.
  - An inherited `/MediaBox` and `/Rotate`, together with high-precision reals,
    now work.
  - A relative `temporary_root` works.
  - Public exports, the `EngineResult` round-trip and the 300 s timeout cap
    are checked.
- **Units.** Tokenizer offsets, strings, hex strings and inline images. Replay
  versus PDFium objects on content with shading, `'`/`"`, empty shows, one-point
  paths, missing XObjects and unmatched marked content. Splice semantics for
  `'`, `"` and paths. Text line-advance dependency blocking. Effective crop and
  unit-rectangle mapping.

### Real documents (not part of the unit suite)

The PDFs bundled with the locally installed Adobe Acrobat DC (under
`C:\Program Files`) were used read-only, through copies in a scratch directory.
Only statistics and file names were recorded.

- The replay/PDFium/pypdf mapping check was run on the first 25 pages of 73
  files, 637 pages in total. **637/637 pages mapped exactly.**
- `analyze` was run on 67 files, followed by `remove(mode="area")` with a
  central selection `(0.3, 0.3, 0.7, 0.7)`. The first run found three false
  failures, which were fixed:
  - `independent_page_box_mismatch` for an inherited `/MediaBox`;
  - `structural_preservation_check_failed` caused by pypdf's 8-digit real
    serialization, on 2 Acrobat demo reports;
  - `object_graph_limit` caused by a depth of 64 on a tagged sample.

  A rerun after the fixes gave the results below:

  | File | `analyze` | Area mode, validated |
  | --- | --- | --- |
  | The 24-page "Demo Quarterly Earnings Report" | Readable | Removed 757 objects on 17 pages (2 kept as not separable) in 7.5 s |
  | "Demo Shareholder Report" | Readable | Removed 21 objects in 4.9 s |
  | The inherited-media-box icon | Readable | Nothing inside |
  | "Bus Schedule" | Readable | Removed 405 objects |

  Before the fixes, the full 67-file run gave `analyze` on 65
  `no_supported_watermark_detected`, 1 `supported_watermark_detected` and 1
  invalid file. Area mode gave 55 validated removals, 7
  `no_removable_objects_in_selection`, 2 false `processing_failed` results and
  2 refusals of signed documents.

  After the fixes, only the four affected files were rerun. The full 67-file
  rerun was started but stopped unfinished at the coordinator's request to wrap
  up. No result is claimed for it.
- "Bus Schedule.pdf" contains real Acrobat watermark artifacts (vector paths,
  6 per page on pages 2 to 4). `detect` reports `artifact_count` 18. Automatic
  `remove` removed all 18 (`watermark_artifact`), with every check passing, in
  4.3 s. A visual before, after and difference comparison of page 2 shows only
  the gray diagonal watermark removed. The text, the photo and the table of
  contents are unchanged.

### Not done or not claimed

- POSIX resource limits and Python 3.11 were not executed.
- The engine does not descend into Form XObjects that are only partly inside
  the selection. `FPDFFormObj_RemoveObject` was tried, and the removal is not
  persisted on save in this PDFium build.
- `FPDFPage_GenerateContent` was evaluated and rejected. Regenerating a stream
  with shading, inline image, `Tc`/`Tw` and `Tr` content changed the rendering:
  the shading and inline image vanished, the spacing was lost and the render
  mode leaked into the next text.
- The Flutter app and the Android packaging are outside this module; the root
  README lists their checks. The PC server that once wrapped this engine was
  removed on 2026-11-18.
- Validation runs at the configured resolution (1024 px long edge). It does not
  prove identical rendering in every viewer.

## In-process mode and Android adapter (2026-11-18)

Run on Windows 11 with Python 3.13.2, pypdf 7.1.0, pypdfium2 5.15.2 and Pillow
12.3.0, from a throwaway virtual environment:

| Command | Result |
| --- | --- |
| `python -m unittest discover -s processing_engine/tests` (whole suite) | **109 tests OK**, 272 s. |
| of which `tests/test_inprocess.py` | 8 tests: no worker process is started, the working directory is unchanged, results equal worker-mode results, failures are results, the source is never modified, and the rename fallback of `publish_exclusive` publishes without overwriting. |
| of which `tests/test_mobile_adapter.py` | 7 tests: the JSON contract of `analyze`, `remove`, `self_test` and `purge` in `android/app/src/main/python/pdfwm_mobile.py`, including area removal on a 3-page PDF and errors returned as JSON. |

These tests run the Android code **on the PC**. They do not prove that the
packaged Python, PDFium and Pillow start on a phone. The APK was inspected (it
contains `libpython3.13.so`, the engine `.pyc` files, pypdf, pypdfium2 with
`libpdfium.so`, and Pillow 11.0.0 with its native libraries), but it has not been
run on a device or emulator. The app's **Check PDF engine** action is the on-phone
check. Pillow 11.0.0 is what the APK ships (PyPI has no Android Pillow 12); the
PC tests above use 12.3.0.

## Stage 6A verification (historical, 2026-11-14)

Verified on 2026-11-14 on Windows 11 with Python 3.14.5. This is a separate
local engine; Flutter integration is not included.

| Check | Actual result |
| --- | --- |
| `processing_engine/.venv/Scripts/python.exe -m unittest discover -s processing_engine/tests -v` | **66 tests passed**, 81.999 seconds; no failures or skips. |
| Geometry unit tests | 19 passed: rotations, crop/media frames, negative origins, UserUnit, bounds, raster aspect, stale geometry and invalid coordinates. |
| Engine integration tests | 36 passed: actual native rendering/removal, ordinary content preservation, all outcomes, manual scope, multipage/nested page trees, malformed/encrypted/signed inputs and limits. |
| Storage/protocol/independent-oracle tests | 11 passed: publication safety, cleanup, unreadable input, hard-link aliases, source mutation, zero-removal rejection, CLI JSON and native PDFium coordinate mapping. |
| `processing_engine/.venv/Scripts/python.exe processing_engine/tools/generate_demo.py` | Four real watermark annotations removed; all four pages independently verified. |

The four-page Stage 6A before/after demonstration files (`output/pdf/stage6a-*`
and `tmp/pdfs/stage6a*`) were deleted from the repository on 2026-11-18 during a
cleanup, along with `processing_engine/CHANGED_FILES.txt`. They had been produced
by the annotation pipeline, which 0.2.0 keeps unchanged for annotation-only
removal. `tools/generate_demo.py` can recreate a demonstration; its default
folders `output/pdf` and `tmp/pdfs` are git-ignored and created on demand. It was
not rerun for 0.2.0.

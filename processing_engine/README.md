# PDF watermark engine (0.2.0)

This module removes watermarks from PDFs conservatively. It writes a separate,
validated PDF and never opens the source for writing. It is independent of
Flutter and has no HTTP server. It does not do OCR, redaction, inpainting or
rasterization, and it does not report fake progress.

Version 0.2.0 handles three kinds of watermark:

| Mode | What it removes | How it is identified |
| --- | --- | --- |
| `auto` | Indirect `/Subtype /Watermark` annotations (Stage 6A rules) | Explicit annotation subtype |
| `auto` | **Acrobat-style watermark artifacts**: page content inside `/Artifact <</Subtype /Watermark ...>> BDC ... EMC` | Explicit marked-content properties (how Acrobat's *Add Watermark* writes them) |
| `area` | Every top-level page object, and every `/Watermark` or `/Stamp` annotation, lying **fully inside** a user-selected rectangle, on page 1 or on all pages | Geometry only: the user's attested selection |

## Run locally

From the repository root in PowerShell, with Python 3.11 or newer:

```powershell
python -m venv processing_engine/.venv
.\processing_engine\.venv\Scripts\python.exe -m pip install -e './processing_engine[verify]'
.\processing_engine\.venv\Scripts\python.exe -m unittest discover -s processing_engine/tests -v
.\processing_engine\.venv\Scripts\python.exe -m pdf_watermark_engine detect input.pdf
.\processing_engine\.venv\Scripts\python.exe -m pdf_watermark_engine analyze input.pdf page1-preview.png
.\processing_engine\.venv\Scripts\python.exe -m pdf_watermark_engine remove input.pdf separate-output.pdf
.\processing_engine\.venv\Scripts\python.exe -m pdf_watermark_engine --timeout 180 remove input.pdf out.pdf --mode area --selection selection.json --apply-to all_pages --preview out-page1.png
```

Runtime dependencies are pinned **pypdf 7.1.0**, **pypdfium2 5.15.2** and
**Pillow 12.3.0** (Pillow became a runtime dependency in 0.2.0, for preview PNGs
and pixel-difference validation). The `[verify]` extra is kept, empty, so older
install commands still work. PyMuPDF is not used. See
[library evaluation and licenses](DEPENDENCIES.md).

## Running inside an Android app (in-process mode)

`PdfWatermarkEngine(isolation="inprocess")` runs each job in the calling process
instead of a worker process, because an app embedding Python (Chaquopy) cannot
start a second interpreter. The Android entry point is
`android/app/src/main/python/pdfwm_mobile.py`, which the app calls through
`MainActivity.kt`.

What differs from the default `isolation="process"`:

- **No memory limit and no hard timeout.** A native PDFium call cannot be
  interrupted, and `setrlimit`/Job Objects would apply to the whole app. The
  adapter instead uses phone-sized limits (40 MiB input, 100 pages, 48 MiB of
  decoded streams) and the app shows them before accepting a file.
- **No working-directory change.** `run_job(..., in_process=True)` only checks
  the job folder's name, not that it is the current directory.
- **Publication falls back to a rename.** If the file system refuses the
  exclusive hard link, the fully written staging file is renamed into place after
  re-checking that nothing exists at the destination (`rename_fallback=True`).
  Hard links stay mandatory in the default mode.
- **Parser logging is disabled** for the duration of a job, as in the worker.
- Everything else is shared: the same validation, the same result types (results
  go through the same JSON round trip), the same codes.

Tests: `tests/test_inprocess.py` (mode behaviour, including that the results
match worker mode and that no process is started) and `tests/test_mobile_adapter.py`
(the adapter's JSON contract and its self test, run on the PC). They do not prove
that the Android packaging works; the app's **Check PDF engine** action does that
on a phone.

## Python API

```python
from pdf_watermark_engine.api import PdfWatermarkEngine
from pdf_watermark_engine.models import EngineResult, EngineFailure, Limits, ManualSelection, Outcome

engine = PdfWatermarkEngine(Limits(timeout_seconds=180), temporary_root=None)
engine.detect(source, *, expected_sha256=None) -> EngineResult
engine.analyze(source, preview_png, *, long_edge=1024, expected_sha256=None) -> EngineResult
engine.remove(source, output, *, mode="auto", selection=None, apply_to="all_pages",
              expected_sha256=None, preview_png=None) -> EngineResult
```

`PdfWatermarkEngine` and `EngineFailure` are also exported from the package root.
The public methods never raise `EngineFailure`. They return an `EngineResult`.
`temporary_root` is resolved to an absolute path when the engine is
constructed. On Python 3.11 a relative root otherwise produced a relative job
directory, and the worker failed with `invalid_job_directory`. Existing output
or preview paths are never overwritten. The output must end in `.pdf` and the
preview in `.png`, and neither may be the source.

`EngineResult` fields (all JSON-serializable; `to_dict`/`from_dict` round-trip):

| Field | Meaning |
| --- | --- |
| `outcome`, `code`, `message` | One of the seven outcomes below, plus a machine-readable reason. |
| `source_sha256`, `source_size`, `document_id` | Identity of the exact source bytes (`document_id` is `sha256:<hex>`). |
| `page_count`, `pages` | Per page: `media_box`, `crop_box` (the effective one, intersected with the media box), `rotation`, `user_unit`, `geometry_sha256`. After a watermark scan each page also has `watermark_artifact_count`. |
| `supported_count`, `unsupported_count`, `candidates` | `/Watermark` annotation candidates, as in Stage 6A. |
| `artifact_count` | Removable Acrobat-style watermark artifact page objects. |
| `removed_count`, `removed_by_kind`, `pages_changed` | After a removal: `removed_count == sum(removed_by_kind.values()) > 0`. The kinds are `watermark_annotation`, `watermark_artifact`, `area_object` and `area_annotation`. `pages_changed` is 1-based. |
| `output_path`, `output_sha256` | Set only after the validated output has been published. |
| `preview` | Set by `analyze`, and by `remove(..., preview_png=...)` when it succeeds: `{"page_number": 1, "width", "height", "render_box": "cropBox", "geometry_sha256", "path"}`. |
| `checks` | Validation facts, for example `unsupported_artifact_pages`, `trailing_bytes_after_eof_ignored`, `area_pages_not_editable`, `area_objects_kept_not_separable`. |

### `detect` and `analyze`

`detect` returns `supported_watermark_detected` when supported `/Watermark`
annotations **or** removable watermark artifacts exist. Otherwise it returns
`unsupported_watermark_structure` when only unsupported candidates exist
(annotations or artifact pages), and `no_supported_watermark_detected` when
there are none.

`analyze` does everything `detect` does in the same worker run. It also renders
page 1 with PDFium, using the effective crop box as the frame. The page
`/Rotate` is applied and annotation appearances are drawn. No forms environment
or JavaScript is initialized. The background is white and the long edge is
exactly `long_edge` pixels (16 to 4096). The PNG is then published to
`preview_png` exclusively. The preview is the trusted frame for a manual
selection. Build the selection as follows:

```python
p = result.preview
selection = ManualSelection(result.document_id, result.source_sha256, result.source_size, 1,
                            p["geometry_sha256"], "cropBox", p["width"], p["height"],
                            (left, top, right, bottom))  # normalized to the PNG, top-left origin
```

Tests place a marker at a known PDF point and find it in the PNG. The marker
lands at `geometry.pdf_to_normalized(...)` within two pixels, for rotations
0/90/180/270, offset crop boxes and crop boxes larger than the media box.

`ManualSelection` requires every field below. The engine recomputes the
document and geometry identities from its own snapshot.

| Field | Required binding |
| --- | --- |
| `document_id` | `sha256:` followed by the full source SHA-256. |
| `source_sha256`, `source_size` | The exact source revision and its byte count. |
| `page_number` | The integer `1`. |
| `geometry_sha256` | The page-1 digest from `pages[0]` or `preview`. |
| `render_box` | `cropBox` for the engine preview (`mediaBox` is accepted only with a renderer that is known to show the media box). |
| `raster_width`, `raster_height` | The preview size. It must match the rotated box aspect within 2 px. |
| `rect` | `[left, top, right, bottom]`, normalized to the raster, each value in `[0, 1]` and each extent at least `0.02`. |
| `coordinate_space` | Exactly `renderedPageTopLeft`. |

For displayed unit coordinates `(s,t)`, rotations 0/90/180/270 map back to
`(u,v) = (s,t), (t,1-s), (1-s,1-t), (1-t,s)`. For a box `(x0,y0,x1,y1)`, the PDF
point is then `x = x0 + u*(x1-x0)` and `y = y1 - v*(y1-y0)`. All four corners
are transformed and their bounds taken. `/UserUnit` changes the physical size
but not these raw coordinates.

### `remove(mode="auto")`

- Supported `/Watermark` annotations are removed, using the Stage 6A rules
  described below.
- Acrobat-style watermark artifacts are removed. These are page-level marked
  content `/Artifact` whose properties have `/Subtype /Watermark`. The
  properties may be given inline or as a `/Properties` resource name. The
  watermark can be a Form XObject (`/FmN Do`, as Acrobat writes it), text,
  paths or images inside the section.
- `apply_to="first_page"` limits the removal to page 1. A `selection` limits
  it to page-1 objects fully inside the attested rectangle, which was the
  Stage 6A manual behavior.
- If neither kind exists in scope, the result is `no_supported_watermark_detected`
  (or `unsupported_watermark_structure`) and no output is written.
- When only annotations are removed, the strict Stage 6A pypdf pipeline still
  runs unchanged. When artifacts are involved, the content pipeline described
  below runs, and it removes both kinds in one validated output.

### `remove(mode="area")`

`selection` is required. It is validated exactly as in Stage 6A against page 1:
document identity, size, geometry digest, explicit render box, raster aspect
and the 2% minimum extent. The same normalized rectangle is then mapped onto
every page in scope (`apply_to="all_pages"` or `"first_page"`). Each page uses
**its own** effective crop box (or media box, if the selection says so) and its
own rotation. A watermark therefore has to sit at the same displayed relative
position on each page. On each page the engine removes:

- every top-level page object whose PDFium bounds (`FPDFPageObj_GetBounds`, PDF
  user space) lie fully inside the mapped rectangle, within 0.5 pt. This covers
  text, paths, images, inline images, shadings and Form XObjects. Invisible text
  (render modes 3 and 7) is not counted, so OCR layers are not stripped by
  accident.
- every `/Watermark` or `/Stamp` annotation whose `/Rect` is fully inside, unless
  it is Hidden/NoView. The annotation's `/Popup` is removed with it.

Objects that are only partly inside are kept, and so is everything outside the
rectangle. If nothing is removed anywhere, the outcome is
`no_supported_watermark_detected` with code `no_removable_objects_in_selection`,
and no output is written. If objects were inside but no page's content could be
mapped safely, the outcome is `unsupported_watermark_structure` with code
`area_content_structure_unsupported`. Signed or certified documents are refused
(`signed_or_certified_document_not_modified`). Encrypted documents return
`password_required`.

The engine **does not descend into Form XObjects** that are only partly inside
the rectangle. In the pinned PDFium build, `FPDFFormObj_RemoveObject` returns
success, but the change is lost on save (verified). Editing the form stream
ourselves would need page-private copies of shared XObjects and resources, and
that is not implemented. Such forms are kept unchanged and nothing is recorded
for them.

## How content is edited (artifacts and area)

PDFium's `FPDFPage_GenerateContent` was evaluated and **rejected**. When it
regenerates a stream, the pinned build drops shading (`sh`) objects, inline
images, character and word spacing, and it leaks text render modes into later
text. Instead, the engine works in four steps:

1. Tokenizes each content stream with its own byte-offset lexer
   (`content.py`). The lexer covers strings, hex strings, names with `#xx`,
   arrays, dictionaries, comments and inline images.
2. Replays the operators with PDFium's object-creation rules, to predict
   exactly which page objects PDFium creates and in which order. The rules
   cover path points and painting, text shows, `Do`, inline images, `sh`, the
   marked-content stack, `q`/`Q`, the font and the text render mode.
3. Edits a page only if three independent views agree. The predicted objects
   must match PDFium's actual page objects in type and mark depth, every
   watermark object must carry an `Artifact` mark with a `/Subtype` name, and
   pypdf's own operator parse must give the same operator sequence. Otherwise
   the page is reported as not editable.
4. Removes each object by splicing only its painting operator out of the
   original bytes:
   - path painting becomes `n`, so clipping is kept;
   - `Do`, `sh`, inline images and `Tj`/`TJ` are deleted;
   - `'` becomes `T*`, and `"` becomes `aw Tw ac Tc T*`.

   All other bytes stay identical, including graphics-state and marked-content
   operators. Only edited streams are replaced. A `Tj`/`TJ` is not removed when
   later text on the same line would move because of it, and clipping text
   (render modes 4 to 7) is never removed. Artifact removal is all-or-nothing
   per page. XObjects whose only uses were removed are detached through a
   page-private `/Resources`, and the second whole-document clone drops them
   and any other now-unreachable objects.

Validation runs before anything is published. If any check fails, the result
is `processing_failed` with the code shown, and nothing is published:

1. The output reopens with pypdf `strict=True` and with PDFium. It has the same
   page count, the same media and effective crop boxes and the same rotations
   (`output_page_geometry_changed`, `output_page_count_changed`).
2. A pypdf logical-graph digest of the whole document matches the source. Only
   the removed annotations, and the `/Contents` and `/Resources` of edited
   pages, may differ (`structural_preservation_check_failed`).
3. Every page is rendered before and after at the same size, with annotations
   drawn and a long edge of `render_long_edge`. Pillow then compares the pixels.
   No pixel may differ by more than 16/255 in any channel outside the allowed
   region (`content_outside_selection_changed`). The allowed region is the
   mapped rectangle in area mode. In automatic mode it is the union of the
   removed objects' bounds and annotation rectangles. Either region is dilated
   by 2 px. A page without removals must not change at all
   (`unexpected_page_change`).
4. PDFium text-page characters outside the allowed region must be unchanged, in
   order, in Unicode value and in box position within 0.5 pt
   (`text_outside_selection_changed`).
5. The edited pages are analyzed again. No watermark artifact may remain
   (`watermark_artifact_absence_check_failed`). Exactly the non-separable objects
   may remain inside the area (`area_object_absence_check_failed` and
   `area_annotation_absence_check_failed`). Supported annotations may not
   remain, and no orphan annotation objects may be left behind.
6. The result must satisfy `removed_count == sum(removed_by_kind.values()) > 0`,
   and `pages_changed` must be exactly the pages with removals
   (`inconsistent_removal_report`, `invalid_success_result`).
7. The Stage 6A guarantees still apply. The source is opened read-only and
   re-hashed after processing (`source_changed_during_processing`). The output
   and preview are published exclusively, through a hard link that never
   overwrites. If the PDF cannot be published, the preview is withdrawn. Job
   and staging files are always cleaned up.

## Stage 6A annotation rules (unchanged)

The supported annotation is an indirect `/Annots` entry with `/Subtype /Watermark`
(PDF 1.7, 12.5.6.22). It must also have all of the following:

- an ordered `/Rect` inside the crop box;
- a normal `/AP /N` that is an indirect, non-empty Form XObject with a finite
  `/BBox` and an invertible `/Matrix`;
- flags absent, 0 or Print;
- a correct `/P`, and exactly one incoming reference;
- none of `/A`, `/AA`, `/Popup`, `/IRT`, `/Parent`, `/Kids`, `/StructParent`,
  `/OC` or `/FixedPrint`.

`/Stamp` annotations (including `/Name /Watermark`) are never removed in auto
mode. A stamp named `/Name /Watermark` is reported as an ambiguous candidate.

## Exact unsupported scope

- Watermarks that are not marked as watermark artifacts. These include plain
  page text, images, vector art, scanned pixels, OCG layers and repeated
  headers. Automatic mode never guesses at them. Use `area` mode.
- Watermark artifacts that are inside Form XObjects rather than at page level.
  They are not detected. The page-level form that contains them can be removed
  only through `area` mode, and only when it lies fully inside the selection.
- Pages where the tokenizer, PDFium and pypdf disagree. Examples are operators
  split across content streams, inline images whose length cannot be
  determined, and invalid fonts or shadings that PDFium drops. Such pages are
  not edited (`unsupported_artifact_pages` or `area_pages_not_editable`).
- Partial removal of a watermark object: pixels inside an object are never erased.
- Encrypted PDFs (`password_required`), and signed or certified documents
  (refused, with no re-signing).
- Leading junk before `%PDF`, files without `%%EOF` in their last 4 KiB,
  malformed PDFs, crop boxes that do not intersect the media box, and documents
  for which preservation cannot be shown.

Accepted since 0.2.0 are bytes after the last `%%EOF` (common in scanner and
printer output) and crop boxes extending beyond the media box. For trailing
bytes, the last `%%EOF` within the final 4 KiB is used. Only the job's private
snapshot is truncated, so `source_sha256` still describes the original bytes and
`checks.trailing_bytes_after_eof_ignored` is set. An oversized crop box is
intersected with the media box, as the PDF specification and PDFium do,
everywhere geometry is used: reports, digests, mapping and render checks.

Three more Stage 6A false failures were found by running the engine on PDFs
bundled with Adobe Acrobat, and are fixed in 0.2.0:

- **Inherited `/MediaBox`.** `FPDFPage_GetMediaBox` ignores page-tree
  inheritance, and pypdfium2 then reports US Letter, so the independent check
  rejected valid files (`independent_page_box_mismatch`). The PDFium side now
  compares `FPDF_GetPageBoundingBox`, the displayed box with inheritance
  applied, and compares the media box only when the page states it explicitly.
- **Clone side effects.** pypdf's clone writes inherited `/Resources`,
  `/MediaBox`, `/CropBox` and `/Rotate` explicitly on each page, and it writes
  reals with 8 significant digits (`1008.789063` becomes `1008.78906`). The graph
  digest now resolves inherited page attributes on both sides and compares reals
  at that write precision. Before, both effects caused
  `structural_preservation_check_failed`.
- **Graph depth.** Tagged documents exceeded the old depth limit of 64.

## Outcomes

| `outcome` | Meaning |
| --- | --- |
| `supported_watermark_detected` | Supported annotations or removable watermark artifacts exist. |
| `watermark_removed_successfully` | At least one object was removed and the separate output passed every check. |
| `no_supported_watermark_detected` | Nothing supported is in scope (or nothing lies fully inside the selection). No output is written. This does not prove the PDF has no watermark. |
| `unsupported_watermark_structure` | A candidate exists but cannot be modified safely, or the document is signed or certified. |
| `invalid_or_unreadable_pdf` | The input cannot be opened or fails structural or readability checks. |
| `password_required` | The document is encrypted. |
| `processing_failed` | A resource limit, a stale selection or revision, an unsafe output path, a worker failure or a validation failure. |

Codes added in 0.2.0:

- **Success:** `supported_watermarks_removed` (content pipeline) and
  `selected_area_objects_removed`.
- **Nothing removed:** `no_removable_objects_in_selection` and
  `area_content_structure_unsupported`.
- **Request errors:** `area_selection_required`, `invalid_mode_or_scope`,
  `unsafe_or_existing_preview`, `invalid_preview_size`, `preview_not_rendered`
  and `preview_size_limit`.
- **Validation failures:** `content_outside_selection_changed`,
  `text_outside_selection_changed`, `unexpected_page_change`,
  `output_page_count_changed`, `output_page_geometry_changed`,
  `watermark_artifact_absence_check_failed`, `area_object_absence_check_failed`,
  `area_annotation_absence_check_failed`, `output_content_unverifiable`,
  `content_stream_layout_changed` and `inconsistent_removal_report`.

The Stage 6A codes are unchanged.

Do not decide success from the CLI exit code alone. Exit 0 also covers a
completed scan that found nothing supported. Read `outcome` and `removed_count`.
Parser exception strings, document text and annotation contents are never
returned.

## Limits

These are the defaults:

| Limit | Default |
| --- | --- |
| Input size | 64 MiB |
| Each output or intermediate PDF, and the preview | 128 MiB |
| Pages | 100 |
| Objects | 50,000 |
| Annotations | 2,000 |
| Graph depth | **256** (was 64) |
| Total decoded streams | 64 MiB |
| One appearance | 2 MiB |
| Render long edge | 1024 px |
| Worker memory | 768 MiB |
| Worker timeout | 30 s |

The graph depth went up from 64 because real tagged PDFs, such as an Adobe
sample with a structure tree, need between 64 and 128. `timeout_seconds` can be
set from just above 0 up to **300**. Larger values raise `ValueError`. The
app or a server wrapper would pass e.g. `Limits(timeout_seconds=180)`. A 50-page area removal took
4 to 7 s here, also with the default 30 s limit (see [VERIFICATION.md](VERIFICATION.md)). Snapshot and publication I/O
fall outside the worker timeout.

Windows uses a memory-limited, kill-on-close Job Object. POSIX uses address
space and CPU rlimits, but that branch has not been run on this Windows host.
These controls are not a security sandbox. Before accepting public uploads, run
the native renderer in a restricted worker with no network, narrow filesystem
access, bounded concurrency and disk quotas.

Remaining risks:

- The artifact classifier trusts explicit marked-content semantics. Content
  that the author mislabeled as a watermark artifact would be removed.
- Area mode removes whatever lies fully inside the user's rectangle, which can
  include ordinary text the user selected.
- Validation runs at a bounded resolution, so it does not prove identical
  behavior in every viewer.
- Synthetic fixtures and the bundled Adobe samples do not cover every producer.

## Files

| File | Role |
| --- | --- |
| `api.py` | Jobs and exclusive publication of the PDF and PNG. |
| `worker.py`, `isolation.py` | Resource boundaries. |
| `document.py` | Strict parsing, effective crop box, EOF trimming, graph digest and cloning. |
| `annotations.py` | Classifies `/Watermark` annotations. |
| `content.py` | Tokenizer, PDFium-compatible replay and byte splicing. |
| `editing.py` | Artifact and area planning, edits and validation. |
| `rendering.py` | PDFium geometry checks, exact-size rendering, page objects and text. |
| `geometry.py` | Coordinate mapping. |
| `core.py` | The worker's job logic. |
| `models.py` | The contract. |
| `cli.py`, `__main__.py` | Local JSON commands. |

See [VERIFICATION.md](VERIFICATION.md) for the commands that were run and their
results.

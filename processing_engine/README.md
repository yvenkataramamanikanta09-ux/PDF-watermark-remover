# Stage 6A: local PDF watermark annotation engine

This module performs real, conservative removal of explicitly typed PDF
watermark annotations. It creates a separate, validated PDF and never opens
the source for writing. It is independent of Flutter. No HTTP server, FastAPI,
UI integration, OCR, redaction, artificial progress or completion screen is added.

## Run locally

From the repository root in PowerShell, with Python 3.11 or newer:

```powershell
python -m venv processing_engine/.venv
.\processing_engine\.venv\Scripts\python.exe -m pip install -e './processing_engine[verify]'
.\processing_engine\.venv\Scripts\python.exe -m unittest discover -s processing_engine/tests -v
.\processing_engine\.venv\Scripts\python.exe -m pdf_watermark_engine detect input.pdf
.\processing_engine\.venv\Scripts\python.exe -m pdf_watermark_engine remove input.pdf separate-output.pdf
```

For runtime only, install `./processing_engine` without `[verify]`. Pillow is
only used to make the demonstration comparison image. The engine uses the
installed APIs of pinned **pypdf 7.1.0** and **pypdfium2 5.15.2**. See
[library evaluation and licenses](DEPENDENCIES.md) before distribution.

Python API:

```python
from pdf_watermark_engine.api import PdfWatermarkEngine
from pdf_watermark_engine.models import Outcome

engine = PdfWatermarkEngine()
detection = engine.detect("input.pdf")
result = engine.remove("input.pdf", "separate-output.pdf",
                       expected_sha256=detection.source_sha256)
if result.outcome == Outcome.REMOVED:
    assert result.removed_count > 0
    print(result.output_path)
```

Do not decide success from the CLI exit code alone. Exit 0 also means a completed
scan with nothing supported or an unsupported structure. Read `outcome` and
`removed_count`. Invalid input, password requirements and processing failures
return exit 2. Existing output paths are never overwritten.

## Exact supported scope

The initial supported type is an indirect annotation in a page's `/Annots`
array with **`/Subtype /Watermark`**, as defined in PDF 1.7 section 12.5.6.22.
This is an explicit structural identifier, not an inference from text, opacity,
position, filenames, repeated page content or a stamp icon name.

The supported subset has:

- An ordered, nonzero `/Rect` entirely within the crop box.
- A normal `/AP /N` that is an indirect, nonempty Form XObject stream, with
  a finite positive `/BBox` and, if present, a finite nonsingular `/Matrix`.
- Flags absent, zero, or Print (`4`), with no hidden, locked, read-only,
  NoZoom or NoRotate behavior.
- A correct `/P` if present, and exactly one incoming reference, from its
  page's annotation array. Shared appearance resources are allowed and retained
  if another object still uses them.
- No `/A`, `/AA`, `/Popup`, `/IRT`, `/Parent`, `/Kids`, `/StructParent`, `/OC`
  or `/FixedPrint` relationships.

Automatic mode removes every supported annotation across all pages, within
configured limits. Manual mode only removes supported annotations fully
contained by the attested selection on page one. Partial intersections and
ordinary content are never erased. `/NM` and `/Contents` are not classifiers.

See the [Adobe-hosted PDF specification](https://opensource.adobe.com/dc-acrobat-sdk-docs/standards/pdfstandards/pdf/PDF32000_2008.pdf)
for the distinction between stamp annotations and watermark annotations.

## Exact unsupported scope

- **All `/Stamp` annotations**, including `/Name /Watermark`, `/Draft`,
  `/Confidential` and `/Approved`. A custom `/Name /Watermark` is reported as
  an ambiguous candidate. Other stamp names remain ordinary annotations.
- Watermark appearances stored in named appearance-state dictionaries, missing
  or unsupported appearance streams, fixed-print transformations, optional
  content, dependent/shared annotation objects, interactive/tagged annotations,
  hidden/locked annotations, and rectangles outside the crop box.
- Watermarks flattened into page content, text operators, vector artwork,
  images, scanned pages, Form XObjects used as page artwork, repeated headers,
  and OCG/layer watermarks. These are not heuristically classified. The result
  may be **No supported watermark detected**, even when a watermark is visible.
- Encrypted PDFs, even those with an empty user password: **Password required**.
  No password input or decryption is implemented.
- Signed/certified documents: detection may describe annotation candidates,
  but removal is refused. No signature validation or re-signing is implemented.
- Invalid/ambiguous geometry, malformed PDFs, exceeded limits, and documents
  for which preservation or independent rendering cannot be established.

## Outcomes

| `outcome` | Meaning |
| --- | --- |
| `supported_watermark_detected` | A scan identified at least one structurally supported annotation. |
| `watermark_removed_successfully` | At least one supported object was removed and the separate output passed all checks. |
| `no_supported_watermark_detected` | No supported object exists in scope; no output is published. This does not prove the PDF has no watermark. |
| `unsupported_watermark_structure` | A recognizable candidate or protected document cannot be safely modified. |
| `invalid_or_unreadable_pdf` | Input cannot be opened or fails structural/readability checks. |
| `password_required` | Encrypted document; password handling is not implemented. |
| `processing_failed` | Resource limit, stale selection/revision, unsafe output, worker failure or preservation check failure. |

Machine-readable `code` gives the specific reason. Mixed supported and
unsupported candidates are counted separately; a successful result means only
`removed_count` objects were removed, not that every visible watermark is gone.
Parser exception strings, document text and annotation contents are not logged
or returned. The result contains geometry, hashes, counts and the requested
output path; future transport logs should also avoid identifying user paths.

## Processing and preservation

1. Stream the input into an owned temporary snapshot while hashing it; check
   for source changes and optional expected revision. No file content enters
   Flutter/Dart and no source write handle is opened.
2. Parse strictly in a constrained subprocess; validate header/EOF, active page
   content syntax, object graph, page count, boxes, rotations and stream limits.
3. Open/render every page independently using native PDFium. Check geometry
   against pypdf; do not initialize forms or execute document actions.
4. Remove only eligible annotation references. Clone the reachable document a
   second time to discard detached annotation dictionaries and exclusive
   appearance resources. Preserve nested page-tree links.
5. Reopen the output strictly. Compare its parsed logical root/metadata graph
   against the source graph with only authorized annotation references omitted.
   Check page geometry and remaining supported objects, including raw xrefs for
   orphan watermark annotation dictionaries. Compare all base-content renders.
6. Rehash the original. Publish only the fully validated result using an
   exclusive same-filesystem hard link to a flushed temporary output. A
   filesystem without this capability fails safely. Clean up job/staging files.

This preserves parsed ordinary text, image bytes, content streams, resources,
links, non-watermark annotations, metadata and page structure, or refuses the
output. Object numbers, serialization, xrefs, file size and obsolete/unreachable
objects may change. The original is retained for recovery. It is not a PDF/A,
PDF/UA, cryptographic signature, malware or universal PDF-conformance validator.

## Flutter manual-selection contract

Stage 5's `PdfAreaSelection` stores a session document ID, `SelectedPdf`, page
one, normalized bounds, raster dimensions and `renderedPageTopLeft`. Android
`pdfx` already applies native page orientation, but the model does **not** attest
the source SHA-256, rotation, crop box or whether the rendered frame is the
media or crop box. Its original payload is deliberately not accepted directly.

The engine's `ManualSelection` requires all these fields:

| Field | Required binding |
| --- | --- |
| `document_id` | `sha256:` followed by the full source SHA-256. |
| `source_sha256`, `source_size` | Exact immutable source revision and byte count. |
| `page_number` | Integer `1` for this stage. |
| `geometry_sha256` | Canonical digest from the engine's page report. |
| `render_box` | Explicit `cropBox` or `mediaBox`, established by a trusted renderer contract. |
| `raster_width`, `raster_height` | Positive integer actual page-raster dimensions, matching the rotated box aspect within two pixels. |
| `rect` | `[left, top, right, bottom]`, each in `[0,1]`, each extent at least `0.02`. |
| `coordinate_space` | Exactly `renderedPageTopLeft`. |

Pass this model to `remove(..., selection=model)` or use `--selection file.json`.
The engine recomputes document and geometry identities from the snapshot. A
caller-supplied box name is an assertion, not proof of a trusted preview; Stage
6B must bind it to the actual preview, not infer it from aspect ratio alone.

For normalized visible coordinates `(s,t)`, the inverse clockwise display
rotation is `(u,v) = (s,t), (t,1-s), (1-s,1-t), (1-t,s)` for rotations
0/90/180/270 respectively. For raw box `(x0,y0,x1,y1)`, PDF user-space coordinates
are `x = x0 + u*(x1-x0)`, `y = y1 - v*(y1-y0)`. Transform all four corners and
take bounds. Crop offsets and negative origins are retained. `/UserUnit` affects
physical size, not these raw coordinates. The model rejects other rotations,
out-of-media crop boxes, nonfinite values, missing frames and stale bindings.

Flutter already excludes preview-card letterboxing when normalizing the page
rectangle. Screen pixels, Figma coordinates, card bounds and transforms must
never be substituted for this normalized page frame. Independent PDFium
`FPDF_PageToDevice` tests check the formulas for all four rotations and cropping.

## Limits and remaining risks

Defaults: 64 MiB input, 128 MiB per output/intermediate PDF, 100 pages, 50,000
objects, 2,000 annotations, 64 graph levels, 64 MiB total decoded reachable
streams, 2 MiB per appearance, 1024-pixel render long edge, 768 MiB worker
memory and a 30-second worker timeout. Snapshot/publication filesystem I/O is
outside the worker timeout. pypdf's bounded snapshot may be held in worker
memory; no claim is made that structural parsing is constant-memory.

Windows uses a memory-limited, kill-on-close Job Object before sending work to
the subprocess. POSIX uses address-space/CPU limits; that branch has not been
verified on this Windows host. Normal errors and timeouts clean intermediate
files. An abrupt host termination may leave private temporary files; a future
service needs a job ledger and age-based cleanup of its owned directories.

These resource controls are not a security sandbox. Before accepting public
uploads, isolate the native renderer in a restricted worker/container with no
network, narrow filesystem access, bounded concurrency and disk quotas, and
track dependency security updates. The classifier trusts explicit PDF object
semantics; mislabeled author-created annotations cannot be semantically proven
to be watermarks. Validation at bounded resolution is not proof of all possible
viewer behavior. Synthetic fixtures exercise the supported scope, not every
producer, complex font, transparency blend, embedded file or malformed PDF.

## Recommended Stage 6B architecture (not implemented)

Keep this module as the processing core. For remote Python execution, add a
small authenticated FastAPI adapter only when integration is authorized. It
should accept a bounded streamed upload, compute and retain an immutable
revision, then enqueue an isolated job. Do not send an Android content URI or
client filesystem path to Python as if it were server-readable.

Return a job/document token plus SHA-256, size and page metadata. Establish a
trusted preview frame: preferably serve a renderer-generated preview and its
box/rotation/dimensions contract, or first verify the exact Android `pdfx`
crop/media/rotation behavior on the supported devices. Bind the committed
selection to that revision and frame. Matching aspect ratios alone are
insufficient, particularly for square cropped/rotated pages.

Detection should return supported/unsupported candidate counts. An explicitly
authorized remove request should carry the expected revision and optional
attested selection. Run the existing isolated engine, preserve its seven
outcomes, expose a result only after validation and `removed_count > 0`, and
expire owned input/output artifacts with cancellation and retry handling.
Processing progress should describe real job state only. The current Flutter
Apply Selection action and **Not started** state remain unchanged in Stage 6A.

## Files and evidence

`api.py` owns jobs and publication; `worker.py`/`isolation.py` own resource
boundaries; `document.py` parses and audits graphs; `annotations.py` classifies;
`geometry.py` maps selections; `core.py` removes and validates; `rendering.py`
independently checks PDFium output; `storage.py` handles bounded I/O; `models.py`
defines the contract; `cli.py`/`__main__.py` expose local JSON commands.

See [VERIFICATION.md](VERIFICATION.md) for actual tests, complete changed-file
groups and the four-page before/after demonstration. Regenerate evidence into
a new directory with:

```powershell
.\processing_engine\.venv\Scripts\python.exe processing_engine/tools/generate_demo.py --output-dir output/pdf/new-demo
```

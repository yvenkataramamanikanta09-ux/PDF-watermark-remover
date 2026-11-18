# Home Screen visual verification

Source: [Figma Home Screen, node 221:2](https://www.figma.com/design/LBbaZL6BVE9djixis3rYnJ/PDF-Watermark-Remover---UI-UX-Design?node-id=221-2), matching the supplied screenshot.

- Source visual: `build/home-screen-qa/figma-reference.png`.
- Implementation: `build/home-screen-qa/after.png`.
- Full comparison: `build/home-screen-qa/comparison-after.png` (Figma left, Flutter right).
- Focused comparisons: `header-comparison.png`, `document-comparison.png`, and
  `copy-and-button-comparison.png` in the same directory.
- Viewport: 390 x 844 Flutter logical pixels; both images are 390 x 844 pixels.
  Flutter device pixel ratio is 1. No density normalization was needed. CSS size
  is not applicable to this native Flutter screen.
- State: initial Home Screen, bundled Inter and Material Icons loaded, images
  decoded, no menu or snackbar open. The source omits system bars, so the direct
  comparison uses zero insets. System insets are verified separately.

## Findings and fixes

The initial render had three substantive mismatches:

1. [P1, fixed] Opaque image backgrounds created a rectangular cutout around the
   teal decoration and obscured the file icon. Re-exported the exact Figma nodes
   `221:3`, `221:4`, and `223:103` as transparent PNGs at 3x resolution. Verified
   their nonempty files, alpha channels, widget callsites, and logical dimensions:
   navy 390 x 195, teal 125 x 250, and icon 20 x 20. The ellipse exports are clipped
   to the original Figma frame.
2. [P2, fixed] The preview began at y=221.25 and the button ended at y=844,
   rather than the reference positions y=195 and y=802. Replaced the sliver fill
   arrangement with a scroll view whose minimum content height accounts for both
   top and bottom padding. The current render places the preview at y=195,
   heading at y=578, description at y=650, and button at y=746, height 56.
3. [P2, fixed] The title wrapped onto two lines at the reference width. Adjusted
   its horizontal space while retaining the 16 px text and menu touch target.
   The current render and a regression test confirm a single line with Inter.

Iteration evidence: `before.png`, `before.json`, and `comparison-before.png`
record the initial state. `after.png`, `after.json`, the full comparison, and
the focused comparisons record the corrected state. Each comparison places the
source and implementation together at the same viewport.

## Required fidelity surfaces

- Typography: bundled Inter, white heading, secondary gray description, 600
  weights, source text sizes, and two-line heading/description wrapping retained.
  Minor font-renderer differences and a few pixels of header/illustration label
  alignment remain P3 polish; no text is cropped or truncated.
- Spacing: header, preview, heading, description, button, radii, and major gaps
  checked against the full and focused comparisons. Reference geometry matches.
- Colors: the specified background, navy, teal, preview, pink, white, and gray
  tokens are preserved. The exported assets have transparent backgrounds.
- Assets: original Figma decorations and file icon are rendered locally, with no
  temporary asset URLs or new runtime dependencies. The PDF illustration remains
  native Flutter widgets corresponding to the original Figma UI layers.
- Copy: all requested Home Screen text and the SAMPLE watermark match.

## Interaction and responsive checks

- `flutter analyze`: passed, no issues.
- `flutter test`: passed, 11 widget tests.
- Tests cover 320 x 568, 390 x 844, 600 x 960, and 844 x 390 layouts; portrait
  system bars; landscape side cutouts; and 2x accessibility text.
- Upload displays feedback without opening a PDF processing flow.
- The three-dot menu opens the About dialog.
- Built and installed on emulator-5554, Android 17 / API 37, at 1080 x 2400
  physical pixels and device pixel ratio 2.625. Inspected the rendered Home Screen
  and its status/navigation bar spacing. This device has a different logical
  viewport from the Figma frame, so it is a responsive check rather than the
  direct 390 x 844 comparison.
- Native interaction evidence: `android-upload.png` shows upload feedback,
  `android-menu.png` shows the open menu, and `android-about.png` shows the About
  dialog. `android-final.png` records the Home Screen after closing the dialog.
- Checked the app process's Flutter and AndroidRuntime error logs after the
  interactions; no error entries were returned.
- Baseline SHA-256 comparison confirms Android source/configuration,
  `pubspec.yaml`, `pubspec.lock`, and analyzer settings were unchanged.

## Implementation checklist

- [x] Preserve the Figma palette, reference proportions, and exact copy.
- [x] Correct the source assets and reference-size layout.
- [x] Keep controls reachable with safe areas, short screens, and large text.
- [x] Pass analyzer, formatting, and all widget tests.
- [x] Finish the installed Android emulator visual and interaction check.

final result: passed

# Stage 2: PDF Upload

Source of truth: `design_reference/upload_screen.png`, copied byte-for-byte from
the supplied `02 - PDF Upload.png` attachment. The requested project reference
path did not previously exist. The supplied image was accessible and was not
reconstructed or substituted. Its matching Figma frame is node `223:111`.

## Comparison evidence

- Source: `design_reference/upload_screen.png`, 390 x 844 pixels.
- Implementation: `build/upload-screen-qa/upload-first.png`, 390 x 844 pixels.
- Full comparison: `build/upload-screen-qa/comparison-first.png`; source left,
  Flutter right, both at the same initial screen state.
- Focused comparisons: `build/upload-screen-qa/heading-comparison.png` and
  `build/upload-screen-qa/card-comparison.png`.
- Viewport: 390 x 844 Flutter logical pixels, device pixel ratio 1, zero system
  insets, bundled Inter and Material Icons loaded, all image assets decoded,
  route transition finished, menu closed, no snackbar. Both images have the same
  density; no normalization was needed. CSS dimensions are not applicable.
- Small-screen capture: `build/upload-screen-qa/upload-small.png`, 320 x 568.
  Choose PDF stays visible while the upper content scrolls.

The first visual comparison found no actionable P0/P1/P2 differences, so no
visual correction iteration was required. Minor font-renderer differences and
approximately one pixel of heading alignment remain P3 polish. The shared
header retains the verified Home Screen appearance.

## Fidelity checks

- Typography: shared local Inter; 26 px heading, 18 px semibold card prompt,
  14 px regular secondary/supporting copy, and the existing 16 px primary button.
  Text can wrap and the card can grow with accessibility text.
- Layout: the header is x=24, y=40, 340 x 76; card is x=24, y=275, 342 x 315;
  Choose PDF is x=24, y=746, 342 x 56. The icon is 76 x 76 at x=157, y=310.
  Prompt, description, and supported-format text begin at y=414, 459, and 535.
  Source margins, radii, borders, and major spacing match the comparison.
- Colors: existing background, navy, teal, preview, border, accent, white, and
  secondary-gray tokens are reused without changes.
- Assets: original background and file-icon PNGs are reused unchanged. The
  32 x 32 cloud icon was exported directly from Figma node `223:138` as a
  transparent 96 x 96 PNG and renders in its original logical slot. No new
  runtime image URLs, icon approximations, or dependencies were introduced.
- Copy: Upload Your PDF, Select a PDF file to upload, Choose a PDF from your
  device., Supported format: PDF only, and Choose PDF match the approved image.

## Navigation and verification

- Home's Upload PDF action pushes `/pdf-upload`. Android system back and the
  Upload menu's Back to Home action pop the route. The closed header appearance
  remains unchanged. Home's scroll position survives navigation.
- Choose PDF is pinned above the navigation area. It currently displays
  `PDF selection is coming soon.`; it does not open a picker or processing flow.
- `flutter analyze`: passed with no issues.
- `flutter test`: all 25 passed. The 11 original Home scenarios are retained,
  with upload assertions updated for navigation, plus 14 new Upload tests.
- Responsive tests cover 320 x 568, 360 x 640, 390 x 844, 600 x 960, 844 x 390,
  portrait and landscape insets/side cutouts, fixed button placement during
  scrolling, and 2x accessibility text.
- Home preservation: `build/home-screen-qa/stage-two-home.png` is byte-identical
  to the verified Stage 1 `build/home-screen-qa/after.png`.
- Android: built, installed, and checked on emulator-5554, Android 17 / API 37,
  1080 x 2400 physical pixels, device pixel ratio 2.625. This is a responsive
  device check; the direct reference comparison uses the 390 x 844 render above.
- Native screenshots in `build/upload-screen-qa/`: `android-upload.png`,
  `android-choose.png`, `android-back.png`, `android-menu.png`, and
  `android-menu-back.png` document the screen, placeholder feedback, Android
  back, menu, and menu back. `android-final.png` shows the Upload screen left
  open for inspection.
- Flutter and AndroidRuntime error logs for the running app returned no errors.
- Baseline hashes confirm Android source/configuration, SDK/NDK configuration
  files, dependency files, existing assets/fonts, and analyzer settings unchanged.

## Stage 2 checklist

- [x] Access and retain the exact approved reference.
- [x] Reuse the verified design system and preserve Home's appearance.
- [x] Implement only PDF Upload, navigation, and placeholder Choose PDF feedback.
- [x] Keep Choose PDF visible on short screens and respect system safe areas.
- [x] Pass analyzer, formatting, and all tests.
- [x] Verify visual fidelity and both back paths on the Android emulator.

Native file selection, PDF processing, and backend functionality remain deferred.

final result: passed

# Stage 3: Native PDF selection

The approved initial views remain unchanged. The Stage 3 captures
`build/home-screen-qa/stage-three-home.png` and
`build/upload-screen-qa/stage-three-upload.png` are byte-identical to the verified
prior-stage Home and Upload captures, respectively. Viewports remain 390 x 844
logical/physical pixels at device pixel ratio 1, with the same fonts, assets,
closed-menu state, zero system insets, and no snackbar. No density normalization
is needed. The earlier full and focused comparisons therefore remain valid for
typography, layout, colors, assets, and static copy.

## Stage 3 functional evidence

- `flutter analyze --no-pub`: passed, no issues.
- `flutter test --no-pub`: 58 passed, including all previous 25 screen scenarios
  (the placeholder assertion now tests actual selection through an injected
  picker), 21 service tests, four plugin-adapter tests, and eight additional UI
  tests. Tests cover asynchronous completion, navigation during selection,
  retention, cancellation, validation/access errors, and bounded streaming.
- `flutter run --no-pub -d emulator-5554 --no-resident`: APK built and installed
  successfully against the existing SDK 36 / NDK 28.2.13676358 configuration.
  The connected emulator is Android 17 / API 37, 1080 x 2400 at pixel ratio 2.625.
- A subsequent `flutter pub get` completed successfully. No Windows settings were
  changed to work around the initial optional desktop symlink setup warning.
- `build/selection-qa/native-picker.png` and `picker-downloads.png` show Android's
  real document picker. The UI hierarchy records `stage3-note.txt` disabled while
  PDF candidates are selectable, confirming native format filtering.
- `build/selection-qa/valid-confirmation-sequence.png` records the confirmation
  `Selected stage3-valid.pdf (602 B).` The complete fixture has a page, objects,
  cross-reference table, and trailer, and its cached Android copy was observed.
- `build/selection-qa/empty-error-sequence.png` shows empty-file rejection.
- `build/selection-qa/invalid-error-sequence.png` shows rejection of text content
  renamed with a PDF extension. The Choose PDF action remains visible with both
  confirmation and error snackbars.
- `build/selection-qa/android-cancel.png` shows Upload after canceling the native
  picker with Android back, with no error or confirmation snackbar.
- Flutter/AndroidRuntime error logs returned no entries after these interactions.
- Hashes confirm approved assets/reference, theme, visual widgets, Android
  SDK/NDK/build settings, and Android manifest unchanged. Generated native plugin
  registration files changed as part of adding file_picker.

Selection retains name, exact size, and a fresh readable stream reference for
the app session. Cancellation and rejected replacements preserve the prior PDF.
The service inspects nine header bytes and cancels the stream; native importing
may create a disk cache copy with a bounded buffer. No storage permissions,
PDF-content logging, full-file Dart memory read, parser, artificial progress,
watermark detection/removal, or backend integration was added.

Full PDF integrity and encrypted/corrupted-body handling are not verified by this
preliminary header check. Selection does not persist across process restarts,
and the cached reference is not guaranteed to survive cache removal. Provider
access failures are covered by automated fault injection, rather than by changing
emulator/provider permissions during manual verification.

final result: passed

# Stage 4: PDF Processing and real first-page preview

## Reference and comparison conditions

- Approved source: `design_reference/processing_screen.png`, copied byte-for-byte
  from the supplied `C:/Users/yvenk/Downloads/processing_screen.png.png`. The exact
  attachment was accessible; no missing design content was invented.
- Figma context: file `LBbaZL6BVE9djixis3rYnJ`, Processing node `223:144`. The
  attached frame and Figma screenshot agree. Existing Figma backgrounds, icon,
  bundled Inter font, colors, header, and button are reused.
- Direct comparison: reference and implementation are both 390 x 844 pixels at
  pixel ratio 1, text scale 1, zero system insets, menu closed, and no snackbar.
  Capture: `build/processing-qa/processing-390x844.png`; measured rectangles:
  `processing-390x844.json` in the same directory.
- This headless geometry capture injects an image rasterized from the complete
  two-page test fixture, because native pdfx rendering is not available in a
  widget-test process. It is not evidence of the native renderer. Native Android
  screenshots below verify the production service with the actual selected file.
- Full comparison: `build/processing-qa/reference-comparison.png`. Focused header,
  document/status, manual-section, card, and footer comparisons:
  `build/processing-qa/focused-comparison.png`. Both were inspected visually.
- Device check: emulator-5554, Android 17 / API 37, 1080 x 2400 physical pixels,
  pixel ratio 2.625 (approximately 411.43 x 914.29 logical pixels). Android's
  status/navigation areas are respected. Native screenshots were not stretched
  to the reference viewport; the separate 390 x 844 capture checks exact geometry.

## Visual findings

| Surface | Verified result |
| --- | --- |
| Layout and spacing | Header (24,40,340,76), heading y=164, filename y=225, track (42,300,306,10), manual heading y=382, helper y=415, card (24,460,342,250), button (24,746,342,56). Geometry matches the approved frame. |
| Typography | Existing bundled Inter, white headings, gray metadata/helper copy, original shared header/button styles. Page-count metadata fits the previously empty space at y=251. Long filenames and enlarged text wrap/scroll safely. Minor shared-header glyph spacing/rasterization differences from the source remain consistent with the already-approved implementation. |
| Colors | Flat source and implementation regions use the same #151515, #172838, #1B403B, #252631, #F4B9BD, and white values. The static track uses the existing #41424D border/track color. |
| Assets and preview | Decorative shapes and PDF icon reuse existing Figma exports. The central page is the selected document's genuine first page with its own aspect ratio; no SAMPLE watermark or simulated selection outline is drawn over it. |
| Copy and states | Actual filename, formatted size, and renderer-reported page count. No 55% claim: the track is empty/static and status reads `Not started — processing unavailable`. Manual selection is unavailable and Apply Selection is disabled, retaining approved button styling. |

The document content/filename, added metadata, honest pending status, and disabled
manual-selection helper text are intentional requirements of Stage 4. They do not
represent watermark detection or a processing result. No completion route exists.

Home preservation: `build/home-screen-qa/stage-four-home.png` is byte-identical to
`build/home-screen-qa/after.png`. Upload preservation:
`build/upload-screen-qa/stage-four-upload.png` is byte-identical to
`build/upload-screen-qa/upload-first.png`. These captures use the same initial
viewports/fonts/assets/states as their earlier approvals. Selection validation,
retention, cancellation, and picker adapter code/models remain unchanged.

## Automated verification

- `flutter analyze --no-pub`: passed, no issues.
- `flutter test --no-pub`: **101 passed**. All 58 prior scenarios remain; successful
  selection now expects Processing navigation with the same selected model.
- New coverage: 20 Processing UI/navigation/metadata/error/lifecycle/responsive
  cases, 12 preparation/service/reference/copy/cleanup cases, and 11 installed
  renderer API/resource/cancellation cases. No native picker or renderer is
  required in widget tests; their boundaries are injected.
- Existing Home/Upload regressions remain, including 320 x 568 phones, tablet,
  landscape, safe areas/cutouts, fixed footers, and large accessibility text.
  New Processing tests also cover long filenames, 2x text, error scrolling, safe
  back during rendering, ignored late results, and serialized resume/retry.
- Three additional font/asset-loaded screenshot capture checks passed for Home,
  Upload, and Processing. Dart source formatting checks passed.
- `flutter pub get`: completed successfully after dependency installation. No
  Windows settings were changed for optional desktop symlink support.

## Android verification

- `flutter run --no-pub -d emulator-5554 --no-resident`: debug APK built,
  installed, and launched successfully. Artifact:
  `build/app/outputs/flutter-apk/app-debug.apk`.
- The actual Android document picker is recorded in
  `build/processing-qa/android-native-picker.png` and `restart-picker.xml`.
- Selecting the complete 1,291-byte `stage4-preview.pdf` produced a real first
  page (navy title, colored chart, document text), displayed **1.3 KB • 2 pages**,
  and did not reopen the picker for rendering. Production evidence:
  `android-final-processing.png`, `final-processing.xml`, and the earlier
  `android-processing-valid.png` in `build/processing-qa/`.
- UI hierarchy confirms Apply Selection has `enabled=false`; tapping the button
  did not trigger processing/navigation. There is no percentage animation or
  completion claim.
- Header-valid `stage4-corrupt.pdf` has a malformed body and was rejected by the
  real native renderer. `android-corrupt.png` and `corrupt-result.xml` show the
  friendly damaged/password-protected message and Back to Upload action.
- The error action, Android hardware back, and header menu Back to Upload all
  returned to Upload. Evidence: `android-back-upload.png`,
  `upload-after-menu.xml`, and `cancel.xml`. Canceling a replacement picker
  produced no error and stayed on Upload.
- Home/background then app resume retained the completed preview and metadata:
  `android-resumed.png`. Automated tests cover interruption during pending native
  work, since the small native fixture renders too quickly to time reliably.
- A force-stop/restart returned safely to Home (`restart-home.xml`). A fresh
  Home > Upload > native picker > Processing flow was then verified through UI
  labels and a real selected file (`verify_native.py`, `final-processing.xml`).
  The final screen is left showing that valid preview for inspection.
- Flutter/AndroidRuntime error logs for the final app process contained no error
  entries. Unsupported-file handling was observed separately as an expected
  preview error state.

## Resource handling and limits

pdfx **2.11.0** is the only new direct dependency; file_picker **13.3.3** and
android_file_picker **2.1.6** remain unchanged. Exact required transitive versions
are locked in `pubspec.lock`. Generated Android/iOS/macOS/Windows plugin
registrations changed as required by pdfx. Baseline hashes confirm Android
SDK/NDK/build/manifest settings, analyzer configuration, previous design
references/assets/fonts, theme, and Stage 3 selection model/services unchanged.

Existing local references are opened directly and never deleted by the preview
service. Stream-only references are copied incrementally to a private temporary
directory with a fixed basename and a 256 MiB copy limit, then removed after
success, error, or cooperative cancellation. This is not a 256 MiB limit on
already-local PDFs. Native page/document handles close before owned-file cleanup.
The raster's long edge is capped at 1,024 pixels; no entire PDF is loaded into
Dart memory. Native document complexity can still consume rendering resources.

Native rendering cannot be forcibly stopped mid-call. Cancellation ignores late
UI results, waits for native completion/cleanup, and serializes resume/retry.
Missing/changed references, copy limits/failures, and renderer failures are tested
with injected faults. Cloud-provider-specific behavior and very large/complex
documents were not manually stress-tested. Abrupt process death may leave OS
cache files and deliberately loses the session-only selection; it does not
restore a stale Processing route.

This verifies opening/rendering the first page, not complete PDF integrity.
Password entry, zoom/page browsing, manual area selection, watermark detection,
removal, processing progress, backend integration, and Processing Completed remain
unimplemented. The build's future Kotlin Gradle migration warning is documented;
the current installed toolchain builds successfully without configuration changes.

final result: passed

# Stage 5: Manual watermark-area selection

## Design preservation

The approved `design_reference/processing_screen.png` remains unchanged. Stage 5
uses the existing Inter font, colors, decorative exports, header, preview card,
and primary button. Select/View/Clear replace the former unavailable helper copy
inside its existing space; a selected rectangle uses #F4B9BD, a two-logical-pixel
outline, and 16% translucent fill. No processing percentage or completion view is
introduced.

Direct captures use 390 x 844 pixels, device pixel ratio 1, text scale 1, zero
system insets, closed menus, and no snackbar. The reference, full comparison,
focused comparison, and measured rectangles were inspected:

- `build/manual-selection-qa/processing-initial-390x844.png`
- `build/manual-selection-qa/processing-selected-390x844.png`
- `build/manual-selection-qa/reference-comparison.png`
- `build/manual-selection-qa/focused-comparison.png`
- `build/manual-selection-qa/geometry.json` and `regression-geometry.json`
- `build/manual-selection-qa/stage-four-comparison.png`

Header (24,40,340,76), heading y=164, status track (42,300,306,10), manual heading
y=382, card (24,460,342,250), and button (24,746,342,56) retain their previous
geometry. Controls occupy (24,403,342,57). At enlarged text sizes controls wrap
and the content scrolls; the footer remains fixed above safe areas.

Home's `build/home-screen-qa/stage-five-home.png` and Upload's
`build/upload-screen-qa/stage-five-upload.png` are byte-identical to their Stage 4
captures. A separate same-PDF Processing comparison uses Stage 4's exact filename,
size, page count, raster, and fonts. **Every pixel outside the new manual-control
rectangle is identical to Stage 4**, including the actual document preview. Its
masked difference is `build/manual-selection-qa/processing-regression-diff.png`.
The headless captures inject a raster for geometry/painting; production native
rendering and gestures are verified separately below.

## Architecture and state behavior

- `PdfNormalizedRect` validates finite, ordered unit coordinates. Geometry uses
  the same centered contain-fit rectangle as image placement, excluding both
  horizontal and vertical letterboxing. Global pointer coordinates are converted
  into local coordinates with the current render transform. No Figma positions
  or physical device pixels become PDF coordinates.
- Drag starts must be inside the actual page. Endpoints outside it are clipped.
  Both edges must reach eight preview-local logical pixels and 2% of the matching
  page dimension. Zero/tiny/invalid regions are rejected. Reversed drags work.
- Select mode captures page drags before the surrounding scroll view; dark card
  margins still scroll. View mode permits ordinary scrolling over the page and
  cannot change the region. No zoom/pan or user rotation is offered. Multi-touch,
  layout changes during a gesture, and pointer/lifecycle cancellation discard
  the unfinished gesture while preserving an earlier valid region.
- The application owns `PdfAreaSelectionController`. Draft and committed regions
  are separate. Apply is disabled without a valid, ready region or during a drag
  or pending Apply. It verifies readable access, stores an immutable selection
  model, and confirms only **Watermark area selected. PDF unchanged.** The model
  includes opaque session document identity, the same `SelectedPdf` reference,
  page number 1, normalized bounds, raster dimensions, and the explicit
  `renderedPageTopLeft` coordinate-space convention.
- Replacement clears the earlier commitment; Clear removes both draft and
  commitment. New selected models reset all area state even with matching
  filenames/URIs. Same-model navigation preserves completed areas after a matching
  preview. Changed dimensions/rendered bytes, failed previews, and unreadable
  references invalidate stale regions. Late Apply/render results cannot commit
  to a different document or a disposed/backgrounded route.
- Readability checks consume only metadata and the first nonempty stream chunk,
  then cancel the stream. Only a bounded first-page PNG is held for comparison;
  no whole PDF is added to Dart memory. App code does not write PDF content or
  log document contents. Existing selection/render/copy services are retained.

## Automated verification

- `flutter analyze`: **passed, no issues** after the final code changes.
- `flutter test`: **170 passed**. The 101 prior scenarios remain, with the old
  unavailable-helper assertion updated to working controls and initially disabled
  Apply. Added suites contain 23 geometry, 23 controller, and 23 widget/navigation
  cases, for 69 additional tests.
- Coverage includes unit-coordinate round trips at different sizes, both kinds
  of letterboxing, page boundaries, reversal, tiny/invalid/non-finite areas,
  portrait/landscape rasters and viewports, ancestor scaling, scroll arbitration,
  replacement/Clear/Apply, multi-touch cancellation, device-layout changes during
  dragging, navigation, background/resume, late asynchronous results, reference
  expiry, changed previews, same-name document replacement, bounded reads, and
  original file bytes/modification time remaining unchanged.
- Font/asset-loaded capture checks passed for Home, Upload, the new selected
  document, and the same-PDF Processing regression. A capture exposed fallback
  fonts in the new controls; explicitly using Inter corrected it before the
  final full test run and APK build. Dart formatting checks passed.

## Android build and native verification

Completed command:

```powershell
flutter build apk --debug --target-platform android-x64 --no-pub
```

The x64 debug APK built successfully and installed on emulator-5554 using
`adb install -r`. Artifact: `build/app/outputs/flutter-apk/app-debug.apk`;
build log: `build/manual-selection-qa/android-build.log`. An initial unrestricted
ABI build was stopped while downloading uncached ARM engine artifacts; the
completed build targets the emulator's cached x64 runtime. SDK/NDK/build settings
were not modified. The existing pdfx future Kotlin Gradle migration warning
remains; it did not prevent the completed build.

Device: Android 17 / API 37, 1080 x 2400 physical pixels, density 420, pixel ratio
2.625 (approximately 411.43 x 914.29 logical pixels). Native landscape screenshots
use 2400 x 1080. Actual Android screenshots retain system insets and were not
stretched to the reference viewport. The emulator runtime initially required a
restart after its Android system service/storage stopped responding; no SDK/NDK
configuration was changed. Android's document picker was exercised with genuine
fixture files. Native UI automation waits for file rows and avoids partially
clipped titles behind the system navigation bar.

Complete PDFs with native `/Rotate` values 0, 90, 180, and 270 were selected and
rendered through the unchanged file-picker/pdfx implementation. The asymmetric
blue rectangle in each source PDF provides a known page target. Real touch drags
created the pink outline, and screenshot pixel measurements confirmed alignment:

| Native PDF rotation | Expected displayed normalized bounds (left, top, right, bottom) | Measured outline, rounded |
| --- | --- | --- |
| 0 | 0.10, 0.30, 0.50, 0.50 | 0.0988, 0.2998, 0.5000, 0.5009 |
| 90 | 0.50, 0.10, 0.70, 0.50 | 0.4994, 0.0998, 0.6996, 0.5011 |
| 180 | 0.50, 0.50, 0.90, 0.70 | 0.5000, 0.5009, 0.9012, 0.7002 |
| 270 | 0.30, 0.50, 0.50, 0.90 | 0.3004, 0.5011, 0.4994, 0.9002 |

Maximum observed edge difference is approximately 0.001235 normalized units
(0.124% of a page edge), consistent with physical-touch and hierarchy/pixel
rounding. The zero-rotation check used `stage5-expired.pdf` before inducing
expiration; it is byte-identical to `stage5-native-0.pdf`. Coordinates are on the
page **as rendered**, including its native rotation, not raw PDF object space.

Evidence under `build/manual-selection-qa/`:

- `rotation-0/90/180/270-result.json`, corresponding `*-selected.png`,
  `*-confirmed.png`, and UI hierarchies record genuine page bounds, outline,
  valid-only Apply, and the unchanged Not started state. The 90-degree confirmation
  was inspected in `android-rotated-preview.png`; its snackbar had expired before
  a later hierarchy dump. The 180-degree screenshot caught the closing animation;
  confirmation was also observed cleanly in the zero/270-degree checks.
- `replacement.png`, `cleared.png`, `view-mode-preserves-area.png`, and
  `resumed.png` verify replacement, Clear disabling Apply, View not changing the
  region, and completed areas surviving Home/background/resume. Hardware back and
  header-menu Back to Upload were exercised, including
  `processing-menu-back-upload.xml`.
- `landscape-result.json` and `android-landscape-replaced.png` verify a completed
  area surviving device rotation, scrolling outside the page to reach it, a new
  accurately mapped drag in landscape, and a reachable enabled Apply footer.
  The runtime window-rotation preference was restored to its original `free` mode.
- `expired-result.json`, `android-expired-reference.png`, and
  `expired-reference-error.xml` verify real access failure between preview and
  Apply. Only private cache copies of the generated expiration fixture were
  temporarily renamed. Apply rejected the missing reference, cleared area state,
  disabled Apply/Clear, and offered Back to Upload. All seven matching cache copies
  were restored in cleanup; no backup files remain.
- `source-integrity-result.json` and before/after hashes confirm all five original
  generated PDFs in Android Downloads remain byte-for-byte unchanged.
  Flutter/AndroidRuntime error-level logs for the app process contained no entries.

## Scope, limits, and engine integration

No new packages were added. pdfx 2.11.0, file_picker 13.3.3, and
android_file_picker 2.1.6 remain installed. Hashes confirm 146 protected platform,
dependency, rendering/selection-model/service, theme, reference, and asset files
unchanged. The Stage 5 changed-file list is in README's Code layout section.

Only page one and one rectangular region are supported. There are no resize/move
handles, zoom/pan, automatic watermark detection, PDF edits/removal, downloads,
backend, artificial progress, or Processing Completed navigation. Users replace
an area by dragging again. Fit-page resolution and minimum-area thresholds limit
selection of very small features. State is memory-only and lost at process death.
Native verification covers this x64/API 37 emulator; physical ARM devices and
older Android versions were not manually verified in Stage 5.

Before connecting an engine, explicitly transform `renderedPageTopLeft` through
the engine's rotation, CropBox/MediaBox origins, units, and PDF axis conventions.
Pin/revalidate the document revision before mutation: session identity and a
matching first-page raster are not complete-document integrity verification.
A rectangle does not identify watermark objects or guarantee that overlapping
normal text/images can be removed safely. Provider-specific liveness and very
large/complex documents still need engine-level testing. Native rendering and
provider calls may finish after logical cancellation; late results are ignored.

final result: passed

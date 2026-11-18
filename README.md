# PDF Watermark Remover

Flutter Android application based on the [390 x 844 Figma design](https://www.figma.com/design/LBbaZL6BVE9djixis3rYnJ/PDF-Watermark-Remover---UI-UX-Design?node-id=221-2).

The app includes Home, PDF Upload, native Android PDF selection, and Stage 4's
PDF Processing screen with a real first-page document preview and Stage 5 manual
watermark-area selection.

Stage 6A adds a separate, tested Python annotation-watermark engine in
[`processing_engine/`](processing_engine/README.md), with
[real before/after evidence](processing_engine/VERIFICATION.md).
It is **not connected to Flutter**. The Android app still only previews and
records selections, and its processing status remains **Not started**.

Tap **Upload PDF**, then **Choose PDF** and select a PDF. A valid selection opens
PDF Processing with the same selected document; it does not reopen the picker.
Android back and **More options > Back to Upload** return to Upload. The approved
references are stored in [`design_reference/`](design_reference/).

All three screens reuse the local Inter font, original Figma backgrounds, header,
colors, and primary button styling. The Upload screen keeps **Choose PDF** above
the system navigation area while its content can scroll on shorter screens or
with large text. Choose PDF opens Android's document picker for one PDF. A valid
selection shows its name, size, available page count, and first page; canceling is
silent. Invalid types, empty files, bad PDF headers, and access failures show
concise errors. The approved
screen layouts and assets are unchanged.

## PDF selection and validation

- Direct dependency: [`file_picker` 13.3.3](https://pub.dev/packages/file_picker/versions/13.3.3).
  Its Android implementation resolves to `android_file_picker` 2.1.6 and platform
  interface 4.2.0. Exact transitive versions are recorded in `pubspec.lock`.
- Uses the installed `FilePicker.pickFile(type: FileType.custom,
  allowedExtensions: ['pdf'])` API. This selects a single file and returns null
  on cancellation; obsolete `FilePicker.platform` examples are not used.
- `PdfDocumentPicker` isolates the plugin dependency. `PdfSelectionService`
  checks the case-insensitive `.pdf` suffix, known positive size, readability,
  and a standard PDF header at byte zero (`%PDF-1.0` through `%PDF-1.7`, or
  `%PDF-2.0`, followed by LF or CR/CRLF).
- Only nine header bytes are retained and inspected, then the read stream is
  canceled. The platform stream may supply a larger bounded chunk. Neither the
  service nor UI calls `readAsBytes` or loads an entire PDF into Dart memory.
  Android's plugin may first copy the chosen document to its application cache
  using a bounded native buffer, so large/cloud files can take time to import.
- `SelectedPdf` retains the original name, exact byte size, and `PdfDocument`
  reference, including URI and `openRead()` for a fresh stream. The app owns one
  service across Home/Upload navigation. Canceling or rejecting a replacement
  preserves the previous valid selection; overlapping picker requests coalesce.
- No storage/media permissions were added, and app code does not log PDF
  contents or expose provider exception details.

Selection validation is **preliminary**. A matching header cannot establish full
PDF integrity. The native preview renderer additionally opens the document and
renders page one, but does not verify every page, object, or cross-reference.
No watermark detection/removal, processing progress, processing-success screen,
or backend was added.

The selected document is held for the current app session, not saved as a persistent
library. Android cache references may expire if files/cache are cleared. Preview
or selection access reports a missing reference and provides a return to Upload
to select again. Process restarts return safely to Home without restoring a stale
document.

## PDF Processing and real preview

- Direct dependency: [`pdfx` 2.11.0](https://pub.dev/packages/pdfx/versions/2.11.0).
  The installed `PdfDocument.openFile`, `getPage(1)`, and PNG `render` APIs use
  Android's native `PdfRenderer`. Rendering is separated from widgets behind
  injectable preview/renderer interfaces.
- Existing local document references are opened directly after checking their
  type and size. They are never deleted by the preview service. Stream-only
  references use a private temporary directory and constant filename, copying
  incrementally to disk with a 256 MiB limit. Both advertised and actual copy
  sizes are checked. Owned copies are removed after rendering, errors, or
  cooperative cancellation. An abrupt process kill can leave OS cache files;
  the app does not persist or restore a selected-document library.
- Only page one is rasterized, with a maximum 1,024-pixel long edge. The app
  retains that PNG rather than the entire PDF in Dart memory. Page/document
  handles close before temporary-file cleanup. Complex PDFs may still consume
  native rendering resources; this is not a full PDF viewer.
- Missing/changed references, copy limits, unsupported/password-protected or
  damaged PDFs, and rendering failures produce concise errors. Transient preview
  failures offer **Try again**; all failures offer **Back to Upload**. Underlying
  provider exceptions and document contents are not logged by app code.
- Back navigation cancels pending work and ignores late results. Backgrounded
  in-flight previews are canceled cooperatively and retried after resume and
  resource cleanup. Completed previews survive ordinary background/resume.
  Native rendering cannot be interrupted immediately; handles close when it
  returns. No new storage permissions are required.
- The approved background, header, card, typography, spacing, and pink button
  styling are reused. The reference's sample filename/page are replaced by the
  selected document. Its simulated 55% progress is replaced by an empty static
  track and **Not started — processing unavailable**. Stage 5 adds a pink selection
  outline and translucent fill to the real page. Apply Selection becomes enabled
  only for a valid area. No artificial progress, detection result, or completion
  route is added.

Only Android has been built and manually verified for this stage. Password entry,
zoom/page browsing, full integrity verification,
watermark detection/removal, and backend integration remain unimplemented.

## Manual watermark-area selection

1. Choose a PDF and wait for its first page to appear. **Select** is the default
   mode. Drag on the page to create a rectangular area. Drag again to replace it.
2. Use **View** to scroll by dragging over the document without changing the area.
   In Select mode, scroll outside the page. No page zoom or pan is implemented.
3. **Clear** removes both the draft and applied area. **Apply Selection** commits
   a valid area to application state and confirms **Watermark area selected. PDF
   unchanged.** Processing remains **Not started**.

The new controls occupy the previous manual-section helper space. The approved
header, heading, status track, preview card, button positions, backgrounds, colors,
and Inter typography are retained. Controls wrap at large accessibility text sizes.
Home and Upload initial captures remain byte-identical to Stage 4.

`PdfSelectionGeometry` uses the exact contain-fit rectangle used to place the
image. It subtracts letterboxing/centering and divides by the displayed page
width/height. Pointer positions are converted from global coordinates into the
preview's local frame; no screenshot offsets, fixed PDF coordinates, or device
pixel ratios are assumed. A change in that frame during a drag cancels the drag.
Starts outside the page are ignored and endpoints leaving the page are clipped.
Valid areas need both edges to be at least eight preview-local logical pixels and
2% of their corresponding page dimension. Non-finite, inverted, zero-area, and
out-of-bounds model coordinates are rejected. A rejected/canceled replacement
preserves the last valid area.

The app-owned `PdfAreaSelectionController` separates draft, active-drag, and
committed state. `PdfAreaSelection` records an opaque session document identity,
the same `SelectedPdf` readable reference, page number **1**, normalized bounds,
and raster dimensions. A newly selected model resets all old areas, including
reselecting the same filename/URI. Same-document navigation preserves completed
areas after a successful matching preview. Preview errors, expired references,
changed raster dimensions, or changed rendered bytes invalidate stale areas.
Only the bounded page PNG is retained for comparison, not a full PDF memory copy.

Apply performs a bounded readability preflight (known size and the first nonempty
stream chunk, then stream cancellation). Missing/changed/unreadable references
clear region state and show a return-to-Upload error. Late Apply results are
ignored after Clear, document replacement, backgrounding, or leaving the screen.
An unfinished gesture is canceled across lifecycle/layout interruptions; completed
areas survive ordinary background/resume. State is deliberately session-only and
does not survive process death. App code does not log PDF content.

Coordinates are explicitly **`renderedPageTopLeft`**, within `[0,1]`, relative to
the full first page as rendered by Android. Native page rotation is already baked
into this image, so a rotated page is selected in its displayed orientation. This
is **not unrotated PDF user space**. There is no additional user rotation, zoom,
pan, or resizable-handle mode; replacement dragging is supported.

Before integrating a real processing engine, map this declared coordinate space
through the engine's page rotation, CropBox/MediaBox origin and PDF coordinate
conventions. Verify an immutable document revision or full content identity before
mutation: a readable reference and matching first-page raster do not prove that
the entire PDF is unchanged. A rectangle identifies an area, not specific PDF
watermark objects; preserving overlapping text/images requires engine-level
validation. Stage 5 does not modify PDF content, remove watermarks, create
downloads, or claim processing completion.

## Run on the Android emulator

Start your emulator from Android Studio's Device Manager, then run in PowerShell:

```powershell
Set-Location 'C:\Users\yvenk\Desktop\APK\pdf_watermark_remover'
flutter devices
flutter run -d emulator-5554
```

Use the device ID reported by `flutter devices` if it differs. If Flutter is not
on your PATH, use the existing SDK directly:

```powershell
& 'C:\Users\yvenk\Desktop\APK\flutter_windows_3.50.0-stable\flutter\bin\flutter.bat' run -d emulator-5554
```

Press `r` in the Flutter terminal to hot reload, or `q` to stop the run.

## Checks

```powershell
flutter analyze
flutter test
```

Stage 5: **170 tests pass**, including all 101 previous scenarios and 69 new
selection cases (23 geometry, 23 controller, and 23 widget/navigation cases).
Existing initial-state assertions now expect the working Select/View/Clear
controls and require a region before Apply is enabled. New tests cover letterbox
mapping, parent scaling, portrait/landscape, boundaries, minimum areas, reversal,
two-finger cancellation, replacement/Clear/Apply, reference expiry, changed
previews, document changes, late asynchronous results, navigation, lifecycle, and
unchanged source-file bytes/modification time. No new dependencies were added;
pdfx 2.11.0 and file_picker 13.3.3 remain installed.

`flutter analyze` completed with no issues. The completed Android build used
`flutter build apk --debug --target-platform android-x64 --no-pub`; its debug APK
installed successfully on emulator-5554. The initial unrestricted ABI attempt
was stopped while downloading additional ARM runtimes. No SDK/NDK settings were
changed. Physical ARM builds/devices are not verified in this stage.

Native checks passed for actual first-page PDFs at 0/90/180/270 degrees, accurate
touch outlines, valid-only Apply/confirmation, replacement, Clear, View mode,
hardware/menu back, background/resume, device landscape, and a real expired cache
reference between preview and Apply. Temporary fixture cache renames were all
restored. All five original fixture PDFs retained their SHA-256 hashes, and app
Flutter/AndroidRuntime error logs were empty. Screenshots, source PDFs, measured
results, and scripts are in `build/manual-selection-qa/`; see `design-qa.md` for
the full evidence and coordinate-space limitations.

Stage 4 baseline: **101 tests passed**, and the analyzer reported no issues. All 58 earlier
scenarios remain, with successful-selection UI assertions updated to expect
Processing navigation. The 43 added tests cover the same-model handoff, actual
metadata/preview bytes, disabled actions, failures and retry, safe back and late
results, background/resume, phone/tablet/landscape/safe areas/large text, bounded
stream copies and cleanup, expired references, native API calls, and handle
closure. Renderer tests use injected native objects; real rendering was verified
separately on Android.

Commands executed: `flutter analyze --no-pub`, `flutter test --no-pub`, and
`flutter run --no-pub -d emulator-5554 --no-resident`. The debug APK built and
installed successfully. A subsequent normal `flutter pub get` also succeeded.
No system settings were changed. The build warns that pdfx's Kotlin Gradle Plugin
support will require a future Flutter migration; current settings build correctly
and were preserved.

On emulator-5554 (Android 17 / API 37, 1080 x 2400 at pixel ratio 2.625), a complete
two-page, 1,291-byte fixture rendered its genuine first page with **1.3 KB • 2
pages** metadata. A header-valid PDF with a malformed body reached the preview
error state. Native picker cancellation, error recovery, hardware/menu back,
disabled Apply Selection, background/resume, and reopening after process restart
were checked. Expired references, copy failures/limits, and mid-render interruption
are covered by automated tests; cloud-provider-specific failures were not induced.
Screenshots, fixture generation, and UI hierarchies are in `build/processing-qa/`.

Home and Upload captures remain byte-identical to their approved prior-stage
captures. Three additional screenshot capture checks passed. The 390 x 844
Processing capture checks geometry with an injected raster; Android screenshots
verify the production native renderer.

The reference layout places the PDF preview at y=195, the heading at y=578, the
description at y=650, and the upload button at y=746 with a 42 px bottom margin.
Shorter screens and larger accessibility text can scroll rather than overflow.

See [design-qa.md](design-qa.md) for the visual comparison and verification notes.

## Code layout

Stage 5 changed files:

- Added `lib/models/pdf_area_selection.dart`,
  `lib/services/pdf_area_selection_controller.dart`,
  `lib/utils/pdf_selection_geometry.dart`,
  `lib/widgets/pdf_page_selection_view.dart`, and
  `lib/widgets/pdf_selection_controls.dart`.
- Updated `lib/main.dart`, `lib/screens/home_screen.dart`,
  `lib/screens/pdf_upload_screen.dart`, `lib/screens/pdf_processing_screen.dart`,
  and `lib/widgets/pdf_document_preview_card.dart` to share and display the
  application-owned selection state.
- Added `test/pdf_selection_geometry_test.dart`,
  `test/pdf_area_selection_controller_test.dart`, and
  `test/pdf_manual_selection_test.dart`; updated `test/pdf_processing_screen_test.dart`.
- Updated `README.md` and `design-qa.md`. Local capture scripts, generated test
  PDFs, screenshots, and verification logs live under ignored `.dart_tool/` and
  `build/manual-selection-qa/`.

The dependency manifests/lockfile, Android/SDK/NDK/permission settings, existing
rendering and file-selection services/models, Figma references/assets, theme,
header, and primary-button widget are unchanged in Stage 5.

Stage 4 updates `main.dart`, Home/Upload navigation, `home_header.dart` (back-menu
label), and `upload_pdf_button.dart` (disabled styling). It adds the Processing
screen, preview model/card/services, shared size formatter, three test suites and
preview test doubles listed below. Existing Upload tests now assert the genuine
Processing handoff. `pubspec.yaml`, `pubspec.lock`, this README, and `design-qa.md`
are updated; the approved Processing attachment is added to `design_reference/`.
The selected-document model, selection service, picker adapter, theme, and existing
assets are unchanged.

Flutter automatically updates these dependency registration files:
`android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java`,
`ios/Runner/GeneratedPluginRegistrant.m`,
`macos/Flutter/GeneratedPluginRegistrant.swift`,
`windows/flutter/generated_plugin_registrant.cc`, and
`windows/flutter/generated_plugins.cmake`.

- `lib/main.dart`: application entry point, font license registration, and shared
  injectable session selection/preview services.
- `lib/theme/app_theme.dart`: shared design colors and dark theme.
- `lib/screens/home_screen.dart`: responsive, scrollable Home Screen layout.
- `lib/screens/pdf_upload_screen.dart`: PDF Upload route, safe areas, scrollable
  content, fixed Choose PDF action, selection/error feedback, and Processing handoff.
- `lib/screens/pdf_processing_screen.dart`: real metadata, pending processing
  state, lifecycle-aware preview, and back navigation.
- `lib/models/selected_pdf.dart`: selected metadata and readable content contract.
- `lib/models/pdf_page_preview.dart`: bounded first-page image and page count.
- `lib/services/pdf_document_picker.dart`: testable picker boundary.
- `lib/services/file_picker_pdf_document_picker.dart`: installed plugin adapter.
- `lib/services/pdf_selection_service.dart`: preliminary validation and retained
  session selection, independently of UI widgets.
- `lib/services/pdf_preview_service.dart`: preview errors, cancellation, and
  injectable service/renderer contracts.
- `lib/services/pdf_preview_file_store.dart`: direct references and bounded owned
  temporary copies, with cleanup.
- `lib/services/local_pdf_preview_service.dart`: preparation/render/cleanup coordination.
- `lib/services/pdfx_first_page_renderer.dart`: installed native rendering API,
  raster limits, and page/document handle closure.
- `lib/utils/file_size.dart`: shared size formatting extracted from Upload.
- `lib/widgets/`: shared header, background, primary button, Home PDF preview,
  PDF Upload card, and the new `pdf_document_preview_card.dart`.
- `test/pdf_upload_screen_test.dart`: Upload, navigation, and selection UI tests.
- `test/pdf_selection_service_test.dart`: validation, retention, and streaming tests.
- `test/file_picker_pdf_document_picker_test.dart`: plugin API/adapter tests.
- `test/pdf_processing_screen_test.dart`: navigation, metadata, preview/error UI,
  disabled actions, lifecycle, and responsive regression coverage.
- `test/pdf_preview_service_test.dart`: reference/copy/cleanup/error tests.
- `test/pdfx_first_page_renderer_test.dart`: installed rendering API and resource tests.
- `test/fakes/`: picker, content, and preview doubles.
- `design_reference/upload_screen.png`: the approved attachment, copied unchanged.
- `design_reference/processing_screen.png`: the approved Stage 4 attachment,
  copied unchanged from `processing_screen.png.png`.
- `assets/`: transparent Figma exports at 3x resolution and the Inter font with
  its SIL Open Font License. The images render at their original logical sizes.

Inter is bundled from [Google Fonts](https://github.com/google/fonts/tree/main/ofl/inter).
The existing dependencies are retained. Stage 4 adds pdfx and its required
transitive packages. Flutter updated generated Android/iOS/macOS/Windows plugin
registrations. Android build, SDK/NDK, and permission configuration remain unchanged.

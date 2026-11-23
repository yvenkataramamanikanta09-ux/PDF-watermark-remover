# PDF Watermark Remover

An Android app (Flutter, Material 3) that removes watermarks from PDFs **on the
phone itself**. There is no server and no network access: the Python PDF engine
is packaged inside the APK (using [Chaquopy](https://chaquo.com/chaquopy/)), your
PDF is copied into the app's private cache, processed there, and the cleaned copy
is saved wherever you choose. The original file is never changed.

```
Android app (Dart, lib/)  ──channel──▶  MainActivity.kt  ──▶  pdfwm_mobile.py  ──▶  engine (processing_engine/)
choose, mark, save                       Chaquopy host         JSON entry points      pypdf + PDFium + Pillow, in-process
```

## What it removes

- **Automatic:** PDF watermark annotations (`/Subtype /Watermark`) and
  Acrobat-style watermark layers (page content marked `/Artifact` with
  `/Subtype /Watermark`).
- **Mark area:** you drag a rectangle around the watermark on page 1. Every
  page object (text, image, vector shape) that lies **fully inside** that
  rectangle is removed, on every page or only on page 1. Objects that only
  partly overlap are kept.

After every removal the engine renders each page before and after and refuses
to produce a file if anything outside the removed area changed.

It does **not** handle password-protected or digitally signed PDFs, and it
cannot remove a watermark that is baked into a scanned page image. See
[processing_engine/README.md](processing_engine/README.md) for the exact scope.

## Phone requirements and limits

- 64-bit ARM Android phone (arm64-v8a), Android 7.0 (API 24) or newer. The
  embedded Python and the PDFium library are shipped for arm64 only.
- PDFs up to 40 MB and 100 pages. The engine runs inside the app's process, so
  these limits are lower than on a PC; the app shows the limit before accepting a file.
- The APK is about 40 MB because it contains Python, PDFium and Pillow.

**Checking a phone:** open the "…" menu on the Home screen and tap **Check PDF
engine**. It runs the whole engine once on a built-in sample PDF and shows each
step and the library versions. If that dialog reports a failure, the engine
cannot run on that phone; please send the error code shown.

## Using the app

1. **Upload PDF**, then **Choose PDF**. The file is copied into the app and
   checked; page 1 is shown.
2. Drag a rectangle around the watermark and tap **Apply Selection**. If a
   watermark was detected, **Automatic** is offered as well.
3. **Download PDF** lets you choose where the cleaned copy is saved.

The screens follow the
[Figma design](https://www.figma.com/design/LBbaZL6BVE9djixis3rYnJ/PDF-Watermark-Remover---UI-UX-Design?node-id=224-344)
and are built from Material 3 components. `flutter test test/design_capture_test.dart`
renders every screen at the Figma frame size into `build/design_captures/`.

## Build the APK

Needs Flutter 3.50, JDK 17 and the Android SDK (platform 36, NDK 28.2). The first
build also downloads Chaquopy's Python 3.13 runtime and the Python packages.
Python 3.13 must be installed on the build machine (Chaquopy uses it to run pip).

```powershell
flutter pub get
flutter build apk --release --target-platform android-arm64
```

The APK is written to `build\app\outputs\flutter-apk\app-release.apk`. Release
builds are currently signed with the debug key and use the application id
`com.example.pdf_watermark_remover`. Both must change before publishing to a
store.

Notes on the Android build (`android/app/build.gradle.kts`):

- `disable-abi-filtering=true` in `android/gradle.properties` stops Flutter from
  adding 32-bit ARM, which the embedded Python (Chaquopy 17) does not support.
- The engine is taken straight from `processing_engine/pdf_watermark_engine`;
  `android/app/src/main/python/pdfwm_mobile.py` is the entry point.
- Python packages: `pypdf` 7.1.0, `pypdfium2` 5.15.2 (Android wheel from PyPI)
  and Pillow 11.0.0 (Chaquopy's Android build; PyPI has none). The engine only
  uses Pillow's `ImageChops` and `ImageDraw`, which are the same in 11 and 12.
- `pypdfium2` and `pypdfium2_raw` are unpacked to real files at run time because
  pypdfium2 loads `libpdfium.so` by path.

## Tests

```powershell
flutter analyze
flutter test
python -m venv processing_engine\.venv
processing_engine\.venv\Scripts\python.exe -m pip install -e .\processing_engine
processing_engine\.venv\Scripts\python.exe -m unittest discover -s processing_engine\tests
```

`flutter test` covers the screens (with a fake engine) and the platform-channel
client. The engine suite also runs the Android adapter (`pdfwm_mobile.py`) and
the engine's in-process mode on the PC. **What no automated test here proves** is
that the packaged Python and PDFium start on a real phone; use **Check PDF
engine** for that.

## Code layout

- `lib/main.dart`: app entry; wires the picker, the on-device engine and the saver.
- `lib/theme/app_theme.dart`: the Figma colours as a Material 3 dark theme, the
  type scale (Newsreader for headlines, Figtree for everything else) and all
  component themes.
- `lib/screens/`: the five Figma frames (`home_screen`, `pdf_upload_screen`,
  `pdf_processing_screen`, `pdf_result_screen`, `pdf_error_screen`).
- `lib/services/`: `pdf_engine` (the engine interface and error types),
  `on_device_pdf_engine` (talks to Kotlin over the `pdfwm/engine` channel and
  copies the picked PDF into a job folder), `pdf_selection_service` +
  `file_picker_pdf_document_picker` (picking and first checks),
  `pdf_area_selection_controller`, `pdf_saver`.
- `lib/widgets/`: `app_screen` (shared frame: background, header, pinned
  action), `home_header`, `pdf_upload_card`, `removal_info_sheet`,
  `engine_check_dialog`, `pdf_page_selection_view` (drawing the rectangle;
  touches are mapped to page fractions by `lib/utils/pdf_selection_geometry.dart`).
- `android/app/src/main/kotlin/.../MainActivity.kt`: starts Python, runs every
  call on one background thread, owns the job folders under the app cache.
- `android/app/src/main/python/pdfwm_mobile.py`: JSON entry points (`info`,
  `analyze`, `remove`, `self_test`, `purge`).
- `processing_engine/`: the removal engine, its tests and its own documentation.

Figtree (sans serif) and Newsreader (serif) are bundled from
[Google Fonts](https://github.com/google/fonts) under the SIL Open Font License;
the licence texts are in `assets/fonts/` and in the app's licence page. Licence
notes for the engine's libraries are in
[processing_engine/DEPENDENCIES.md](processing_engine/DEPENDENCIES.md).

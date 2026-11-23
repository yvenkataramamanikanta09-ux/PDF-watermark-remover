// Renders each screen at the Figma frame size (390 x 844) with the real fonts
// and assets, and writes PNGs to build/design_captures/ for comparison with
// the design. Run: flutter test test/design_capture_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf_watermark_remover/models/selected_pdf.dart';
import 'package:pdf_watermark_remover/screens/home_screen.dart';
import 'package:pdf_watermark_remover/screens/pdf_error_screen.dart';
import 'package:pdf_watermark_remover/screens/pdf_processing_screen.dart';
import 'package:pdf_watermark_remover/screens/pdf_result_screen.dart';
import 'package:pdf_watermark_remover/screens/pdf_upload_screen.dart';
import 'package:pdf_watermark_remover/services/app_services.dart';
import 'package:pdf_watermark_remover/services/pdf_selection_service.dart';
import 'package:pdf_watermark_remover/theme/app_theme.dart';

import 'fakes/engine_fakes.dart';
import 'fakes/pdf_selection_fakes.dart';

const _boundaryKey = ValueKey('capture-boundary');

Future<void> _loadFonts() async {
  for (final (family, file) in const [
    ('Figtree', 'assets/fonts/Figtree-Variable.ttf'),
    ('Newsreader', 'assets/fonts/Newsreader-Variable.ttf'),
  ]) {
    await (FontLoader(family)..addFont(rootBundle.load(file))).load();
  }
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) {
    final icons = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (icons.existsSync()) {
      final loader = FontLoader('MaterialIcons')
        ..addFont(icons.readAsBytes().then((bytes) => ByteData.view(bytes.buffer)));
      await loader.load();
    }
  }
}

/// A white portrait page with a grey "watermark" band, as a stand-in preview.
Future<Uint8List> _samplePage() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 232, 300), Paint()..color = Colors.white);
  canvas.drawRect(
    const Rect.fromLTWH(36, 120, 160, 48),
    Paint()
      ..color = const Color(0xFFDDDDDD)
      ..style = PaintingStyle.fill,
  );
  final image = await recorder.endRecording().toImage(232, 300);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

void main() {
  late FakeEngine engine;
  late AppServices services;

  setUpAll(_loadFonts);

  setUp(() {
    engine = FakeEngine();
    services = AppServices(
      pdfSelection: PdfSelectionService(picker: FakePdfDocumentPicker()),
      engine: engine,
      saver: FakeSaver(),
    );
  });

  Future<void> capture(WidgetTester tester, String name, Widget screen) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepaintBoundary(
        key: _boundaryKey,
        child: MaterialApp(debugShowCheckedModeBanner: false, theme: AppTheme.dark, home: screen),
      ),
    );
    // Let async work (fake upload, preview fetch) finish on the real event loop,
    // then decode every image for real before painting.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pump();
    await tester.runAsync(() async {
      for (final element in find.byType(Image).evaluate()) {
        await precacheImage((element.widget as Image).image, element);
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_boundaryKey));
    final bytes = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
    final directory = Directory('build/design_captures')..createSync(recursive: true);
    File('${directory.path}/$name.png').writeAsBytesSync(bytes!);
    expect(tester.takeException(), isNull);
  }

  testWidgets('capture: home', (tester) async {
    await capture(tester, '1_home', HomeScreen(services: services));
    expect(find.text('Upload PDF'), findsOneWidget);
  });

  testWidgets('capture: upload', (tester) async {
    await capture(tester, '2_upload', PdfUploadScreen(services: services));
    expect(find.text('Choose PDF'), findsOneWidget);
  });

  testWidgets('capture: processing', (tester) async {
    final page = await tester.runAsync(_samplePage);
    engine.previewBytes = page;
    final document = FakePdfDocument(name: 'sample_document.pdf');
    await capture(
      tester,
      '3_processing',
      PdfProcessingScreen(
        pdf: SelectedPdf(name: 'sample_document.pdf', size: 245760, content: document),
        services: services,
      ),
    );
    expect(find.text('Apply Selection'), findsOneWidget);
  });

  testWidgets('capture: completed', (tester) async {
    final page = await tester.runAsync(_samplePage);
    await capture(
      tester,
      '4_completed',
      PdfResultScreen(
        job: job(status: 'succeeded', mode: 'area', outcome: 'watermark_removed_successfully',
            removed: 3, pagesChanged: [1, 2, 3]),
        cleanedFileName: 'sample_document_cleaned.pdf',
        preview: page,
        engine: engine,
        saver: FakeSaver(),
      ),
    );
    expect(find.text('Download PDF'), findsOneWidget);
  });

  testWidgets('capture: error', (tester) async {
    await capture(
      tester,
      '5_error',
      const PdfErrorScreen(
        details: PdfErrorDetails(
          title: 'Watermark Removal Failed',
          message: "We couldn't remove the watermark. Please try processing again.",
          code: 'WATERMARK_REMOVAL_FAILED',
        ),
      ),
    );
    expect(find.text('Try Again'), findsOneWidget);
  });
}

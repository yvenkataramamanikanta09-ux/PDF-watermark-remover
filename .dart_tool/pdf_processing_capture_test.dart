import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf_watermark_remover/models/pdf_page_preview.dart';
import 'package:pdf_watermark_remover/models/selected_pdf.dart';
import 'package:pdf_watermark_remover/screens/pdf_processing_screen.dart';
import 'package:pdf_watermark_remover/theme/app_theme.dart';
import 'package:pdf_watermark_remover/widgets/home_header.dart';
import 'package:pdf_watermark_remover/widgets/pdf_document_preview_card.dart';

import '../test/fakes/pdf_preview_fakes.dart';
import '../test/fakes/pdf_selection_fakes.dart';

// Geometry capture only. Production pdfx rendering is verified on Android.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final entry in {
      'Inter': 'assets/fonts/Inter-Variable.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      final loader = FontLoader(entry.key)..addFont(rootBundle.load(entry.value));
      await loader.load();
    }
  });

  testWidgets('Capture Processing geometry with approved fonts and assets', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final directory = Directory('build/processing-qa')..createSync(recursive: true);
    final pageBytes = File('${directory.path}/fixture-first-page.png').readAsBytesSync();
    final document = FakePdfDocument(name: 'stage4-preview.pdf');
    final selected = SelectedPdf(name: document.name, size: 1291, content: document);
    final service = FakePdfPreviewService(onRender: (_, _) async => PdfPagePreview(
      bytes: pageBytes, width: 576, height: 1024, pageCount: 2,
    ));
    final captureKey = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
      key: captureKey,
      child: MaterialApp(debugShowCheckedModeBanner: false, theme: AppTheme.dark, home: PdfProcessingScreen(
        selectedPdf: selected, previewService: service,
      )),
    ));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      for (final asset in ['navy_ellipse.png', 'teal_ellipse.png', 'file_icon.png']) {
        await precacheImage(AssetImage('assets/images/$asset'), captureKey.currentContext!);
      }
      await precacheImage(MemoryImage(pageBytes), captureKey.currentContext!);
    });
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final geometry = <String, Object>{};
    for (final entry in {
      'header': find.byType(HomeHeader),
      'heading': find.text('Processing Your PDF'),
      'document': find.text('Document: stage4-preview.pdf'),
      'metadata': find.text('1.3 KB • 2 pages'),
      'track': find.byKey(const ValueKey('processing-not-started-track')),
      'status': find.text('Not started — processing unavailable'),
      'manual': find.text('Manual Watermark Selection'),
      'description': find.text('Manual selection is not available yet.'),
      'card': find.byType(PdfDocumentPreviewCard),
      'button': find.widgetWithText(FilledButton, 'Apply Selection'),
    }.entries) {
      final rect = tester.getRect(entry.value);
      geometry[entry.key] = {'x': rect.left, 'y': rect.top, 'width': rect.width, 'height': rect.height};
    }
    await tester.runAsync(() async {
      final boundary = captureKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final capture = await boundary.toImage(pixelRatio: 1);
      final bytes = await capture.toByteData(format: ui.ImageByteFormat.png);
      await File('${directory.path}/processing-390x844.png').writeAsBytes(bytes!.buffer.asUint8List());
      await File('${directory.path}/processing-390x844.json').writeAsString(const JsonEncoder.withIndent('  ').convert(geometry));
      capture.dispose();
    });
  });
}

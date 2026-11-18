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
import 'package:pdf_watermark_remover/services/pdf_area_selection_controller.dart';
import 'package:pdf_watermark_remover/theme/app_theme.dart';
import 'package:pdf_watermark_remover/widgets/home_header.dart';
import 'package:pdf_watermark_remover/widgets/pdf_document_preview_card.dart';
import 'package:pdf_watermark_remover/widgets/pdf_selection_controls.dart';

import '../test/fakes/pdf_preview_fakes.dart';
import '../test/fakes/pdf_selection_fakes.dart';

// Geometry/paint capture. Production native rendering is verified on Android.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final entry in {'Inter': 'assets/fonts/Inter-Variable.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf'}.entries) {
      final loader = FontLoader(entry.key)..addFont(rootBundle.load(entry.value));
      await loader.load();
    }
  });
  testWidgets('Capture manual selection with approved fonts, assets and geometry', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final directory = Directory('build/manual-selection-qa');
    const regression = bool.fromEnvironment('MANUAL_CAPTURE_REGRESSION');
    final sourceDirectory = regression ? 'build/processing-qa' : directory.path;
    final name = regression ? 'stage4-preview.pdf' : 'stage5-native-0.pdf';
    final prefix = regression ? 'regression' : 'processing';
    final png = File('$sourceDirectory/fixture-first-page.png').readAsBytesSync();
    final source = FakePdfDocument(name: name, bytes:
      File('$sourceDirectory/$name').readAsBytesSync());
    final pdf = SelectedPdf(name: source.name, size: source.bytes.length, content: source);
    final area = PdfAreaSelectionController();
    final preview = FakePdfPreviewService(onRender: (_, _) async => PdfPagePreview(
      bytes: png, width: 576, height: 1024, pageCount: regression ? 2 : 1));
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(key: key, child: MaterialApp(
      debugShowCheckedModeBanner: false, theme: AppTheme.dark,
      home: PdfProcessingScreen(selectedPdf: pdf, previewService: preview, areaSelectionController: area))));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      for (final asset in ['navy_ellipse.png','teal_ellipse.png','file_icon.png']) {
        await precacheImage(AssetImage('assets/images/$asset'), key.currentContext!);
      }
      await precacheImage(MemoryImage(png), key.currentContext!);
    });
    await tester.pumpAndSettle();
    Future<void> capture(String name) => tester.runAsync(() async {
      final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('${directory.path}/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    await capture('$prefix-initial-390x844');
    final geometry = <String,Object>{};
    for (final entry in {'header': find.byType(HomeHeader),
      'heading': find.text('Processing Your PDF'),
      'track': find.byKey(const ValueKey('processing-not-started-track')),
      'manual': find.text('Manual Watermark Selection'), 'controls': find.byType(PdfSelectionControls),
      'card': find.byType(PdfDocumentPreviewCard),
      'page': find.byKey(const ValueKey('pdf-page-gesture-surface')),
      'button': find.widgetWithText(FilledButton, 'Apply Selection')}.entries) {
      final r = tester.getRect(entry.value);
      geometry[entry.key] = {'x':r.left,'y':r.top,'width':r.width,'height':r.height};
    }
    final page = tester.getRect(find.byKey(const ValueKey('pdf-page-gesture-surface')));
    final gesture = await tester.startGesture(page.topLeft + Offset(page.width*.1, page.height*.3));
    await gesture.moveTo(page.topLeft + Offset(page.width*.5, page.height*.5));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(area.draft, isNotNull);
    await capture('$prefix-selected-390x844');
    final region = area.draft!.rect;
    geometry['normalizedSelection'] = [region.left,region.top,region.right,region.bottom];
    await tester.runAsync(() async => File('${directory.path}/$prefix-geometry.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert(geometry)));
    expect(tester.takeException(), isNull);
  });
}

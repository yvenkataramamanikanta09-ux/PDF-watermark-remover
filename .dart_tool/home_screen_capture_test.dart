import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf_watermark_remover/main.dart';
import 'package:pdf_watermark_remover/widgets/home_header.dart';
import 'package:pdf_watermark_remover/widgets/pdf_preview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final loader = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter-Variable.ttf'));
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  testWidgets('Capture the Home Screen with the bundled Inter font', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final captureKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(key: captureKey, child: const MyApp()),
    );
    await tester.runAsync(() async {
      for (final asset in [
        'assets/images/navy_ellipse.png',
        'assets/images/teal_ellipse.png',
        'assets/images/file_icon.png',
      ]) {
        await precacheImage(AssetImage(asset), captureKey.currentContext!);
      }
    });
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final geometry = <String, Object>{};
    for (final entry in {
      'header': find.byType(HomeHeader),
      'title': find.text('PDF Watermark Remover'),
      'preview': find.byType(PdfPreview),
      'heading': find.text('Remove Watermarks from Your PDF'),
      'description': find.text(
        'Upload your PDF to remove supported watermarks quickly and securely.',
      ),
      'button': find.widgetWithText(FilledButton, 'Upload PDF'),
    }.entries) {
      final rect = tester.getRect(entry.value);
      geometry[entry.key] = {
        'x': rect.left,
        'y': rect.top,
        'width': rect.width,
        'height': rect.height,
      };
    }

    await tester.runAsync(() async {
      const name = String.fromEnvironment(
        'HOME_CAPTURE_NAME',
        defaultValue: 'before',
      );
      final directory = Directory('build/home-screen-qa')..createSync(recursive: true);
      final boundary = captureKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final capture = await boundary.toImage(pixelRatio: 1);
      final data = await capture.toByteData(format: ui.ImageByteFormat.png);
      await File('${directory.path}/$name.png').writeAsBytes(
        data!.buffer.asUint8List(),
      );
      await File('${directory.path}/$name.json').writeAsString(
        const JsonEncoder.withIndent('  ').convert(geometry),
      );
      capture.dispose();
    });
  });
}

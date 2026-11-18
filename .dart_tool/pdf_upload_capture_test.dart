import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf_watermark_remover/main.dart';
import 'package:pdf_watermark_remover/widgets/home_header.dart';
import 'package:pdf_watermark_remover/widgets/pdf_upload_card.dart';

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

  testWidgets('Capture PDF Upload with the app font and assets', (tester) async {
    const width = int.fromEnvironment('UPLOAD_CAPTURE_WIDTH', defaultValue: 390);
    const height = int.fromEnvironment('UPLOAD_CAPTURE_HEIGHT', defaultValue: 844);
    const textScale = String.fromEnvironment('UPLOAD_CAPTURE_SCALE', defaultValue: '1');
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width.toDouble(), height.toDouble());
    tester.platformDispatcher.textScaleFactorTestValue = double.parse(textScale);
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final captureKey = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(key: captureKey, child: const MyApp()));
    await tester.pumpAndSettle();
    final upload = find.widgetWithText(FilledButton, 'Upload PDF');
    await tester.ensureVisible(upload);
    await tester.pumpAndSettle();
    await tester.tap(upload);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      for (final asset in [
        'navy_ellipse.png', 'teal_ellipse.png', 'file_icon.png', 'upload_cloud.png',
      ]) {
        await precacheImage(AssetImage('assets/images/$asset'), captureKey.currentContext!);
      }
    });
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final geometry = <String, Object>{};
    for (final entry in {
      'header': find.byType(HomeHeader),
      'heading': find.text('Upload Your PDF'),
      'card': find.byType(PdfUploadCard),
      'prompt': find.text('Select a PDF file to upload'),
      'description': find.text('Choose a PDF from your device.'),
      'supported': find.text('Supported format: PDF only'),
      'button': find.widgetWithText(FilledButton, 'Choose PDF'),
    }.entries) {
      final rect = tester.getRect(entry.value);
      geometry[entry.key] = {
        'x': rect.left, 'y': rect.top, 'width': rect.width, 'height': rect.height,
      };
    }
    await tester.runAsync(() async {
      const name = String.fromEnvironment('UPLOAD_CAPTURE_NAME', defaultValue: 'upload-first');
      final directory = Directory('build/upload-screen-qa')..createSync(recursive: true);
      final boundary = captureKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final capture = await boundary.toImage(pixelRatio: 1);
      final data = await capture.toByteData(format: ui.ImageByteFormat.png);
      await File('${directory.path}/$name.png').writeAsBytes(data!.buffer.asUint8List());
      await File('${directory.path}/$name.json').writeAsString(
        const JsonEncoder.withIndent('  ').convert(geometry),
      );
      capture.dispose();
    });
  });
}

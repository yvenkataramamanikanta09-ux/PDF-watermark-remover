import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:pdf_watermark_remover/main.dart';
import 'package:pdf_watermark_remover/screens/pdf_upload_screen.dart';
import 'package:pdf_watermark_remover/widgets/home_header.dart';
import 'package:pdf_watermark_remover/widgets/pdf_preview.dart';

void main() {
  setUpAll(() async {
    // Test typography with the font used by the app rather than Flutter's Ahem.
    final loader = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter-Variable.ttf'));
    await loader.load();
  });

  void setDisplay(
    WidgetTester tester,
    Size size, {
    FakeViewPadding padding = FakeViewPadding.zero,
    double textScale = 1,
  }) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.view.padding = padding;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  testWidgets('Home replaces the counter with the requested content', (
    tester,
  ) async {
    setDisplay(tester, const Size(390, 844));
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('PDF Watermark Remover'), findsOneWidget);
    expect(find.text('Remove Watermarks from Your PDF'), findsOneWidget);
    expect(
      find.text(
        'Upload your PDF to remove supported watermarks quickly and securely.',
      ),
      findsOneWidget,
    );
    expect(find.text('SAMPLE'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Upload PDF'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Upload opens PDF Upload without opening a processing flow', (
    tester,
  ) async {
    setDisplay(tester, const Size(390, 844));
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Upload PDF'));
    await tester.pumpAndSettle();

    expect(find.byType(PdfUploadScreen), findsOneWidget);
    expect(find.text('Choose PDF'), findsOneWidget);
    expect(find.byType(PdfPreview), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Reference layout fits without scrolling or wrapping the title', (
    tester,
  ) async {
    setDisplay(tester, const Size(390, 844));
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    final title = tester.renderObject<RenderParagraph>(
      find.text('PDF Watermark Remover'),
    );
    final titlePainter = TextPainter(
      text: title.text,
      textDirection: title.textDirection,
      textScaler: title.textScaler,
    )..layout(maxWidth: title.size.width);
    expect(titlePainter.computeLineMetrics(), hasLength(1));
    titlePainter.dispose();

    final preview = tester.getRect(find.byType(PdfPreview));
    expect(preview.size, const Size(342, 340));
    expect(preview.top, closeTo(195, 1));

    final button = tester.getRect(
      find.widgetWithText(FilledButton, 'Upload PDF'),
    );
    expect(button.top, closeTo(746, 1));
    expect(button.bottom, closeTo(802, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Three-dot menu opens the About dialog', (tester) async {
    setDisplay(tester, const Size(390, 844));
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('About this app'));
    await tester.pumpAndSettle();

    expect(find.byType(AboutDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(600, 960),
    const Size(844, 390),
  ]) {
    testWidgets('Home stays usable at $size', (tester) async {
      setDisplay(tester, size);
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final button = find.widgetWithText(FilledButton, 'Upload PDF');
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      expect(tester.getRect(button).bottom, lessThanOrEqualTo(size.height));
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.byType(PdfUploadScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Header and upload button respect Android safe areas', (
    tester,
  ) async {
    setDisplay(
      tester,
      const Size(390, 844),
      padding: const FakeViewPadding(top: 44, bottom: 34),
    );
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(
      tester.getRect(find.byType(HomeHeader)).top,
      greaterThanOrEqualTo(44),
    );
    final button = find.widgetWithText(FilledButton, 'Upload PDF');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    expect(tester.getRect(button).bottom, lessThanOrEqualTo(844 - 34));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Landscape content stays inside side cutouts and system bars', (
    tester,
  ) async {
    setDisplay(
      tester,
      const Size(844, 390),
      padding: const FakeViewPadding(left: 44, top: 24, right: 24, bottom: 24),
    );
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    final header = tester.getRect(find.byType(HomeHeader));
    expect(header.left, greaterThanOrEqualTo(44));
    expect(header.right, lessThanOrEqualTo(844 - 24));
    expect(header.top, greaterThanOrEqualTo(24));

    final button = find.widgetWithText(FilledButton, 'Upload PDF');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    final buttonRect = tester.getRect(button);
    expect(buttonRect.left, greaterThanOrEqualTo(44));
    expect(buttonRect.right, lessThanOrEqualTo(844 - 24));
    expect(buttonRect.bottom, lessThanOrEqualTo(390 - 24));
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byType(PdfUploadScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Large text remains readable and the button stays reachable', (
    tester,
  ) async {
    setDisplay(tester, const Size(320, 568), textScale: 2);
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final button = find.widgetWithText(FilledButton, 'Upload PDF');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byType(PdfUploadScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

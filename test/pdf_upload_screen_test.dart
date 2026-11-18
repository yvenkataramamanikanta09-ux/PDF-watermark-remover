import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:pdf_watermark_remover/main.dart';
import 'package:pdf_watermark_remover/models/selected_pdf.dart';
import 'package:pdf_watermark_remover/services/pdf_selection_service.dart';
import 'package:pdf_watermark_remover/screens/home_screen.dart';
import 'package:pdf_watermark_remover/screens/pdf_upload_screen.dart';
import 'package:pdf_watermark_remover/screens/pdf_processing_screen.dart';
import 'package:pdf_watermark_remover/widgets/home_header.dart';
import 'package:pdf_watermark_remover/widgets/pdf_upload_card.dart';

import 'fakes/pdf_selection_fakes.dart';
import 'fakes/pdf_preview_fakes.dart';

void main() {
  setUpAll(() async {
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

  Future<void> openUpload(
    WidgetTester tester, {
    PdfSelectionService? selectionService,
  }) async {
    await tester.pumpWidget(
      MyApp(
        pdfSelectionService: selectionService,
        pdfPreviewService: FakePdfPreviewService(),
      ),
    );
    await tester.pumpAndSettle();
    final upload = find.widgetWithText(FilledButton, 'Upload PDF');
    await tester.ensureVisible(upload);
    await tester.pumpAndSettle();
    await tester.tap(upload);
    await tester.pumpAndSettle();
  }

  Future<void> choosePdf(WidgetTester tester) async {
    // Allow asynchronous stream completion outside the fake widget-test clock.
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Choose PDF'));
      await Future<void>(() {});
    });
    await tester.pumpAndSettle();
  }

  testWidgets('PDF Upload shows the approved copy and reference geometry', (
    tester,
  ) async {
    setDisplay(tester, const Size(390, 844));
    await openUpload(tester);

    expect(find.text('PDF Watermark Remover'), findsOneWidget);
    expect(find.text('Upload Your PDF'), findsOneWidget);
    expect(find.text('Select a PDF file to upload'), findsOneWidget);
    expect(find.text('Choose a PDF from your device.'), findsOneWidget);
    expect(find.text('Supported format: PDF only'), findsOneWidget);
    final screenContext = tester.element(find.byType(PdfUploadScreen));
    expect(
      ModalRoute.of(screenContext)!.settings.name,
      PdfUploadScreen.routeName,
    );

    final header = tester.getRect(find.byType(HomeHeader));
    expect(header, const Rect.fromLTWH(24, 40, 340, 76));
    final card = tester.getRect(find.byType(PdfUploadCard));
    expect(card, const Rect.fromLTWH(24, 275, 342, 315));
    final choose = tester.getRect(
      find.widgetWithText(FilledButton, 'Choose PDF'),
    );
    expect(choose, const Rect.fromLTWH(24, 746, 342, 56));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Android back restores the Home Screen', (tester) async {
    setDisplay(tester, const Size(390, 844));
    await openUpload(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(PdfUploadScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Remove Watermarks from Your PDF'), findsOneWidget);
    expect(find.text('Upload PDF'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Header menu returns to Home without changing the closed design',
    (tester) async {
      setDisplay(tester, const Size(390, 844));
      await openUpload(tester);
      expect(find.text('Back to Home'), findsNothing);

      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back to Home'));
      await tester.pumpAndSettle();

      expect(find.byType(PdfUploadScreen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Returning to Home preserves its scroll position', (
    tester,
  ) async {
    setDisplay(tester, const Size(320, 568));
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    final upload = find.widgetWithText(FilledButton, 'Upload PDF');
    await tester.ensureVisible(upload);
    await tester.pumpAndSettle();
    final homeScroll = tester.state<ScrollableState>(find.byType(Scrollable));
    final offset = homeScroll.position.pixels;
    expect(offset, greaterThan(0));

    await tester.tap(upload);
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(homeScroll.position.pixels, offset);
    expect(upload.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Choose PDF confirms selection and opens PDF Processing', (
    tester,
  ) async {
    setDisplay(tester, const Size(390, 844));
    final document = FakePdfDocument();
    final service = PdfSelectionService(
      picker: FakePdfDocumentPicker(result: document),
    );
    await openUpload(tester, selectionService: service);
    await choosePdf(tester);
    expect(
      find.text('Selected sample.pdf (${document.bytes.length} B).'),
      findsOneWidget,
    );
    expect(service.selectedPdf!.content, same(document));
    expect(find.byType(PdfProcessingScreen), findsOneWidget);
    expect(
      tester
          .widget<PdfProcessingScreen>(find.byType(PdfProcessingScreen))
          .selectedPdf,
      same(service.selectedPdf),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Canceling Choose PDF leaves the screen unchanged without errors',
    (tester) async {
      setDisplay(tester, const Size(390, 844));
      final picker = FakePdfDocumentPicker();
      await openUpload(
        tester,
        selectionService: PdfSelectionService(picker: picker),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Choose PDF'));
      await tester.pumpAndSettle();
      expect(picker.calls, 1);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(PdfUploadScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final failure in [
    (FakePdfDocument(name: 'notes.txt'), PdfSelectionFailure.invalidExtension),
    (FakePdfDocument(bytes: []), PdfSelectionFailure.emptyFile),
    (
      FakePdfDocument(bytes: 'not a real PDF'.codeUnits),
      PdfSelectionFailure.invalidHeader,
    ),
    (
      FakePdfDocument(readError: StateError('provider failure')),
      PdfSelectionFailure.unreadableFile,
    ),
  ]) {
    testWidgets('Shows a friendly ${failure.$2.name} validation message', (
      tester,
    ) async {
      setDisplay(tester, const Size(390, 844));
      final service = PdfSelectionService(
        picker: FakePdfDocumentPicker(result: failure.$1),
      );
      await openUpload(tester, selectionService: service);
      await choosePdf(tester);
      expect(
        find.text(PdfSelectionException(failure.$2).message),
        findsOneWidget,
      );
      expect(find.byType(PdfUploadScreen), findsOneWidget);
      expect(service.selectedPdf, isNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Repeated taps do not open overlapping pickers', (tester) async {
    setDisplay(tester, const Size(390, 844));
    final pending = Completer<PdfDocument?>();
    final picker = FakePdfDocumentPicker(onPick: () => pending.future);
    await openUpload(
      tester,
      selectionService: PdfSelectionService(picker: picker),
    );
    final choose = find.widgetWithText(FilledButton, 'Choose PDF');
    await tester.tap(choose);
    await tester.tap(choose);
    await tester.pump();
    expect(picker.calls, 1);
    pending.complete(null);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Late picker results are safe after navigating back', (
    tester,
  ) async {
    setDisplay(tester, const Size(390, 844));
    final pending = Completer<PdfDocument?>();
    final service = PdfSelectionService(
      picker: FakePdfDocumentPicker(onPick: () => pending.future),
    );
    await openUpload(tester, selectionService: service);
    await choosePdf(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      pending.complete(FakePdfDocument());
      await Future<void>(() {});
    });
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(service.selectedPdf, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Selected metadata survives returning Home and reopening Upload',
    (tester) async {
      setDisplay(tester, const Size(390, 844));
      final document = FakePdfDocument();
      final service = PdfSelectionService(
        picker: FakePdfDocumentPicker(result: document),
      );
      await openUpload(tester, selectionService: service);
      await choosePdf(tester);
      final selected = service.selectedPdf;
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(PdfUploadScreen), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Upload PDF'));
      await tester.pumpAndSettle();
      expect(service.selectedPdf, same(selected));
      expect(service.selectedPdf!.name, document.name);
      expect(service.selectedPdf!.size, document.bytes.length);
      expect(service.selectedPdf!.content.uri, document.uri);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Shared About menu works on PDF Upload', (tester) async {
    setDisplay(tester, const Size(390, 844));
    await openUpload(tester);
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('About this app'));
    await tester.pumpAndSettle();

    expect(find.byType(AboutDialog), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(PdfUploadScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(320, 568),
    const Size(360, 640),
    const Size(390, 844),
    const Size(600, 960),
    const Size(844, 390),
  ]) {
    testWidgets('Choose PDF stays visible while content scrolls at $size', (
      tester,
    ) async {
      setDisplay(tester, size);
      await openUpload(tester);
      final choose = find.widgetWithText(FilledButton, 'Choose PDF');
      final beforeScroll = tester.getRect(choose);
      expect(choose.hitTestable(), findsOneWidget);
      expect(beforeScroll.bottom, lessThanOrEqualTo(size.height));

      await tester.ensureVisible(find.text('Supported format: PDF only'));
      await tester.pumpAndSettle();
      expect(tester.getRect(choose), beforeScroll);
      final supported = tester.getRect(find.text('Supported format: PDF only'));
      expect(supported.bottom, lessThanOrEqualTo(beforeScroll.top));
      expect(tester.takeException(), isNull);
    });
  }

  for (final landscape in [false, true]) {
    testWidgets(
      'PDF Upload respects ${landscape ? 'landscape' : 'portrait'} insets',
      (tester) async {
        final size = landscape ? const Size(844, 390) : const Size(390, 844);
        final padding = landscape
            ? const FakeViewPadding(left: 44, top: 24, right: 24, bottom: 24)
            : const FakeViewPadding(top: 44, bottom: 34);
        setDisplay(tester, size, padding: padding);
        await openUpload(tester);

        final header = tester.getRect(find.byType(HomeHeader));
        final choose = tester.getRect(
          find.widgetWithText(FilledButton, 'Choose PDF'),
        );
        expect(header.top, greaterThanOrEqualTo(padding.top));
        expect(header.left, greaterThanOrEqualTo(padding.left));
        expect(header.right, lessThanOrEqualTo(size.width - padding.right));
        expect(choose.left, greaterThanOrEqualTo(padding.left));
        expect(choose.right, lessThanOrEqualTo(size.width - padding.right));
        expect(choose.bottom, lessThanOrEqualTo(size.height - padding.bottom));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Large text can scroll and Choose PDF stays visible', (
    tester,
  ) async {
    setDisplay(tester, const Size(320, 568), textScale: 2);
    await openUpload(tester);
    final choose = find.widgetWithText(FilledButton, 'Choose PDF');
    final buttonRect = tester.getRect(choose);
    expect(choose.hitTestable(), findsOneWidget);
    expect(buttonRect.bottom, lessThanOrEqualTo(568));

    await tester.ensureVisible(find.text('Supported format: PDF only'));
    await tester.pumpAndSettle();
    expect(tester.getRect(choose), buttonRect);
    expect(tester.takeException(), isNull);
  });
}

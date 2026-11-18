import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf_watermark_remover/main.dart';
import 'package:pdf_watermark_remover/models/pdf_page_preview.dart';
import 'package:pdf_watermark_remover/models/selected_pdf.dart';
import 'package:pdf_watermark_remover/screens/pdf_processing_screen.dart';
import 'package:pdf_watermark_remover/screens/pdf_upload_screen.dart';
import 'package:pdf_watermark_remover/services/pdf_preview_service.dart';
import 'package:pdf_watermark_remover/services/pdf_selection_service.dart';
import 'package:pdf_watermark_remover/theme/app_theme.dart';
import 'package:pdf_watermark_remover/widgets/home_header.dart';
import 'package:pdf_watermark_remover/widgets/pdf_document_preview_card.dart';

import 'fakes/pdf_preview_fakes.dart';
import 'fakes/pdf_selection_fakes.dart';

void main() {
  setUpAll(() async {
    final loader = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter-Variable.ttf'));
    await loader.load();
  });

  SelectedPdf selected({
    String name = 'quarterly-report.pdf',
    int size = 2048,
  }) => SelectedPdf(
    name: name,
    size: size,
    content: FakePdfDocument(name: name),
  );

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

  Future<void> openProcessing(
    WidgetTester tester, {
    SelectedPdf? pdf,
    FakePdfPreviewService? service,
    Size size = const Size(390, 844),
    FakeViewPadding padding = FakeViewPadding.zero,
    double textScale = 1,
  }) async {
    setDisplay(tester, size, padding: padding, textScale: textScale);
    final document = pdf ?? selected();
    final previewService = service ?? FakePdfPreviewService();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    settings: const RouteSettings(
                      name: PdfProcessingScreen.routeName,
                    ),
                    builder: (context) => PdfProcessingScreen(
                      selectedPdf: document,
                      previewService: previewService,
                    ),
                  ),
                ),
                child: const Text('Open document'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open document'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Successful selection navigates once with the same selected model',
    (tester) async {
      setDisplay(tester, const Size(390, 844));
      final source = FakePdfDocument(name: 'actual-selection.pdf');
      final picker = FakePdfDocumentPicker(result: source);
      final selection = PdfSelectionService(picker: picker);
      final preview = FakePdfPreviewService();
      await tester.pumpWidget(
        MyApp(pdfSelectionService: selection, pdfPreviewService: preview),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Upload PDF'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Choose PDF'));
        await Future<void>(() {});
      });
      await tester.pumpAndSettle();
      expect(find.byType(PdfProcessingScreen), findsOneWidget);
      expect(picker.calls, 1);
      expect(preview.documents.single, same(selection.selectedPdf));
      expect(preview.documents.single.content, same(source));
      expect(find.text('Document: actual-selection.pdf'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(PdfUploadScreen), findsOneWidget);
      expect(selection.selectedPdf!.content, same(source));
      expect(picker.calls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Shows actual filename, byte-size metadata, page count and preview bytes',
    (tester) async {
      final document = selected();
      final preview = FakePdfPreviewService();
      await openProcessing(tester, pdf: document, service: preview);
      expect(find.text('Document: quarterly-report.pdf'), findsOneWidget);
      expect(find.text('2.0 KB • 2 pages'), findsOneWidget);
      expect(preview.documents.single, same(document));
      final image = tester.widget<Image>(
        find.byWidgetPredicate(
          (widget) =>
              widget is Image &&
              widget.semanticLabel == 'First page of quarterly-report.pdf',
        ),
      );
      expect((image.image as MemoryImage).bytes, testPagePreview().bytes);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Uses singular metadata for one page', (tester) async {
    await openProcessing(
      tester,
      service: FakePdfPreviewService(
        onRender: (pdf, token) async => testPagePreview(pageCount: 1),
      ),
    );
    expect(find.text('2.0 KB • 1 page'), findsOneWidget);
  });

  testWidgets('Reference geometry matches the approved processing screen', (
    tester,
  ) async {
    await openProcessing(tester);
    expect(
      tester.getRect(find.byType(HomeHeader)),
      const Rect.fromLTWH(24, 40, 340, 76),
    );
    expect(
      tester.getRect(
        find.byKey(const ValueKey('processing-not-started-track')),
      ),
      const Rect.fromLTWH(42, 300, 306, 10),
    );
    expect(
      tester.getRect(find.byType(PdfDocumentPreviewCard)),
      const Rect.fromLTWH(24, 460, 342, 250),
    );
    expect(
      tester.getRect(find.widgetWithText(FilledButton, 'Apply Selection')),
      const Rect.fromLTWH(24, 746, 342, 56),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Processing remains not started and Apply Selection needs a region',
    (tester) async {
      final preview = FakePdfPreviewService();
      await openProcessing(tester, service: preview);
      expect(find.text('Manual Watermark Selection'), findsOneWidget);
      expect(find.text('Select'), findsOneWidget);
      expect(find.text('View'), findsOneWidget);
      expect(find.text('Clear'), findsOneWidget);
      final action = find.widgetWithText(FilledButton, 'Apply Selection');
      expect(tester.widget<FilledButton>(action).onPressed, isNull);
      await tester.tap(action);
      await tester.pump(const Duration(minutes: 1));
      await tester.pumpAndSettle();
      expect(find.text('Not started — processing unavailable'), findsOneWidget);
      expect(find.textContaining('55%'), findsNothing);
      expect(find.text('Processing Completed'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(preview.calls, 1);
      expect(tester.widget<FilledButton>(action).onPressed, isNull);
    },
  );

  for (final failure in PdfPreviewFailure.values) {
    testWidgets('Shows a clear ${failure.name} preview error', (tester) async {
      await openProcessing(
        tester,
        service: FakePdfPreviewService(error: PdfPreviewException(failure)),
      );
      expect(find.text(PdfPreviewException(failure).message), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Apply Selection'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Back to Upload'));
      await tester.pumpAndSettle();
      expect(find.text('Open document'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Unexpected preview failures do not expose exception details', (
    tester,
  ) async {
    await openProcessing(
      tester,
      service: FakePdfPreviewService(error: StateError('private path details')),
    );
    expect(
      find.text(
        const PdfPreviewException(PdfPreviewFailure.renderFailed).message,
      ),
      findsOneWidget,
    );
    expect(find.textContaining('private path'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'A failed preview can be retried without picking another document',
    (tester) async {
      final preview = FakePdfPreviewService(
        error: const PdfPreviewException(PdfPreviewFailure.renderFailed),
      );
      final pdf = selected();
      await openProcessing(tester, pdf: pdf, service: preview);
      preview.error = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(preview.calls, 2);
      expect(
        preview.documents.every((document) => identical(document, pdf)),
        isTrue,
      );
      expect(find.text('2.0 KB • 2 pages'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'System back during loading cancels and ignores late results safely',
    (tester) async {
      final pending = Completer<PdfPagePreview>();
      final preview = FakePdfPreviewService(
        onRender: (pdf, token) => pending.future,
      );
      await openProcessing(tester, service: preview);
      expect(find.text('Loading first page…'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(preview.cancellations.single.isCancelled, isTrue);
      pending.complete(testPagePreview());
      await tester.pumpAndSettle();
      expect(find.text('Open document'), findsOneWidget);
      expect(find.byType(PdfProcessingScreen), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Header back returns to Upload without an extra picker call', (
    tester,
  ) async {
    await openProcessing(tester);
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back to Upload'));
    await tester.pumpAndSettle();
    expect(find.text('Open document'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Backgrounded rendering is canceled and resumes after cleanup', (
    tester,
  ) async {
    final pending = Completer<PdfPagePreview>();
    final preview = FakePdfPreviewService();
    preview.onRender = (pdf, token) =>
        preview.calls == 1 ? pending.future : Future.value(testPagePreview());
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    await openProcessing(tester, service: preview);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(preview.cancellations.first.isCancelled, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(
      preview.calls,
      1,
      reason: 'The interrupted render must finish before another starts.',
    );
    pending.complete(testPagePreview());
    await tester.pumpAndSettle();
    expect(preview.calls, 2);
    expect(find.text('2.0 KB • 2 pages'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'A ready preview survives background and resume without reopening',
    (tester) async {
      final preview = FakePdfPreviewService();
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      await openProcessing(tester, service: preview);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(preview.calls, 1);
      expect(find.text('2.0 KB • 2 pages'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [
    const Size(320, 568),
    const Size(600, 960),
    const Size(844, 390),
  ]) {
    testWidgets(
      'Processing scrolls safely and keeps disabled action visible at $size',
      (tester) async {
        await openProcessing(tester, size: size);
        final action = find.widgetWithText(FilledButton, 'Apply Selection');
        expect(tester.getRect(action).bottom, lessThanOrEqualTo(size.height));
        final before = tester.getRect(action);
        await tester.ensureVisible(find.byType(PdfDocumentPreviewCard));
        await tester.pumpAndSettle();
        expect(tester.getRect(action), before);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Large text, long names, and preview errors remain reachable', (
    tester,
  ) async {
    final document = selected(
      name: '${List.filled(12, 'long-document-name').join('-')}.pdf',
    );
    await openProcessing(
      tester,
      pdf: document,
      service: FakePdfPreviewService(
        error: const PdfPreviewException(PdfPreviewFailure.unsupportedContent),
      ),
      size: const Size(320, 568),
      textScale: 2,
    );
    expect(find.text('Document: ${document.name}'), findsOneWidget);
    await tester.ensureVisible(find.text('Back to Upload'));
    await tester.pumpAndSettle();
    expect(
      tester
          .getRect(find.widgetWithText(FilledButton, 'Apply Selection'))
          .bottom,
      lessThanOrEqualTo(568),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Processing respects landscape cutouts and navigation insets', (
    tester,
  ) async {
    await openProcessing(
      tester,
      size: const Size(844, 390),
      padding: const FakeViewPadding(left: 44, top: 24, right: 24, bottom: 24),
    );
    final header = tester.getRect(find.byType(HomeHeader));
    final action = tester.getRect(
      find.widgetWithText(FilledButton, 'Apply Selection'),
    );
    expect(header.left, greaterThanOrEqualTo(44));
    expect(header.right, lessThanOrEqualTo(820));
    expect(header.top, greaterThanOrEqualTo(24));
    expect(action.bottom, lessThanOrEqualTo(366));
    expect(tester.takeException(), isNull);
  });
}

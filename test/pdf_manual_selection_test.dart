import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf_watermark_remover/main.dart';
import 'package:pdf_watermark_remover/models/pdf_page_preview.dart';
import 'package:pdf_watermark_remover/models/selected_pdf.dart';
import 'package:pdf_watermark_remover/screens/pdf_processing_screen.dart';
import 'package:pdf_watermark_remover/screens/pdf_upload_screen.dart';
import 'package:pdf_watermark_remover/services/pdf_area_selection_controller.dart';
import 'package:pdf_watermark_remover/services/pdf_preview_service.dart';
import 'package:pdf_watermark_remover/services/pdf_selection_service.dart';
import 'package:pdf_watermark_remover/theme/app_theme.dart';
import 'package:pdf_watermark_remover/widgets/pdf_page_selection_view.dart';

import 'fakes/pdf_preview_fakes.dart';
import 'fakes/pdf_selection_fakes.dart';

void main() {
  setUpAll(() async {
    final loader = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter-Variable.ttf'));
    await loader.load();
  });
  late PdfAreaSelectionController area;
  late SelectedPdf document;
  setUp(() {
    area = PdfAreaSelectionController();
    final source = FakePdfDocument();
    document = SelectedPdf(
      name: source.name,
      size: source.bytes.length,
      content: source,
    );
  });

  void setDisplay(WidgetTester tester, Size size, {double scale = 1}) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double scale = 1,
    double transformScale = 1,
    FakePdfPreviewService? preview,
  }) async {
    setDisplay(tester, size, scale: scale);
    final service = preview ?? FakePdfPreviewService();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => Transform.scale(
                    scale: transformScale,
                    alignment: Alignment.topLeft,
                    child: PdfProcessingScreen(
                      selectedPdf: document,
                      previewService: service,
                      areaSelectionController: area,
                    ),
                  ),
                ),
              ),
              child: const Text('Open document'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open document'));
    await tester.pumpAndSettle();
  }

  Finder getPage() => find.byKey(const ValueKey('pdf-page-gesture-surface'));
  Finder apply() => find.widgetWithText(FilledButton, 'Apply Selection');
  Offset at(Rect page, double x, double y) =>
      page.topLeft + Offset(page.width * x, page.height * y);
  Future<void> draw(
    WidgetTester tester, {
    Offset start = const Offset(.2, .3),
    Offset end = const Offset(.8, .7),
  }) async {
    await tester.ensureVisible(getPage());
    await tester.pumpAndSettle();
    final rect = tester.getRect(getPage());
    final gesture = await tester.startGesture(at(rect, start.dx, start.dy));
    await tester.pump();
    expect(area.canApply, isFalse);
    await gesture.moveTo(at(rect, end.dx, end.dy));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  void matchesRegion(Rect actual, Rect expected) {
    expect(actual.left, closeTo(expected.left, .00001));
    expect(actual.top, closeTo(expected.top, .00001));
    expect(actual.right, closeTo(expected.right, .00001));
    expect(actual.bottom, closeTo(expected.bottom, .00001));
  }

  testWidgets('Page drag creates a bounded pink region and enables Apply', (
    tester,
  ) async {
    await open(tester);
    expect(tester.widget<FilledButton>(apply()).onPressed, isNull);
    await draw(tester);
    matchesRegion(area.draft!.rect, const Rect.fromLTRB(.2, .3, .8, .7));
    final paint = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('pdf-region-outline')),
    );
    matchesRegion(
      (paint.painter! as PdfRegionPainter).region,
      area.draft!.rect,
    );
    expect(tester.widget<FilledButton>(apply()).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Parent scaling is inverted before mapping pointer coordinates', (
    tester,
  ) async {
    await open(tester, transformScale: .8);
    await draw(tester);
    matchesRegion(area.draft!.rect, const Rect.fromLTRB(.2, .3, .8, .7));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Vertical selection drag never scrolls the surrounding screen', (
    tester,
  ) async {
    await open(tester, size: const Size(320, 568));
    await tester.ensureVisible(getPage());
    await tester.pumpAndSettle();
    final scroll = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    final offset = scroll.pixels;
    await draw(tester, start: const Offset(.2, .2), end: const Offset(.7, .9));
    expect(scroll.pixels, offset);
    matchesRegion(area.draft!.rect, const Rect.fromLTRB(.2, .2, .7, .9));
  });

  testWidgets(
    'View mode lets page drags scroll without selecting or transforming',
    (tester) async {
      await open(tester, size: const Size(320, 568));
      await tester.ensureVisible(find.text('View'));
      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(getPage());
      await tester.pumpAndSettle();
      final scroll = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      final before = scroll.pixels;
      final page = tester.getRect(getPage());
      await tester.dragFrom(at(page, .5, .3), const Offset(0, 90));
      await tester.pumpAndSettle();
      expect(scroll.pixels, lessThan(before));
      expect(area.draft, isNull);
      expect(find.byType(InteractiveViewer), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Dark letterboxing cannot create a page selection', (
    tester,
  ) async {
    await open(tester);
    final viewport = tester.getRect(
      find.byKey(const ValueKey('pdf-selection-viewport')),
    );
    final page = tester.getRect(getPage());
    expect(page.left, greaterThan(viewport.left + 10));
    await tester.dragFrom(
      Offset(viewport.left + 10, page.center.dy),
      const Offset(30, 20),
    );
    await tester.pumpAndSettle();
    expect(area.draft, isNull);
    expect(tester.widget<FilledButton>(apply()).onPressed, isNull);
  });

  testWidgets('Drag leaving the page is clipped to its edges', (tester) async {
    await open(tester);
    await draw(tester, start: const Offset(.2, .3), end: const Offset(2, 1.2));
    matchesRegion(area.draft!.rect, const Rect.fromLTRB(.2, .3, 1, 1));
  });

  testWidgets('Tiny and zero-area gestures are rejected with useful feedback', (
    tester,
  ) async {
    await open(tester);
    await draw(
      tester,
      start: const Offset(.2, .3),
      end: const Offset(.21, .31),
    );
    expect(area.draft, isNull);
    expect(
      find.text('Drag a larger rectangle inside the PDF page.'),
      findsOneWidget,
    );
    await tester.tapAt(tester.getCenter(getPage()));
    await tester.pumpAndSettle();
    expect(area.canApply, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Apply commits only region state and never starts PDF processing',
    (tester) async {
      await open(tester);
      final bytes = List<int>.of((document.content as FakePdfDocument).bytes);
      await draw(tester);
      await tester.runAsync(() async {
        await tester.tap(apply());
        await Future<void>(() {});
      });
      await tester.pumpAndSettle();
      expect(area.committed!.document, same(document));
      expect(area.committed!.pageNumber, 1);
      matchesRegion(
        area.committed!.bounds.rect,
        const Rect.fromLTRB(.2, .3, .8, .7),
      );
      expect(
        find.text('Watermark area selected. PDF unchanged.'),
        findsOneWidget,
      );
      expect(find.text('Not started — processing unavailable'), findsOneWidget);
      expect(find.text('Processing Completed'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect((document.content as FakePdfDocument).bytes, bytes);
      expect(find.byType(PdfProcessingScreen), findsOneWidget);
    },
  );

  testWidgets('A second drag replaces selection; Clear disables Apply', (
    tester,
  ) async {
    await open(tester);
    await draw(tester);
    await draw(tester, start: const Offset(.1, .1), end: const Offset(.6, .5));
    matchesRegion(area.draft!.rect, const Rect.fromLTRB(.1, .1, .6, .5));
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(area.hasRegion, isFalse);
    expect(find.byKey(const ValueKey('pdf-region-outline')), findsNothing);
    expect(tester.widget<FilledButton>(apply()).onPressed, isNull);
  });

  testWidgets(
    'Canceled and invalid replacement drags preserve a valid selection',
    (tester) async {
      await open(tester);
      await draw(tester);
      final saved = area.draft;
      final page = tester.getRect(getPage());
      final gesture = await tester.startGesture(at(page, .1, .1));
      await gesture.moveTo(at(page, .5, .5));
      await tester.pump();
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(area.draft, same(saved));
      await draw(
        tester,
        start: const Offset(.2, .3),
        end: const Offset(.201, .301),
      );
      expect(area.draft, same(saved));
      expect(area.canApply, isTrue);
    },
  );

  testWidgets(
    'Two-finger input cancels creation instead of scaling or saving bad coordinates',
    (tester) async {
      await open(tester);
      final page = tester.getRect(getPage());
      final first = await tester.startGesture(at(page, .2, .2), pointer: 1);
      await first.moveTo(at(page, .8, .6));
      await tester.pump();
      final second = await tester.startGesture(at(page, .5, .5), pointer: 2);
      await tester.pump();
      await first.up();
      await second.up();
      await tester.pumpAndSettle();
      expect(area.draft, isNull);
      expect(area.isDrawing, isFalse);
      await draw(tester);
      expect(area.draft, isNotNull);
    },
  );

  for (final size in [
    const Size(320, 568),
    const Size(600, 960),
    const Size(844, 390),
  ]) {
    testWidgets('Selection maps correctly and footer stays visible at $size', (
      tester,
    ) async {
      await open(tester, size: size);
      await draw(tester);
      matchesRegion(area.draft!.rect, const Rect.fromLTRB(.2, .3, .8, .7));
      expect(tester.getRect(apply()).bottom, lessThanOrEqualTo(size.height));
      expect(tester.widget<FilledButton>(apply()).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'Landscape page has accurate letterboxing and selectable displayed coordinates',
    (tester) async {
      final landscape = PdfPagePreview(
        bytes: base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAMAAAACCAIAAAASFvFNAAAAFElEQVR4nGP8//8/AxgwQSgGBgYANgYDARtTfJEAAAAASUVORK5CYII=',
        ),
        width: 3,
        height: 2,
        pageCount: 1,
      );
      await open(
        tester,
        preview: FakePdfPreviewService(onRender: (_, _) async => landscape),
      );
      final viewport = tester.getRect(
        find.byKey(const ValueKey('pdf-selection-viewport')),
      );
      final page = tester.getRect(getPage());
      expect(page.top, greaterThan(viewport.top));
      await tester.dragFrom(
        Offset(page.center.dx, viewport.top + 2),
        const Offset(10, 3),
      );
      await tester.pumpAndSettle();
      expect(area.draft, isNull);
      await draw(tester);
      matchesRegion(area.draft!.rect, const Rect.fromLTRB(.2, .3, .8, .7));
    },
  );

  testWidgets(
    'Large text keeps controls usable and valid selection reachable',
    (tester) async {
      await open(tester, size: const Size(320, 568), scale: 2);
      await draw(tester);
      await tester.ensureVisible(find.text('Clear'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(area.draft, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Orientation change during a drag cancels rather than remapping its start',
    (tester) async {
      await open(tester);
      final page = tester.getRect(getPage());
      final gesture = await tester.startGesture(at(page, .2, .2));
      await gesture.moveTo(at(page, .7, .7));
      await tester.pump();
      tester.view.physicalSize = const Size(844, 390);
      await tester.pumpAndSettle();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(area.draft, isNull);
      expect(area.isDrawing, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Background cancels an unfinished drag and completed areas survive resume',
    (tester) async {
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      await open(tester);
      await draw(tester);
      final saved = area.draft;
      final page = tester.getRect(getPage());
      final gesture = await tester.startGesture(at(page, .1, .1));
      await gesture.moveTo(at(page, .9, .9));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(area.draft, same(saved));
      expect(area.isDrawing, isFalse);
      expect(tester.widget<FilledButton>(apply()).onPressed, isNotNull);
    },
  );

  testWidgets(
    'Back during dragging preserves committed state for the same document',
    (tester) async {
      await open(tester);
      await draw(tester);
      await tester.runAsync(() => area.apply());
      final saved = area.committed;
      final page = tester.getRect(getPage());
      final gesture = await tester.startGesture(at(page, .1, .1));
      await gesture.moveTo(at(page, .9, .9));
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await gesture.up();
      expect(area.isDrawing, isFalse);
      expect(area.committed, same(saved));
      expect(area.canApply, isFalse);
      await tester.tap(find.text('Open document'));
      await tester.pumpAndSettle();
      expect(area.committed, same(saved));
      expect(tester.widget<FilledButton>(apply()).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Expired reference at Apply clears areas and offers a new selection',
    (tester) async {
      area = PdfAreaSelectionController(verifyAccess: (_) async => false);
      await open(tester);
      await draw(tester);
      await tester.tap(apply());
      await tester.pumpAndSettle();
      expect(area.hasRegion, isFalse);
      expect(
        find.text(
          const PdfPreviewException(PdfPreviewFailure.unreadable).message,
        ),
        findsOneWidget,
      );
      expect(tester.widget<FilledButton>(apply()).onPressed, isNull);
      await tester.tap(find.text('Back to Upload'));
      await tester.pumpAndSettle();
      expect(find.text('Open document'), findsOneWidget);
    },
  );

  testWidgets(
    'A failed re-open clears a committed area and retry starts without stale selection',
    (tester) async {
      final preview = FakePdfPreviewService();
      await open(tester, preview: preview);
      await draw(tester);
      await tester.runAsync(() => area.apply());
      expect(area.committed, isNotNull);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      preview.error = const PdfPreviewException(PdfPreviewFailure.renderFailed);
      await tester.tap(find.text('Open document'));
      await tester.pumpAndSettle();
      expect(area.hasRegion, isFalse);
      preview.error = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(preview.calls, 3);
      expect(area.draft, isNull);
      expect(tester.widget<FilledButton>(apply()).onPressed, isNull);
      expect(
        preview.documents.every((pdf) => identical(pdf, document)),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Lifecycle interruption suppresses a late Apply confirmation', (
    tester,
  ) async {
    final pending = Completer<bool>();
    area = PdfAreaSelectionController(verifyAccess: (_) => pending.future);
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    await open(tester);
    await draw(tester);
    await tester.tap(apply());
    await tester.pump();
    expect(area.isApplying, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    pending.complete(true);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(area.committed, isNull);
    expect(area.draft, isNotNull);
    expect(find.text('Watermark area selected. PDF unchanged.'), findsNothing);
    expect(tester.widget<FilledButton>(apply()).onPressed, isNotNull);
  });

  testWidgets(
    'Choosing a replacement PDF clears the app-owned selection without modifying documents',
    (tester) async {
      setDisplay(tester, const Size(390, 844));
      final first = FakePdfDocument(name: 'same-name.pdf');
      final second = FakePdfDocument(name: 'same-name.pdf');
      final picker = FakePdfDocumentPicker(result: first);
      final selection = PdfSelectionService(picker: picker);
      await tester.pumpWidget(
        MyApp(
          pdfSelectionService: selection,
          pdfPreviewService: FakePdfPreviewService(),
          areaSelectionController: area,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Upload PDF'));
      await tester.pumpAndSettle();
      Future<void> choose() async {
        await tester.runAsync(() async {
          await tester.tap(find.widgetWithText(FilledButton, 'Choose PDF'));
          await Future<void>(() {});
        });
        await tester.pumpAndSettle();
      }

      await choose();
      await draw(tester);
      await tester.runAsync(() async {
        await area.apply();
      });
      await tester.pumpAndSettle();
      final id = area.documentId;
      expect(area.committed, isNotNull);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(PdfUploadScreen), findsOneWidget);
      expect(area.committed, isNotNull);
      picker.result = null;
      await choose();
      expect(find.byType(PdfUploadScreen), findsOneWidget);
      expect(area.documentId, id);
      expect(area.committed, isNotNull);
      picker.result = second;
      await choose();
      expect(find.byType(PdfProcessingScreen), findsOneWidget);
      expect(area.documentId, isNot(id));
      expect(area.document, same(selection.selectedPdf));
      expect(area.document!.content, same(second));
      expect(area.hasRegion, isFalse);
      expect(tester.widget<FilledButton>(apply()).onPressed, isNull);
      expect(picker.calls, 3);
      expect(first.bytes, second.bytes);
    },
  );
}

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf_watermark_remover/main.dart';
import 'package:pdf_watermark_remover/models/job.dart';
import 'package:pdf_watermark_remover/services/app_services.dart';
import 'package:pdf_watermark_remover/services/pdf_engine.dart';
import 'package:pdf_watermark_remover/services/pdf_selection_service.dart';

import 'fakes/engine_fakes.dart';
import 'fakes/pdf_selection_fakes.dart';

void main() {
  late FakeEngine engine;
  late FakeSaver saver;
  late FakePdfDocumentPicker picker;

  setUp(() {
    engine = FakeEngine();
    saver = FakeSaver();
    picker = FakePdfDocumentPicker(result: FakePdfDocument(name: 'report.pdf'));
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MyApp(
        services: AppServices(
          pdfSelection: PdfSelectionService(picker: picker),
          engine: engine,
          saver: saver,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openUpload(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('upload-pdf-button')));
    await tester.pumpAndSettle();
  }

  /// Picking and validating read a real stream, which needs real event-loop turns.
  Future<void> settleSelection(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }

  Future<void> choosePdf(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('choose-pdf-button')));
    await settleSelection(tester);
    await tester.pumpAndSettle();
  }

  Future<void> openProcessing(WidgetTester tester) async {
    await pumpApp(tester);
    await openUpload(tester);
    await choosePdf(tester);
  }

  Future<void> dragArea(WidgetTester tester) async {
    final surface = find.byKey(const ValueKey('pdf-page-gesture-surface'));
    await tester.ensureVisible(surface);
    await tester.pumpAndSettle();
    final box = tester.getRect(surface);
    final gesture = await tester.startGesture(box.topLeft + Offset(box.width * 0.2, box.height * 0.2));
    await gesture.moveTo(box.topLeft + Offset(box.width * 0.5, box.height * 0.4));
    await gesture.moveTo(box.topLeft + Offset(box.width * 0.8, box.height * 0.6));
    await gesture.up();
    await tester.pumpAndSettle();
  }

  Future<void> selectMenu(WidgetTester tester, String item) async {
    await tester.tap(find.byTooltip('More options').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(item).last);
    await tester.pumpAndSettle();
  }

  FilledButton filled(WidgetTester tester, String key) =>
      tester.widget<FilledButton>(find.byKey(ValueKey(key)));

  JobInfo succeeded({String mode = 'area', bool auto = false, int removed = 3, List<int> pages = const [1, 2, 3]}) =>
      job(status: 'succeeded', auto: auto, mode: mode, outcome: 'watermark_removed_successfully',
          removed: removed, pagesChanged: pages);

  testWidgets('home follows the design copy and uses the Material 3 dark theme', (tester) async {
    await pumpApp(tester);
    expect(find.text('PDF Watermark Remover'), findsOneWidget);
    expect(find.text('Remove Watermarks from Your PDF'), findsOneWidget);
    expect(find.text('Upload PDF'), findsOneWidget);
    final theme = Theme.of(tester.element(find.byType(Scaffold).first));
    expect(theme.useMaterial3, isTrue);
    expect(theme.brightness, Brightness.dark);
    expect(theme.colorScheme.primary, const Color(0xFFF4B9BD));
    expect(theme.scaffoldBackgroundColor, const Color(0xFF151515));
  });

  testWidgets('Upload PDF opens the upload screen from the design', (tester) async {
    await pumpApp(tester);
    await openUpload(tester);
    expect(find.text('Upload Your PDF'), findsOneWidget);
    expect(find.text('Select a PDF file to upload'), findsOneWidget);
    expect(find.text('Supported format: PDF only • up to 40 MB'), findsOneWidget);
    expect(find.text('Choose PDF'), findsOneWidget);
    expect(find.byKey(const ValueKey('engine-warning')), findsNothing);
  });

  testWidgets('upload screen warns when the engine cannot start and can retry', (tester) async {
    engine.statusError = const EngineException(EngineFailure.unavailable, 'The PDF engine could not start.');
    await pumpApp(tester);
    await openUpload(tester);
    expect(find.text('PDF engine unavailable'), findsOneWidget);
    expect(find.text('The PDF engine could not start.'), findsOneWidget);
    engine.statusError = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('engine-warning')), findsNothing);
    expect(find.text('Supported format: PDF only • up to 40 MB'), findsOneWidget);
  });

  testWidgets('a PDF over the engine limit is refused before upload', (tester) async {
    engine.maxFileBytes = 10;
    await openProcessing(tester);
    expect(find.textContaining('can process PDFs up to'), findsOneWidget);
    expect(find.text('Upload Your PDF'), findsOneWidget);
    expect(engine.analyzeCalls, 0);
  });

  testWidgets('cancelling the picker stays on the upload screen', (tester) async {
    picker.result = null;
    await openProcessing(tester);
    expect(find.text('Upload Your PDF'), findsOneWidget);
    expect(engine.analyzeCalls, 0);
  });

  testWidgets('processing shows upload progress, then the area flow completes and downloads', (tester) async {
    engine
      ..analyzeGate = Completer<void>()
      ..removal = succeeded();
    await pumpApp(tester);
    await openUpload(tester);
    await tester.tap(find.byKey(const ValueKey('choose-pdf-button')));
    await settleSelection(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Processing Your PDF'), findsOneWidget);
    expect(find.text('Document: report.pdf'), findsOneWidget);
    expect(find.text('50% — Preparing PDF'), findsOneWidget);
    expect(
      tester.widget<LinearProgressIndicator>(find.byKey(const ValueKey('processing-progress'))).value,
      0.5,
    );
    engine.analyzeGate!.complete();
    await tester.pumpAndSettle();

    expect(find.text('Ready — select the watermark area'), findsOneWidget);
    expect(find.text('Manual Watermark Selection'), findsOneWidget);
    expect(find.text('Select the watermark area in the PDF preview.'), findsOneWidget);
    expect(find.text('3 pages'), findsOneWidget);
    expect(find.byKey(const ValueKey('mode-selector')), findsNothing);
    expect(filled(tester, 'apply-selection-button').onPressed, isNull);

    await dragArea(tester);
    expect(filled(tester, 'apply-selection-button').onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('apply-selection-button')));
    await tester.pumpAndSettle();

    expect(engine.removedMode, RemovalMode.area);
    expect(engine.removedAllPages, isTrue);
    final area = engine.removedArea!.rect;
    expect(area.left, closeTo(0.2, 0.02));
    expect(area.top, closeTo(0.2, 0.02));
    expect(area.right, closeTo(0.8, 0.02));
    expect(area.bottom, closeTo(0.6, 0.02));

    expect(find.text('Processing Completed!'), findsOneWidget);
    expect(find.text('Your PDF is ready to download.'), findsOneWidget);
    expect(find.text('report_cleaned.pdf'), findsOneWidget);
    expect(find.text('3 objects removed • 3 pages'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('download-button')));
    await tester.pumpAndSettle();
    expect(saver.fileName, 'report_cleaned.pdf');
    expect(String.fromCharCodes(saver.bytes!), startsWith('%PDF-'));
    expect(find.text('Saved report_cleaned.pdf.'), findsOneWidget);
  });

  testWidgets('detected watermarks offer automatic removal', (tester) async {
    engine
      ..analyzed = job(auto: true)
      ..removal = succeeded(mode: 'auto', auto: true);
    await openProcessing(tester);
    expect(find.text('3 watermarks detected'), findsOneWidget);
    expect(find.text('Detected Watermarks'), findsOneWidget);
    expect(find.text('Remove Detected Watermarks'), findsOneWidget);
    expect(find.byKey(const ValueKey('page-scope-selector')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('apply-selection-button')));
    await tester.pumpAndSettle();
    expect(engine.removedMode, RemovalMode.auto);
    expect(engine.removedArea, isNull);
    expect(find.text('Processing Completed!'), findsOneWidget);
  });

  testWidgets('first-page-only is sent when the switch is turned off', (tester) async {
    engine.removal = succeeded(removed: 1, pages: [1]);
    await openProcessing(tester);
    await dragArea(tester);
    final pageOne = find.text('Page 1 only');
    await tester.ensureVisible(pageOne);
    await tester.pumpAndSettle();
    await tester.tap(pageOne);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('apply-selection-button')));
    await tester.pumpAndSettle();
    expect(engine.removedAllPages, isFalse);
    expect(find.text('1 object removed • 1 page'), findsOneWidget);
  });

  testWidgets('nothing removed opens the error screen; Try Again returns to selection', (tester) async {
    engine.removal = job(status: 'nothing_removed', mode: 'area', outcome: 'no_supported_watermark_detected');
    await openProcessing(tester);
    await dragArea(tester);
    await tester.tap(find.byKey(const ValueKey('apply-selection-button')));
    await tester.pumpAndSettle();
    expect(find.text('Unable to Process PDF'), findsOneWidget);
    expect(find.text('Nothing Was Removed'), findsOneWidget);
    expect(find.text('Error code: CODE'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('try-again-button')));
    await tester.pumpAndSettle();
    expect(find.text('Processing Your PDF'), findsOneWidget);
    expect(filled(tester, 'apply-selection-button').onPressed, isNotNull);
  });

  testWidgets('a failed removal shows the design error card with the engine message', (tester) async {
    engine.removal = job(status: 'failed', mode: 'area', outcome: 'processing_failed',
        message: 'Processing failed. The original file is unchanged.');
    await openProcessing(tester);
    await dragArea(tester);
    await tester.tap(find.byKey(const ValueKey('apply-selection-button')));
    await tester.pumpAndSettle();
    expect(find.text('Watermark Removal Failed'), findsOneWidget);
    expect(find.text('Processing failed. The original file is unchanged.'), findsOneWidget);
    expect(find.text('Try Again'), findsOneWidget);
  });

  testWidgets('a refused upload shows the reason and returns to Upload', (tester) async {
    engine.analyzeError = const EngineException(
      EngineFailure.rejected,
      'This PDF is password protected. Remove the password and try again.',
      code: 'PASSWORD_REQUIRED',
    );
    await openProcessing(tester);
    expect(find.text('Unable to Process PDF'), findsOneWidget);
    expect(find.text('PDF Not Accepted'), findsOneWidget);
    expect(find.textContaining('password protected'), findsOneWidget);
    expect(find.text('Error code: PASSWORD_REQUIRED'), findsOneWidget);
    await tester.tap(find.text('Choose Another PDF'));
    await tester.pumpAndSettle();
    expect(find.text('Upload Your PDF'), findsOneWidget);
    expect(engine.analyzeCalls, 1);
  });

  testWidgets('an unexpected engine failure while checking can be retried', (tester) async {
    engine.analyzeError = const EngineException(
      EngineFailure.failed,
      'The phone ran out of memory while checking this PDF.',
      code: 'MEMORY_LIMIT',
    );
    await openProcessing(tester);
    expect(find.text('Could Not Check the PDF'), findsOneWidget);
    expect(find.text('Error code: MEMORY_LIMIT'), findsOneWidget);
    engine.analyzeError = null;
    await tester.tap(find.byKey(const ValueKey('try-again-button')));
    await tester.pumpAndSettle();
    expect(engine.analyzeCalls, 2);
    expect(find.text('Ready — select the watermark area'), findsOneWidget);
  });

  testWidgets('leaving the processing screen deletes the local job', (tester) async {
    await openProcessing(tester);
    await selectMenu(tester, 'Back to Upload');
    expect(find.text('Upload Your PDF'), findsOneWidget);
    expect(engine.deleted, ['job-1']);
  });

  testWidgets('the result menu allows another area or going home', (tester) async {
    engine.removal = succeeded();
    await openProcessing(tester);
    await dragArea(tester);
    await tester.tap(find.byKey(const ValueKey('apply-selection-button')));
    await tester.pumpAndSettle();
    await selectMenu(tester, 'Select another area');
    expect(find.text('Processing Your PDF'), findsOneWidget);
    expect(engine.deleted, isEmpty);
    await tester.tap(find.byKey(const ValueKey('apply-selection-button')));
    await tester.pumpAndSettle();
    await selectMenu(tester, 'Back to Home');
    expect(find.text('Remove Watermarks from Your PDF'), findsOneWidget);
    expect(engine.deleted, ['job-1']);
  });

  testWidgets('Check PDF engine runs the self test and shows each step', (tester) async {
    await pumpApp(tester);
    await selectMenu(tester, 'Check PDF engine');
    expect(find.text('The PDF engine works'), findsOneWidget);
    expect(find.text('remove watermark'), findsOneWidget);
    expect(find.textContaining('Python 3.13.0 · pypdf 7.1.0 · PDFium 5.15.2'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('engine-check-close')));
    await tester.pumpAndSettle();
    expect(find.text('The PDF engine works'), findsNothing);
  });

  testWidgets('Check PDF engine explains a failure and can retry', (tester) async {
    engine.statusError = const EngineException(
      EngineFailure.unavailable,
      'The PDF engine could not start.',
      code: 'ENGINE_ERROR',
    );
    await pumpApp(tester);
    await selectMenu(tester, 'Check PDF engine');
    expect(find.text('The PDF engine check failed'), findsOneWidget);
    expect(find.textContaining('Error code: ENGINE_ERROR'), findsOneWidget);
    engine.statusError = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('The PDF engine works'), findsOneWidget);
  });

  testWidgets('the home chip opens the what-can-be-removed bottom sheet', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const ValueKey('what-can-be-removed-chip')));
    await tester.pumpAndSettle();
    expect(find.text('What can be removed?'), findsWidgets);
    expect(find.text('Not supported'), findsOneWidget);
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(find.text('Not supported'), findsNothing);
  });

  testWidgets('tapping the upload card also opens the picker', (tester) async {
    await pumpApp(tester);
    await openUpload(tester);
    await tester.tap(find.text('Select a PDF file to upload'));
    await settleSelection(tester);
    await tester.pumpAndSettle();
    expect(picker.calls, 1);
    expect(find.text('Processing Your PDF'), findsOneWidget);
  });

  testWidgets('a user can switch from automatic to marking an area', (tester) async {
    engine
      ..analyzed = job(auto: true)
      ..removal = succeeded(auto: true);
    await openProcessing(tester);
    await tester.tap(find.text('Mark area'));
    await tester.pumpAndSettle();
    expect(find.text('Manual Watermark Selection'), findsOneWidget);
    expect(filled(tester, 'apply-selection-button').onPressed, isNull);
    await dragArea(tester);
    await tester.tap(find.byKey(const ValueKey('apply-selection-button')));
    await tester.pumpAndSettle();
    expect(engine.removedMode, RemovalMode.area);
    expect(engine.removedArea, isNotNull);
  });

  testWidgets('leaving while processing asks for confirmation', (tester) async {
    engine.removeGate = Completer<void>(); // the engine is still working
    await openProcessing(tester);
    await dragArea(tester);
    await tester.tap(find.byKey(const ValueKey('apply-selection-button')));
    await tester.pump();
    // The indeterminate progress bar never settles: advance time explicitly.
    Future<void> settle() async {
      for (var step = 0; step < 6; step++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> backToUpload() async {
      final menu = find.byTooltip('More options').last;
      await tester.ensureVisible(menu); // the drag scrolled the header away
      await settle();
      await tester.tap(menu);
      await settle();
      await tester.tap(find.text('Back to Upload').last);
      await settle();
    }

    await backToUpload();
    expect(find.text('Stop processing?'), findsOneWidget);
    await tester.tap(find.text('Keep waiting'));
    await settle();
    expect(find.text('Stop processing?'), findsNothing);
    expect(find.text('Processing Your PDF'), findsOneWidget);
    await backToUpload();
    await tester.tap(find.byKey(const ValueKey('leave-processing-button')));
    await settle();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Upload Your PDF'), findsOneWidget);
    expect(engine.deleted, ['job-1']);
    engine.removeGate!.complete(); // the abandoned removal finishes harmlessly
    await tester.pumpAndSettle();
  });

  testWidgets('result and error screens offer their secondary actions', (tester) async {
    engine.removal = succeeded();
    await openProcessing(tester);
    await dragArea(tester);
    await tester.tap(find.byKey(const ValueKey('apply-selection-button')));
    await tester.pumpAndSettle();
    await selectMenu(tester, 'Select another area');
    expect(find.text('Manual Watermark Selection'), findsOneWidget);

    engine.removal = job(status: 'failed', mode: 'area', outcome: 'processing_failed');
    await tester.tap(find.byKey(const ValueKey('apply-selection-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('back-home-button')));
    await tester.pumpAndSettle();
    expect(find.text('Remove Watermarks from Your PDF'), findsOneWidget);
  });
}

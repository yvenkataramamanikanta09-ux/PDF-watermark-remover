import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_watermark_remover/models/pdf_area_selection.dart';
import 'package:pdf_watermark_remover/models/pdf_page_preview.dart';
import 'package:pdf_watermark_remover/models/selected_pdf.dart';
import 'package:pdf_watermark_remover/services/pdf_area_selection_controller.dart';

import 'fakes/pdf_preview_fakes.dart';
import 'fakes/pdf_selection_fakes.dart';

class _FileDocument implements PdfDocument {
  _FileDocument(this.file);
  final File file;
  @override
  String get name => 'original.pdf';
  @override
  Uri get uri => file.uri;
  @override
  Future<int?> length() => file.length();
  @override
  Stream<List<int>> openRead() => file.openRead();
}

void main() {
  late PdfAreaSelectionController controller;
  late SelectedPdf document;
  PdfNormalizedRect region([Rect rect = const Rect.fromLTRB(.2, .3, .8, .7)]) =>
      PdfNormalizedRect.tryCreate(rect)!;

  void ready() {
    controller.bindDocument(document);
    controller.previewAvailable(document, testPagePreview());
  }

  void draw([PdfNormalizedRect? bounds]) {
    final gesture = controller.beginDrag()!;
    final value = bounds ?? region();
    controller.updateDrag(gesture, value.rect);
    expect(controller.finishDrag(gesture, value), isTrue);
  }

  setUp(() {
    controller = PdfAreaSelectionController();
    final source = FakePdfDocument();
    document = SelectedPdf(
      name: source.name,
      size: source.bytes.length,
      content: source,
    );
  });
  tearDown(() => controller.dispose());

  test(
    'No area or preview means Apply is disabled and no source is opened',
    () async {
      controller.bindDocument(document);
      expect(controller.beginDrag(), isNull);
      expect(await controller.apply(), PdfAreaApplyResult.invalid);
      controller.previewAvailable(document, testPagePreview());
      expect(controller.canDraw, isTrue);
      expect(controller.canApply, isFalse);
      expect((document.content as FakePdfDocument).openCalls, 0);
    },
  );

  test('Commit records document identity, page one, raster frame and normalized space', () async {
    ready();
    draw();
    final id = controller.documentId;
    expect(await controller.apply(), PdfAreaApplyResult.committed);
    final saved = controller.committed!;
    expect(saved.document, same(document));
    expect(saved.documentId, id);
    expect(saved.pageNumber, 1);
    expect(saved.bounds, region());
    expect(saved.rasterWidth, 2);
    expect(saved.rasterHeight, 3);
    expect(
      saved.coordinateSpace,
      PdfSelectionCoordinateSpace.renderedPageTopLeft,
    );
    expect(controller.canApply, isTrue);
  });

  test(
    'Drawing disables Apply; replacement clears the earlier commitment',
    () async {
      ready();
      draw();
      await controller.apply();
      final gesture = controller.beginDrag()!;
      expect(controller.canApply, isFalse);
      final next = region(const Rect.fromLTRB(.1, .1, .4, .4));
      controller.updateDrag(gesture, next.rect);
      expect(controller.visibleRegion, next.rect);
      controller.finishDrag(gesture, next);
      expect(controller.draft, next);
      expect(controller.committed, isNull);
      expect(controller.canApply, isTrue);
    },
  );

  test(
    'Rejected or canceled replacement preserves the last valid area',
    () async {
      ready();
      draw();
      await controller.apply();
      final saved = controller.committed;
      final gesture = controller.beginDrag()!;
      expect(controller.finishDrag(gesture, null), isFalse);
      expect(controller.draft, region());
      expect(controller.committed, same(saved));
      final canceled = controller.beginDrag()!;
      controller.cancelInteraction();
      expect(
        controller.finishDrag(
          canceled,
          region(const Rect.fromLTRB(.1, .1, .4, .4)),
        ),
        isFalse,
      );
      expect(controller.committed, same(saved));
    },
  );

  test(
    'Clear removes draft and commitment without changing document identity',
    () async {
      ready();
      draw();
      await controller.apply();
      final id = controller.documentId;
      controller.clear();
      expect(controller.documentId, id);
      expect(controller.hasRegion, isFalse);
      expect(controller.visibleRegion, isNull);
      expect(controller.canDraw, isTrue);
      expect(controller.canApply, isFalse);
    },
  );

  test(
    'A different selected model resets even with identical names and URIs',
    () async {
      ready();
      draw();
      await controller.apply();
      final id = controller.documentId;
      final replacement = SelectedPdf(
        name: document.name,
        size: document.size,
        content: document.content,
      );
      controller.bindDocument(replacement);
      expect(controller.documentId, isNot(id));
      expect(controller.document, same(replacement));
      expect(controller.committed, isNull);
      expect(controller.draft, isNull);
      expect(controller.canApply, isFalse);
      controller.previewAvailable(document, testPagePreview());
      expect(
        controller.isReady,
        isFalse,
        reason: 'Late results for the earlier document are ignored.',
      );
    },
  );

  test(
    'Same document survives navigation and revalidation with the same frame',
    () async {
      ready();
      draw();
      await controller.apply();
      final saved = controller.committed;
      controller.previewLoading(document);
      expect(controller.canApply, isFalse);
      controller.bindDocument(document);
      controller.previewAvailable(document, testPagePreview());
      expect(controller.committed, same(saved));
      expect(controller.draft, region());
      expect(controller.canApply, isTrue);
    },
  );

  test('A changed raster orientation invalidates saved areas', () async {
    ready();
    draw();
    await controller.apply();
    controller.previewLoading(document);
    controller.previewAvailable(
      document,
      PdfPagePreview(
        bytes: testPagePreview().bytes,
        width: 3,
        height: 2,
        pageCount: 2,
      ),
    );
    expect(controller.committed, isNull);
    expect(controller.draft, isNull);
    expect(controller.isReady, isTrue);
  });

  test('A changed first-page raster invalidates saved areas even at the same dimensions', () async {
    ready();
    draw();
    await controller.apply();
    final changed = Uint8List.fromList(testPagePreview().bytes);
    changed[changed.length - 1] ^= 1;
    controller.previewLoading(document);
    controller.previewAvailable(
      document,
      PdfPagePreview(bytes: changed, width: 2, height: 3, pageCount: 2),
    );
    expect(controller.hasRegion, isFalse);
    expect(controller.canApply, isFalse);
  });

  test(
    'Preview failure and invalid dimensions invalidate all region state',
    () async {
      ready();
      draw();
      await controller.apply();
      controller.previewFailed(document);
      expect(controller.hasRegion, isFalse);
      expect(controller.isReady, isFalse);
      controller.previewAvailable(
        document,
        PdfPagePreview(
          bytes: testPagePreview().bytes,
          width: 0,
          height: 3,
          pageCount: 1,
        ),
      );
      expect(controller.isReady, isFalse);
    },
  );

  test(
    'View mode blocks selection and cancels drags while preserving valid state',
    () {
      ready();
      draw();
      final gesture = controller.beginDrag()!;
      controller.setMode(PdfSelectionMode.view);
      expect(controller.beginDrag(), isNull);
      expect(controller.finishDrag(gesture, region()), isFalse);
      expect(controller.draft, region());
      expect(controller.canApply, isTrue);
    },
  );

  test('Out-of-bounds or stale live updates cannot escape the page', () {
    ready();
    final gesture = controller.beginDrag()!;
    for (final rect in [
      const Rect.fromLTRB(-1, 0, .5, .5),
      const Rect.fromLTRB(0, 0, 2, 2),
      const Rect.fromLTRB(.8, .2, .3, .7),
      const Rect.fromLTRB(0, 0, double.nan, .5),
    ]) {
      controller.updateDrag(gesture, rect);
      expect(controller.visibleRegion, isNull);
    }
    controller.cancelInteraction();
    controller.updateDrag(gesture, region().rect);
    expect(controller.visibleRegion, isNull);
  });

  test(
    'Only one Apply preflight runs and Clear supersedes its late result',
    () async {
      final pending = Completer<bool>();
      var checks = 0;
      controller.dispose();
      controller = PdfAreaSelectionController(
        verifyAccess: (_) {
          checks++;
          return pending.future;
        },
      );
      ready();
      draw();
      final applying = controller.apply();
      expect(controller.isApplying, isTrue);
      expect(await controller.apply(), PdfAreaApplyResult.invalid);
      controller.clear();
      pending.complete(true);
      expect(await applying, PdfAreaApplyResult.superseded);
      expect(checks, 1);
      expect(controller.committed, isNull);
    },
  );

  test(
    'Changing document while Apply is pending cannot commit to the new PDF',
    () async {
      final pending = Completer<bool>();
      controller.dispose();
      controller = PdfAreaSelectionController(
        verifyAccess: (_) => pending.future,
      );
      ready();
      draw();
      final applying = controller.apply();
      controller.bindDocument(
        SelectedPdf(
          name: 'next.pdf',
          size: document.size,
          content: document.content,
        ),
      );
      pending.complete(true);
      expect(await applying, PdfAreaApplyResult.superseded);
      expect(controller.committed, isNull);
      expect(controller.draft, isNull);
    },
  );

  test('Lifecycle cancellation ignores a late Apply without discarding the valid draft', () async {
    final pending = Completer<bool>();
    controller.dispose();
    controller = PdfAreaSelectionController(
      verifyAccess: (_) => pending.future,
    );
    ready();
    draw();
    final applying = controller.apply();
    controller.cancelInteraction();
    pending.complete(true);
    expect(await applying, PdfAreaApplyResult.superseded);
    expect(controller.committed, isNull);
    expect(controller.draft, region());
    expect(controller.canApply, isTrue);
  });

  test(
    'A disposed controller ignores late asynchronous access results',
    () async {
      final pending = Completer<bool>();
      final disposed = PdfAreaSelectionController(
        verifyAccess: (_) => pending.future,
      );
      disposed.bindDocument(document);
      disposed.previewAvailable(document, testPagePreview());
      disposed.finishDrag(disposed.beginDrag()!, region());
      final applying = disposed.apply();
      disposed.dispose();
      pending.complete(true);
      expect(await applying, PdfAreaApplyResult.superseded);
    },
  );

  for (final entry in {
    'unknown size': FakePdfDocument(unknownSize: true),
    'changed size': FakePdfDocument(reportedSize: 999),
    'length access error': FakePdfDocument(
      lengthError: FileSystemException('private'),
    ),
    'read access error': FakePdfDocument(
      readError: FileSystemException('private'),
    ),
    'empty content': FakePdfDocument(bytes: [], reportedSize: 23),
  }.entries) {
    test('Access preflight rejects ${entry.key}', () async {
      final source = entry.value;
      document = SelectedPdf(
        name: source.name,
        size: source.bytes.isEmpty ? 23 : source.bytes.length,
        content: source,
      );
      ready();
      draw();
      expect(await controller.apply(), PdfAreaApplyResult.documentUnavailable);
      expect(controller.committed, isNull);
      expect(controller.draft, isNull);
      expect(controller.isReady, isFalse);
    });
  }

  test(
    'Large-source access preflight cancels after the first nonempty chunk',
    () async {
      var chunksRead = 0;
      var closed = false;
      final source = FakePdfDocument(
        reportedSize: 128 * 1024 * 1024,
        streamFactory: () async* {
          try {
            chunksRead++;
            yield List.filled(64 * 1024, 37);
            throw StateError('The rest of the PDF must not be read.');
          } finally {
            closed = true;
          }
        },
      );
      document = SelectedPdf(
        name: source.name,
        size: 128 * 1024 * 1024,
        content: source,
      );
      ready();
      draw();
      expect(await controller.apply(), PdfAreaApplyResult.committed);
      expect(chunksRead, 1);
      expect(closed, isTrue);
    },
  );

  test('Committing and clearing an area leave the original file bytes and mtime unchanged', () async {
    final directory = await Directory.systemTemp.createTemp(
      'pdf_area_readonly_',
    );
    final file = await File(
      '${directory.path}${Platform.pathSeparator}original.pdf',
    ).writeAsBytes('%PDF-1.7\nOriginal document content\n'.codeUnits);
    try {
      final bytes = await file.readAsBytes();
      final stat = await file.stat();
      final source = _FileDocument(file);
      document = SelectedPdf(
        name: source.name,
        size: bytes.length,
        content: source,
      );
      ready();
      draw();
      expect(await controller.apply(), PdfAreaApplyResult.committed);
      controller.clear();
      expect(await file.readAsBytes(), bytes);
      expect((await file.stat()).modified, stat.modified);
    } finally {
      await file.delete();
      await directory.delete();
    }
  });
}

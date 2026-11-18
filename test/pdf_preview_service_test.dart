import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_watermark_remover/models/pdf_page_preview.dart';
import 'package:pdf_watermark_remover/models/selected_pdf.dart';
import 'package:pdf_watermark_remover/services/local_pdf_preview_service.dart';
import 'package:pdf_watermark_remover/services/pdf_preview_file_store.dart';
import 'package:pdf_watermark_remover/services/pdf_preview_service.dart';

import 'fakes/pdf_preview_fakes.dart';
import 'fakes/pdf_selection_fakes.dart';

class _LocalDocument implements PdfDocument {
  _LocalDocument(this.file);
  final File file;
  int streamCalls = 0;
  @override
  String get name => 'actual.pdf';
  @override
  Uri get uri => file.uri;
  @override
  Future<int?> length() => file.length();
  @override
  Stream<List<int>> openRead() {
    streamCalls++;
    return file.openRead();
  }
}

class _Renderer implements PdfFirstPageRenderer {
  _Renderer({this.onRender});
  Future<PdfPagePreview> Function(String, PdfPreviewCancellation)? onRender;
  final paths = <String>[];
  @override
  Future<PdfPagePreview> render(
    String path, {
    required PdfPreviewCancellation cancellation,
  }) async {
    paths.add(path);
    return onRender == null
        ? testPagePreview()
        : await onRender!(path, cancellation);
  }
}

void main() {
  late Directory root;
  late PdfPreviewFileStore store;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('pdf_preview_test_');
    store = PdfPreviewFileStore(
      createTemporaryDirectory: () => root.createTemp('copy_'),
    );
  });
  tearDown(() async {
    // Only this test's freshly created files/directories; no recursive deletion.
    for (final entry in root.listSync()) {
      if (entry is Directory) {
        for (final child in entry.listSync()) {
          await child.delete();
        }
      }
      await entry.delete();
    }
    await root.delete();
  });

  SelectedPdf selected(FakePdfDocument document, {int? size}) => SelectedPdf(
    name: document.name,
    size: size ?? document.bytes.length,
    content: document,
  );
  Matcher failure(PdfPreviewFailure type) => throwsA(
    isA<PdfPreviewException>().having((e) => e.failure, 'failure', type),
  );

  test(
    'Uses an existing local reference without copying or deleting it',
    () async {
      final file = await File('${root.path}/source.pdf')
          .writeAsString('%PDF-1.7\nbody');
      final document = _LocalDocument(file);
      final renderer = _Renderer();
      final service = LocalPdfPreviewService(
        fileStore: store,
        renderer: renderer,
      );
      final result = await service.renderFirstPage(
        SelectedPdf(
          name: document.name,
          size: await file.length(),
          content: document,
        ),
        cancellation: PdfPreviewCancellation(),
      );
      expect(result.pageCount, 2);
      expect(renderer.paths.map((path) => File(path).uri), [file.uri]);
      expect(document.streamCalls, 0);
      expect(await file.exists(), isTrue);
      expect(root.listSync(), hasLength(1));
    },
  );

  test(
    'Copies stream references with a constant safe basename and cleans up',
    () async {
      final document = FakePdfDocument(name: '../../private.pdf');
      final renderer = _Renderer(
        onRender: (path, token) async {
          expect(File(path).uri.pathSegments.last, 'preview.pdf');
          expect(await File(path).readAsBytes(), document.bytes);
          return testPagePreview();
        },
      );
      final service = LocalPdfPreviewService(
        fileStore: store,
        renderer: renderer,
      );
      expect(
        await service.renderFirstPage(
          selected(document),
          cancellation: PdfPreviewCancellation(),
        ),
        isA<PdfPagePreview>(),
      );
      expect(document.openCalls, 1);
      expect(root.listSync(), isEmpty);
    },
  );

  test(
    'Rejects expired local references before invoking the renderer',
    () async {
      final document = _LocalDocument(File('${root.path}/expired.pdf'));
      final renderer = _Renderer();
      final service = LocalPdfPreviewService(
        fileStore: store,
        renderer: renderer,
      );
      await expectLater(
        service.renderFirstPage(
          SelectedPdf(name: document.name, size: 100, content: document),
          cancellation: PdfPreviewCancellation(),
        ),
        failure(PdfPreviewFailure.unreadable),
      );
      expect(renderer.paths, isEmpty);
    },
  );

  test('Rejects local files whose size changed since selection', () async {
    final file = await File('${root.path}/changed.pdf')
        .writeAsString('changed');
    final service = LocalPdfPreviewService(
      fileStore: store,
      renderer: _Renderer(),
    );
    await expectLater(
      service.renderFirstPage(
        SelectedPdf(
          name: 'changed.pdf',
          size: 500,
          content: _LocalDocument(file),
        ),
        cancellation: PdfPreviewCancellation(),
      ),
      failure(PdfPreviewFailure.unreadable),
    );
    expect(await file.exists(), isTrue);
  });

  test('Read errors clean partial copies and hide provider details', () async {
    Stream<List<int>> broken() async* {
      yield '%PDF-'.codeUnits;
      throw const FileSystemException('private source location');
    }

    final service = LocalPdfPreviewService(
      fileStore: store,
      renderer: _Renderer(),
    );
    await expectLater(
      service.renderFirstPage(
        selected(FakePdfDocument(streamFactory: broken)),
        cancellation: PdfPreviewCancellation(),
      ),
      failure(PdfPreviewFailure.unreadable),
    );
    expect(root.listSync(), isEmpty);
    expect(
      const PdfPreviewException(PdfPreviewFailure.unreadable).message,
      isNot(contains('private')),
    );
  });

  test('Renderer failure still removes its temporary copy', () async {
    final service = LocalPdfPreviewService(
      fileStore: store,
      renderer: _Renderer(
        onRender: (path, token) async => throw const PdfPreviewException(
          PdfPreviewFailure.unsupportedContent,
        ),
      ),
    );
    await expectLater(
      service.renderFirstPage(
        selected(FakePdfDocument()),
        cancellation: PdfPreviewCancellation(),
      ),
      failure(PdfPreviewFailure.unsupportedContent),
    );
    expect(root.listSync(), isEmpty);
  });

  test(
    'Unexpected renderer failures are normalized and copies removed',
    () async {
      final service = LocalPdfPreviewService(
        fileStore: store,
        renderer: _Renderer(
          onRender: (path, token) async =>
              throw StateError('native private details'),
        ),
      );
      await expectLater(
        service.renderFirstPage(
          selected(FakePdfDocument()),
          cancellation: PdfPreviewCancellation(),
        ),
        failure(PdfPreviewFailure.renderFailed),
      );
      expect(root.listSync(), isEmpty);
    },
  );

  test('Refuses an oversized stream copy without allocating a file', () async {
    final document = FakePdfDocument();
    final smallStore = PdfPreviewFileStore(
      maxCopyBytes: 8,
      createTemporaryDirectory: () => root.createTemp('copy_'),
    );
    await expectLater(
      smallStore.prepare(
        selected(document),
        cancellation: PdfPreviewCancellation(),
      ),
      failure(PdfPreviewFailure.copyTooLarge),
    );
    expect(document.openCalls, 0);
    expect(root.listSync(), isEmpty);
  });

  test(
    'Enforces the copy limit even if metadata underreports the size',
    () async {
      final document = FakePdfDocument(bytes: List.filled(32, 1));
      final smallStore = PdfPreviewFileStore(
        maxCopyBytes: 8,
        createTemporaryDirectory: () => root.createTemp('copy_'),
      );
      await expectLater(
        smallStore.prepare(
          selected(document, size: 4),
          cancellation: PdfPreviewCancellation(),
        ),
        failure(PdfPreviewFailure.copyTooLarge),
      );
      expect(root.listSync(), isEmpty);
    },
  );

  test(
    'Cancellation during copying closes the source and removes partial data',
    () async {
      final token = PdfPreviewCancellation();
      var closed = false;
      Stream<List<int>> interrupted() async* {
        try {
          yield '%PDF-'.codeUnits;
          token.cancel();
          yield '1.7\n'.codeUnits;
        } finally {
          closed = true;
        }
      }

      await expectLater(
        store.prepare(
          selected(FakePdfDocument(streamFactory: interrupted)),
          cancellation: token,
        ),
        throwsA(isA<PdfPreviewCancelled>()),
      );
      expect(closed, isTrue);
      expect(root.listSync(), isEmpty);
    },
  );

  test('Already cancelled work does not touch the source', () async {
    final token = PdfPreviewCancellation()..cancel();
    final document = FakePdfDocument();
    await expectLater(
      store.prepare(selected(document), cancellation: token),
      throwsA(isA<PdfPreviewCancelled>()),
    );
    expect(document.openCalls, 0);
    expect(root.listSync(), isEmpty);
  });

  test(
    'An empty or changed streamed reference is rejected and cleaned up',
    () async {
      await expectLater(
        store.prepare(
          selected(FakePdfDocument(bytes: []), size: 10),
          cancellation: PdfPreviewCancellation(),
        ),
        failure(PdfPreviewFailure.unreadable),
      );
      expect(root.listSync(), isEmpty);
    },
  );
}

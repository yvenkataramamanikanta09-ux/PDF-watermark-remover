import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:pdf_watermark_remover/services/pdf_preview_service.dart';
import 'package:pdf_watermark_remover/services/pdfx_first_page_renderer.dart';

import 'fakes/pdf_preview_fakes.dart';

class _Document extends pdfx.PdfDocument {
  _Document({int pages = 2, double width = 612, double height = 792})
    : super(sourceName: 'test', id: 'test-document', pagesCount: pages) {
    page = _Page(this, width, height);
  }
  late final _Page page;
  int closes = 0;
  final requestedPages = <int>[];
  @override
  Future<pdfx.PdfPage> getPage(
    int pageNumber, {
    bool autoCloseAndroid = false,
  }) async {
    requestedPages.add(pageNumber);
    return page;
  }

  @override
  Future<void> close() async {
    closes++;
    isClosed = true;
  }

  @override
  bool operator ==(Object other) => identical(this, other);
  @override
  int get hashCode => identityHashCode(this);
}

class _Page extends pdfx.PdfPage {
  _Page(pdfx.PdfDocument document, double width, double height)
    : super(
        document: document,
        id: 'page-1',
        pageNumber: 1,
        width: width,
        height: height,
        autoCloseAndroid: false,
      );
  int closes = 0;
  double? renderWidth;
  double? renderHeight;
  pdfx.PdfPageImageFormat? format;
  String? background;
  Object? renderError;
  Object? closeError;
  bool nullImage = false;
  Future<pdfx.PdfPageImage?> Function()? onRender;

  @override
  Future<pdfx.PdfPageImage?> render({
    required double width,
    required double height,
    pdfx.PdfPageImageFormat format = pdfx.PdfPageImageFormat.jpeg,
    String? backgroundColor,
    Rect? cropRect,
    int quality = 100,
    bool forPrint = false,
    bool removeTempFile = true,
  }) async {
    renderWidth = width;
    renderHeight = height;
    this.format = format;
    background = backgroundColor;
    if (renderError != null) throw renderError!;
    if (onRender != null) return onRender!();
    return nullImage ? null : _Image(width.toInt(), height.toInt());
  }

  @override
  Future<pdfx.PdfPageTexture> createTexture() => throw UnimplementedError();
  @override
  Future<void> close() async {
    closes++;
    isClosed = true;
    if (closeError != null) throw closeError!;
  }

  @override
  bool operator ==(Object other) => identical(this, other);
  @override
  int get hashCode => identityHashCode(this);
}

class _Image extends pdfx.PdfPageImage {
  _Image(int width, int height)
    : super(
        id: 'image',
        pageNumber: 1,
        width: width,
        height: height,
        bytes: testPagePreview().bytes,
        format: pdfx.PdfPageImageFormat.png,
        quality: 100,
      );
  @override
  bool operator ==(Object other) => identical(this, other);
  @override
  int get hashCode => identityHashCode(this);
}

void main() {
  Matcher failure(PdfPreviewFailure type) => throwsA(
    isA<PdfPreviewException>().having((e) => e.failure, 'failure', type),
  );

  test('Uses the selected path and first page, caps raster size, and closes handles', () async {
    final document = _Document();
    final paths = <String>[];
    final renderer = PdfxFirstPageRenderer(
      openDocument: (path) async {
        paths.add(path);
        return document;
      },
    );
    final result = await renderer.render(
      '/selected/reference.pdf',
      cancellation: PdfPreviewCancellation(),
    );
    expect(paths, ['/selected/reference.pdf']);
    expect(document.requestedPages, [1]);
    expect(document.page.renderHeight, 1024);
    expect(document.page.renderWidth, lessThanOrEqualTo(1024));
    expect(document.page.format, pdfx.PdfPageImageFormat.png);
    expect(document.page.background, '#FFFFFF');
    expect(result.pageCount, 2);
    expect(document.page.closes, 1);
    expect(document.closes, 1);
  });

  test('Landscape and oversized page dimensions retain aspect ratio within the cap', () async {
    final document = _Document(width: 20000, height: 10000);
    final renderer = PdfxFirstPageRenderer(openDocument: (_) async => document);
    final result = await renderer.render(
      'local.pdf',
      cancellation: PdfPreviewCancellation(),
    );
    expect(result.width, 1024);
    expect(result.height, 512);
  });

  test(
    'Unsupported or password-protected documents get a sanitized error',
    () async {
      final renderer = PdfxFirstPageRenderer(
        openDocument: (_) async => throw StateError('private source'),
      );
      await expectLater(
        renderer.render('local.pdf', cancellation: PdfPreviewCancellation()),
        failure(PdfPreviewFailure.unsupportedContent),
      );
    },
  );

  test('Documents without pages are closed and rejected', () async {
    final document = _Document(pages: 0);
    final renderer = PdfxFirstPageRenderer(openDocument: (_) async => document);
    await expectLater(
      renderer.render('local.pdf', cancellation: PdfPreviewCancellation()),
      failure(PdfPreviewFailure.unsupportedContent),
    );
    expect(document.closes, 1);
    expect(document.requestedPages, isEmpty);
  });

  test(
    'Invalid dimensions do not allocate an image and handles still close',
    () async {
      final document = _Document(width: double.infinity);
      final renderer = PdfxFirstPageRenderer(
        openDocument: (_) async => document,
      );
      await expectLater(
        renderer.render('local.pdf', cancellation: PdfPreviewCancellation()),
        failure(PdfPreviewFailure.renderFailed),
      );
      expect(document.page.renderWidth, isNull);
      expect(document.page.closes, 1);
      expect(document.closes, 1);
    },
  );

  test('Null rendered images are handled and closed', () async {
    final document = _Document();
    document.page.nullImage = true;
    final renderer = PdfxFirstPageRenderer(openDocument: (_) async => document);
    await expectLater(
      renderer.render('local.pdf', cancellation: PdfPreviewCancellation()),
      failure(PdfPreviewFailure.renderFailed),
    );
    expect(document.page.closes, 1);
    expect(document.closes, 1);
  });

  test('Render errors close the page and document', () async {
    final document = _Document();
    document.page.renderError = StateError('native failure');
    final renderer = PdfxFirstPageRenderer(openDocument: (_) async => document);
    await expectLater(
      renderer.render('local.pdf', cancellation: PdfPreviewCancellation()),
      failure(PdfPreviewFailure.renderFailed),
    );
    expect(document.page.closes, 1);
    expect(document.closes, 1);
  });

  test('Cancellation before opening avoids native work', () async {
    var opens = 0;
    final renderer = PdfxFirstPageRenderer(
      openDocument: (_) async {
        opens++;
        return _Document();
      },
    );
    await expectLater(
      renderer.render(
        'local.pdf',
        cancellation: PdfPreviewCancellation()..cancel(),
      ),
      throwsA(isA<PdfPreviewCancelled>()),
    );
    expect(opens, 0);
  });

  test(
    'Cancellation during opening closes the document without opening a page',
    () async {
      final document = _Document();
      final token = PdfPreviewCancellation();
      final renderer = PdfxFirstPageRenderer(
        openDocument: (_) async {
          token.cancel();
          return document;
        },
      );
      await expectLater(
        renderer.render('local.pdf', cancellation: token),
        throwsA(isA<PdfPreviewCancelled>()),
      );
      expect(document.requestedPages, isEmpty);
      expect(document.closes, 1);
    },
  );

  test('Cancellation during native rendering discards the image and closes handles', () async {
    final document = _Document();
    final token = PdfPreviewCancellation();
    document.page.onRender = () async {
      token.cancel();
      return _Image(600, 800);
    };
    final renderer = PdfxFirstPageRenderer(openDocument: (_) async => document);
    await expectLater(
      renderer.render('local.pdf', cancellation: token),
      throwsA(isA<PdfPreviewCancelled>()),
    );
    expect(document.page.closes, 1);
    expect(document.closes, 1);
  });

  test('Document closure is attempted even when page closure fails', () async {
    final document = _Document();
    document.page.closeError = StateError('close failure');
    final renderer = PdfxFirstPageRenderer(openDocument: (_) async => document);
    await expectLater(
      renderer.render('local.pdf', cancellation: PdfPreviewCancellation()),
      throwsA(isA<StateError>()),
    );
    expect(document.closes, 1);
  });
}

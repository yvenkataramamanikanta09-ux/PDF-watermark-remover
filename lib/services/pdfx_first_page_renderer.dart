import 'dart:math' as math;

import 'package:pdfx/pdfx.dart' as pdfx;

import '../models/pdf_page_preview.dart';
import 'pdf_preview_service.dart';

/// Uses pdfx's installed renderer API rather than a viewer with processing UI.
final class PdfxFirstPageRenderer implements PdfFirstPageRenderer {
  PdfxFirstPageRenderer({
    Future<pdfx.PdfDocument> Function(String)? openDocument,
  }) : _openDocument = openDocument ?? pdfx.PdfDocument.openFile;

  final Future<pdfx.PdfDocument> Function(String) _openDocument;
  static const maxRasterDimension = 1024;

  @override
  Future<PdfPagePreview> render(
    String path, {
    required PdfPreviewCancellation cancellation,
  }) async {
    pdfx.PdfDocument? document;
    pdfx.PdfPage? page;
    try {
      cancellation.throwIfCancelled();
      try {
        document = await _openDocument(path);
      } catch (_) {
        throw const PdfPreviewException(PdfPreviewFailure.unsupportedContent);
      }
      cancellation.throwIfCancelled();
      if (document.pagesCount < 1) {
        throw const PdfPreviewException(PdfPreviewFailure.unsupportedContent);
      }
      page = await document.getPage(1);
      cancellation.throwIfCancelled();
      if (!page.width.isFinite ||
          !page.height.isFinite ||
          page.width <= 0 ||
          page.height <= 0) {
        throw const PdfPreviewException(PdfPreviewFailure.renderFailed);
      }
      final scale = maxRasterDimension / math.max(page.width, page.height);
      final width = (page.width * scale).round().clamp(1, maxRasterDimension);
      final height = (page.height * scale).round().clamp(1, maxRasterDimension);
      final image = await page.render(
        width: width.toDouble(),
        height: height.toDouble(),
        format: pdfx.PdfPageImageFormat.png,
        backgroundColor: '#FFFFFF',
      );
      cancellation.throwIfCancelled();
      if (image == null || image.bytes.isEmpty) {
        throw const PdfPreviewException(PdfPreviewFailure.renderFailed);
      }
      return PdfPagePreview(
        bytes: image.bytes,
        width: image.width ?? width,
        height: image.height ?? height,
        pageCount: document.pagesCount,
      );
    } on PdfPreviewException {
      rethrow;
    } on PdfPreviewCancelled {
      rethrow;
    } catch (_) {
      throw const PdfPreviewException(PdfPreviewFailure.renderFailed);
    } finally {
      try {
        if (page != null && !page.isClosed) await page.close();
      } finally {
        if (document != null && !document.isClosed) await document.close();
      }
    }
  }
}

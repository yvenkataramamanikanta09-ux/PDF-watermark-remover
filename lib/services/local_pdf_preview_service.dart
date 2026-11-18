import 'dart:io';

import '../models/pdf_page_preview.dart';
import '../models/selected_pdf.dart';
import 'pdf_preview_file_store.dart';
import 'pdf_preview_service.dart';
import 'pdfx_first_page_renderer.dart';

final class LocalPdfPreviewService implements PdfPreviewService {
  LocalPdfPreviewService({
    PdfPreviewFileStore? fileStore,
    PdfFirstPageRenderer? renderer,
  }) : _fileStore = fileStore ?? PdfPreviewFileStore(),
       _renderer = renderer ?? PdfxFirstPageRenderer();

  final PdfPreviewFileStore _fileStore;
  final PdfFirstPageRenderer _renderer;

  @override
  Future<PdfPagePreview> renderFirstPage(
    SelectedPdf pdf, {
    required PdfPreviewCancellation cancellation,
  }) async {
    try {
      final local = await _fileStore.prepare(pdf, cancellation: cancellation);
      try {
        cancellation.throwIfCancelled();
        return await _renderer.render(local.path, cancellation: cancellation);
      } finally {
        await local.dispose();
      }
    } on PdfPreviewException {
      rethrow;
    } on PdfPreviewCancelled {
      rethrow;
    } on FileSystemException {
      throw const PdfPreviewException(PdfPreviewFailure.unreadable);
    } catch (_) {
      throw const PdfPreviewException(PdfPreviewFailure.renderFailed);
    }
  }
}

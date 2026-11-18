import '../models/pdf_page_preview.dart';
import '../models/selected_pdf.dart';

enum PdfPreviewFailure {
  unreadable,
  unsupportedContent,
  renderFailed,
  copyTooLarge,
}

final class PdfPreviewException implements Exception {
  const PdfPreviewException(this.failure);

  final PdfPreviewFailure failure;

  String get message => switch (failure) {
    PdfPreviewFailure.unreadable =>
      'This PDF is no longer readable. Go back and choose it again.',
    PdfPreviewFailure.unsupportedContent =>
      'This PDF cannot be previewed. It may be damaged or password protected.',
    PdfPreviewFailure.renderFailed => 'The first page could not be displayed. Try the preview again or choose another PDF.',
    PdfPreviewFailure.copyTooLarge =>
      'This document is too large to copy for preview. Choose a smaller PDF.',
  };

  @override
  String toString() => 'PdfPreviewException(${failure.name})';
}

final class PdfPreviewCancelled implements Exception {}

/// Cooperative cancellation; native rendering finishes before handles close.
final class PdfPreviewCancellation {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
  void throwIfCancelled() {
    if (_cancelled) throw PdfPreviewCancelled();
  }
}

abstract interface class PdfPreviewService {
  Future<PdfPagePreview> renderFirstPage(
    SelectedPdf pdf, {
    required PdfPreviewCancellation cancellation,
  });
}

abstract interface class PdfFirstPageRenderer {
  Future<PdfPagePreview> render(
    String path, {
    required PdfPreviewCancellation cancellation,
  });
}

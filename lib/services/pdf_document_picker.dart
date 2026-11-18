import '../models/selected_pdf.dart';

/// Platform-independent boundary for selecting one document, or canceling.
abstract interface class PdfDocumentPicker {
  Future<PdfDocument?> pickPdf();
}

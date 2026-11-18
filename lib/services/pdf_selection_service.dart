import '../models/selected_pdf.dart';
import 'pdf_document_picker.dart';

enum PdfSelectionFailure {
  invalidExtension,
  emptyFile,
  invalidHeader,
  unreadableFile,
  pickerUnavailable,
}

final class PdfSelectionException implements Exception {
  const PdfSelectionException(this.failure);

  final PdfSelectionFailure failure;

  String get message => switch (failure) {
    PdfSelectionFailure.invalidExtension =>
      'Choose a file with a .pdf extension.',
    PdfSelectionFailure.emptyFile =>
      'This PDF is empty. Choose a different file.',
    PdfSelectionFailure.invalidHeader =>
      'This file does not have a valid PDF header. Choose another PDF.',
    PdfSelectionFailure.unreadableFile =>
      "This file couldn't be read. Download it to your device and try again.",
    PdfSelectionFailure.pickerUnavailable =>
      "Couldn't select a file. Please try again.",
  };

  @override
  String toString() => 'PdfSelectionException(${failure.name})';
}

/// Selects a PDF and performs bounded, preliminary validation.
///
/// Inspects and retains nine header bytes, then cancels the stream. The source
/// may supply a larger bounded chunk. This does not parse objects,
/// cross-reference tables, encryption, or the rest of the file.
final class PdfSelectionService {
  PdfSelectionService({required this._picker});

  final PdfDocumentPicker _picker;
  SelectedPdf? _selectedPdf;
  Future<SelectedPdf?>? _inFlight;

  /// Retained for this service's lifetime, including navigation back to Home.
  /// Cancellation and failed replacements leave the previous selection intact.
  SelectedPdf? get selectedPdf => _selectedPdf;

  Future<SelectedPdf?> selectPdf() {
    // Coalesce concurrent requests instead of opening overlapping native pickers.
    return _inFlight ??= _selectAndValidate().whenComplete(() {
      _inFlight = null;
    });
  }

  Future<SelectedPdf?> _selectAndValidate() async {
    final PdfDocument? document;
    try {
      document = await _picker.pickPdf();
    } catch (_) {
      throw const PdfSelectionException(PdfSelectionFailure.pickerUnavailable);
    }
    if (document == null) return null;

    try {
      final name = document.name;
      if (!name.toLowerCase().endsWith('.pdf')) {
        throw const PdfSelectionException(PdfSelectionFailure.invalidExtension);
      }

      final size = await document.length();
      if (size == null || size < 0) {
        throw const PdfSelectionException(PdfSelectionFailure.unreadableFile);
      }
      if (size == 0) {
        throw const PdfSelectionException(PdfSelectionFailure.emptyFile);
      }

      final header = <int>[];
      await for (final chunk in document.openRead()) {
        header.addAll(chunk.take(9 - header.length));
        if (header.length == 9) break;
      }
      if (header.isEmpty) {
        throw const PdfSelectionException(PdfSelectionFailure.emptyFile);
      }

      // PDF 1.0–1.7 or 2.0, at byte zero, followed by LF or CR (including CRLF).
      final signature = String.fromCharCodes(header);
      if (!RegExp(r'^%PDF-(?:1\.[0-7]|2\.0)[\r\n]$').hasMatch(signature)) {
        throw const PdfSelectionException(PdfSelectionFailure.invalidHeader);
      }

      final selected = SelectedPdf(name: name, size: size, content: document);
      _selectedPdf = selected;
      return selected;
    } on PdfSelectionException {
      rethrow;
    } catch (_) {
      // Never expose provider exceptions, local paths, or document contents.
      throw const PdfSelectionException(PdfSelectionFailure.unreadableFile);
    }
  }
}

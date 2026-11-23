import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

/// Lets the user choose where the cleaned PDF goes (Android's "Save as" screen).
abstract interface class PdfSaver {
  /// Returns false when the user cancels.
  Future<bool> save({required String fileName, required Uint8List bytes});
}

final class FilePickerPdfSaver implements PdfSaver {
  const FilePickerPdfSaver();

  @override
  Future<bool> save({required String fileName, required Uint8List bytes}) async {
    final uri = await FilePicker.saveFile(
      fileName: fileName,
      bytes: bytes,
      mimeType: 'application/pdf',
      dialogTitle: 'Save cleaned PDF',
    );
    return uri != null;
  }
}

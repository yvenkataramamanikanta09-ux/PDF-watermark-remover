import 'package:file_picker/file_picker.dart';

import '../models/selected_pdf.dart';
import 'pdf_document_picker.dart';

final class FilePickerPdfDocumentPicker implements PdfDocumentPicker {
  const FilePickerPdfDocumentPicker();

  @override
  Future<PdfDocument?> pickPdf() async {
    // file_picker 13 uses pickFile for a single selection and null for cancel.
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    return file == null ? null : _PlatformPdfDocument(file);
  }
}

final class _PlatformPdfDocument implements PdfDocument {
  const _PlatformPdfDocument(this._file);

  final PlatformFile _file;

  @override
  String get name => _file.name;

  @override
  Uri get uri => _file.uri;

  @override
  Future<int?> length() => _file.length();

  @override
  Stream<List<int>> openRead() => _file.readAsByteStream();
}

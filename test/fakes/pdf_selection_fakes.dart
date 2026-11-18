import 'package:pdf_watermark_remover/models/selected_pdf.dart';
import 'package:pdf_watermark_remover/services/pdf_document_picker.dart';

class FakePdfDocumentPicker implements PdfDocumentPicker {
  FakePdfDocumentPicker({this.result, this.error, this.onPick});

  PdfDocument? result;
  Object? error;
  Future<PdfDocument?> Function()? onPick;
  int calls = 0;

  @override
  Future<PdfDocument?> pickPdf() async {
    calls++;
    if (error != null) throw error!;
    final callback = onPick;
    if (callback != null) return callback();
    return result;
  }
}

class FakePdfDocument implements PdfDocument {
  FakePdfDocument({
    this.name = 'sample.pdf',
    List<int>? bytes,
    this.reportedSize,
    this.unknownSize = false,
    this.lengthError,
    this.readError,
    this.streamFactory,
  }) : bytes = bytes ?? '%PDF-1.7\nexample content'.codeUnits;

  @override
  final String name;
  final List<int> bytes;
  final int? reportedSize;
  final bool unknownSize;
  final Object? lengthError;
  final Object? readError;
  final Stream<List<int>> Function()? streamFactory;
  int lengthCalls = 0;
  int openCalls = 0;

  @override
  Uri get uri => Uri(scheme: 'memory', path: name);

  @override
  Future<int?> length() async {
    lengthCalls++;
    if (lengthError != null) throw lengthError!;
    return unknownSize ? null : reportedSize ?? bytes.length;
  }

  @override
  Stream<List<int>> openRead() {
    openCalls++;
    if (readError != null) return Stream.error(readError!);
    return streamFactory?.call() ?? Stream.value(bytes);
  }
}

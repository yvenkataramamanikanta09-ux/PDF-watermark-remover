/// A readable document without holding its contents in memory.
abstract interface class PdfDocument {
  String get name;
  Uri get uri;
  Future<int?> length();

  /// Opens a fresh stream at the start of the document on every call.
  Stream<List<int>> openRead();
}

/// A selection that passed preliminary extension and PDF-header checks.
///
/// This does not establish that the entire PDF is structurally valid. The
/// underlying platform reference may expire if its cached file is removed.
final class SelectedPdf {
  const SelectedPdf({
    required this.name,
    required this.size,
    required this.content,
  });

  final String name;
  final int size;
  final PdfDocument content;
}

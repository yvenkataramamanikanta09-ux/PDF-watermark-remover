import 'dart:typed_data';

/// One rasterized page, not the PDF's full byte content.
final class PdfPagePreview {
  const PdfPagePreview({
    required this.bytes,
    required this.width,
    required this.height,
    required this.pageCount,
  });

  final Uint8List bytes;
  final int width;
  final int height;
  final int pageCount;
}

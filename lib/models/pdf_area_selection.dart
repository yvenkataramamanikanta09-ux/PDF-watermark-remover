import 'dart:ui';

import 'selected_pdf.dart';

/// Unit coordinates on the whole rendered page, with a top-left origin.
///
/// These are deliberately NOT unrotated PDF user-space coordinates. Android's
/// renderer has already applied the page's native orientation to the image.
enum PdfSelectionCoordinateSpace { renderedPageTopLeft }

final class PdfNormalizedRect {
  const PdfNormalizedRect._(this.rect);

  static const minimumExtent = 0.02;
  final Rect rect;

  static PdfNormalizedRect? tryCreate(Rect rect) {
    if (!rect.isFinite ||
        rect.left < 0 ||
        rect.top < 0 ||
        rect.right > 1 ||
        rect.bottom > 1 ||
        rect.width < minimumExtent ||
        rect.height < minimumExtent) {
      return null;
    }
    return PdfNormalizedRect._(rect);
  }

  @override
  bool operator ==(Object other) =>
      other is PdfNormalizedRect && other.rect == rect;
  @override
  int get hashCode => rect.hashCode;
}

/// Session state only; committing this model does not write to a PDF.
final class PdfAreaSelection {
  const PdfAreaSelection({
    required this.documentId,
    required this.document,
    required this.bounds,
    required this.rasterWidth,
    required this.rasterHeight,
  });

  /// Opaque session identity; names and provider URIs are not unique identities.
  final String documentId;
  final SelectedPdf document;
  final PdfNormalizedRect bounds;
  final int rasterWidth;
  final int rasterHeight;
  int get pageNumber => 1;
  PdfSelectionCoordinateSpace get coordinateSpace =>
      PdfSelectionCoordinateSpace.renderedPageTopLeft;
}

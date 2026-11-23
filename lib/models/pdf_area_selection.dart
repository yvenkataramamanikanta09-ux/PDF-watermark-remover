import 'dart:ui';

/// A rectangle in unit coordinates of the page-one preview image the engine rendered,
/// origin at its top-left (`renderedPageTopLeft`). The engine binds it to the
/// exact preview it rendered, so no screen or PDF units are involved here.
final class PdfNormalizedRect {
  const PdfNormalizedRect._(this.rect);

  /// The engine requires at least 2% of the page on each axis.
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

  Map<String, double> toJson() => {
    'left': rect.left,
    'top': rect.top,
    'right': rect.right,
    'bottom': rect.bottom,
  };

  @override
  bool operator ==(Object other) =>
      other is PdfNormalizedRect && other.rect == rect;

  @override
  int get hashCode => rect.hashCode;
}

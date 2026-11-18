import 'dart:math' as math;
import 'dart:ui';

import '../models/pdf_area_selection.dart';

/// The same contain fit is used to place the image and map pointer coordinates.
/// No screenshot offsets, device pixel ratios, or PDF point units are assumed.
final class PdfSelectionGeometry {
  PdfSelectionGeometry({required this.viewport, required this.pageSize});

  static const minimumVisibleExtent = 8.0;
  final Size viewport;
  final Size pageSize;

  Rect get pageBounds {
    if (!_validSize(viewport) || !_validSize(pageSize)) return Rect.zero;
    final scale = math.min(
      viewport.width / pageSize.width,
      viewport.height / pageSize.height,
    );
    final size = Size(pageSize.width * scale, pageSize.height * scale);
    return Rect.fromLTWH(
      (viewport.width - size.width) / 2,
      (viewport.height - size.height) / 2,
      size.width,
      size.height,
    );
  }

  bool _validSize(Size size) =>
      size.width.isFinite &&
      size.height.isFinite &&
      size.width > 0 &&
      size.height > 0;

  bool contains(Offset point) {
    final page = pageBounds;
    return !page.isEmpty &&
        point.dx.isFinite &&
        point.dy.isFinite &&
        point.dx >= page.left &&
        point.dx <= page.right &&
        point.dy >= page.top &&
        point.dy <= page.bottom;
  }

  Rect? dragRect(Offset start, Offset end) {
    if (!contains(start) || !end.dx.isFinite || !end.dy.isFinite) return null;
    final page = pageBounds;
    final a = Offset(
      ((start.dx - page.left) / page.width).clamp(0, 1),
      ((start.dy - page.top) / page.height).clamp(0, 1),
    );
    final b = Offset(
      ((end.dx - page.left) / page.width).clamp(0, 1),
      ((end.dy - page.top) / page.height).clamp(0, 1),
    );
    return Rect.fromPoints(a, b);
  }

  PdfNormalizedRect? selectionFromDrag(Offset start, Offset end) {
    final rect = dragRect(start, end);
    if (rect == null) return null;
    final visible = toVisible(rect);
    if (visible.width < minimumVisibleExtent ||
        visible.height < minimumVisibleExtent) {
      return null;
    }
    return PdfNormalizedRect.tryCreate(rect);
  }

  Rect toVisible(Rect normalized) {
    final page = pageBounds;
    return Rect.fromLTRB(
      page.left + normalized.left * page.width,
      page.top + normalized.top * page.height,
      page.left + normalized.right * page.width,
      page.top + normalized.bottom * page.height,
    );
  }
}

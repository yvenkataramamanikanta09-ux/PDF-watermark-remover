import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../models/pdf_area_selection.dart';

/// State of the rectangle the user drags on the page preview.
///
/// Independent of widgets and of the network: the screen enables it while an
/// area may be drawn and reads [area] when the user starts the removal.
final class PdfAreaSelectionController extends ChangeNotifier {
  PdfNormalizedRect? _area;
  Rect? _dragRect;
  int? _gesture;
  int _revision = 0;
  bool _enabled = false;

  /// The last completed, valid area.
  PdfNormalizedRect? get area => _area;

  /// What to paint: the rectangle being dragged, else the completed area.
  Rect? get visibleRegion => _dragRect ?? _area?.rect;
  bool get isDrawing => _gesture != null;
  int? get activeGesture => _gesture;
  bool get hasArea => _area != null;
  bool get canDraw => _enabled;

  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    cancelInteraction();
  }

  int? beginDrag() {
    if (!canDraw) return null;
    _gesture = ++_revision;
    _dragRect = null;
    notifyListeners();
    return _gesture;
  }

  void updateDrag(int gesture, Rect rect) {
    if (_gesture != gesture ||
        !canDraw ||
        !rect.isFinite ||
        rect.left < 0 ||
        rect.top < 0 ||
        rect.right > 1 ||
        rect.bottom > 1 ||
        rect.width < 0 ||
        rect.height < 0) {
      return;
    }
    _dragRect = rect;
    notifyListeners();
  }

  /// Ends a drag. A null [region] (too small) keeps the previous area.
  bool finishDrag(int gesture, PdfNormalizedRect? region) {
    if (_gesture != gesture || !canDraw) return false;
    _gesture = null;
    _dragRect = null;
    _revision++;
    if (region != null) _area = region;
    notifyListeners();
    return region != null;
  }

  void cancelInteraction() {
    _gesture = null;
    _dragRect = null;
    _revision++;
    notifyListeners();
  }

  void clear() {
    _area = null;
    cancelInteraction();
  }
}

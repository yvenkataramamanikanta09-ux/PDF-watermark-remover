import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../models/pdf_area_selection.dart';
import '../models/pdf_page_preview.dart';
import '../models/selected_pdf.dart';

enum PdfSelectionMode { select, view }

enum PdfAreaApplyResult { committed, invalid, documentUnavailable, superseded }

/// App-owned session state, independent of gestures, drawing, or PDF mutation.
final class PdfAreaSelectionController extends ChangeNotifier {
  PdfAreaSelectionController({Future<bool> Function(SelectedPdf)? verifyAccess})
    : _verifyAccess = verifyAccess ?? _isReadable;

  final Future<bool> Function(SelectedPdf) _verifyAccess;
  static int _nextDocumentId = 0;
  SelectedPdf? _document;
  String? _documentId;
  PdfNormalizedRect? _draft;
  PdfAreaSelection? _committed;
  Rect? _dragRect;
  int? _gesture;
  int _revision = 0;
  int? _width;
  int? _height;
  // Keep only the bounded preview raster for exact re-open/retry comparison.
  // This is not a PDF content hash or a complete-document integrity guarantee.
  Uint8List? _pageBytes;
  bool _ready = false;
  bool _applying = false;
  bool _disposed = false;
  PdfSelectionMode _mode = PdfSelectionMode.select;

  SelectedPdf? get document => _document;
  String? get documentId => _documentId;
  PdfNormalizedRect? get draft => _draft;
  PdfAreaSelection? get committed => _committed;
  Rect? get visibleRegion => _dragRect ?? _draft?.rect;
  bool get isDrawing => _gesture != null;
  int? get activeGesture => _gesture;
  bool get isApplying => _applying;
  bool get isReady => _ready;
  PdfSelectionMode get mode => _mode;
  bool get hasRegion => _draft != null || _committed != null;
  bool get canApply => _ready && _draft != null && !isDrawing && !_applying;
  bool get canDraw => _ready && _mode == PdfSelectionMode.select && !_applying;

  void bindDocument(SelectedPdf document) {
    if (identical(_document, document)) return;
    _document = document;
    _documentId = 'session-document-${++_nextDocumentId}';
    _width = _height = null;
    _pageBytes = null;
    _ready = false;
    _mode = PdfSelectionMode.select;
    clear();
  }

  void previewLoading(SelectedPdf document) {
    if (!identical(_document, document)) return;
    _ready = false;
    cancelInteraction();
  }

  void previewAvailable(SelectedPdf document, PdfPagePreview page) {
    if (!identical(_document, document)) return;
    if (page.width <= 0 || page.height <= 0 || page.pageCount < 1) {
      previewFailed(document);
      return;
    }
    if (_width != null &&
        (_width != page.width ||
            _height != page.height ||
            !listEquals(_pageBytes, page.bytes))) {
      _draft = null;
      _committed = null;
    }
    _width = page.width;
    _height = page.height;
    _pageBytes = page.bytes;
    _ready = true;
    cancelInteraction();
  }

  void previewFailed(SelectedPdf document) {
    if (!identical(_document, document)) return;
    _ready = false;
    _pageBytes = null;
    _width = _height = null;
    clear();
  }

  void setMode(PdfSelectionMode mode) {
    if (_mode == mode) return;
    _mode = mode;
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

  bool finishDrag(int gesture, PdfNormalizedRect? region) {
    if (_gesture != gesture || !canDraw) return false;
    _gesture = null;
    _dragRect = null;
    _revision++;
    if (region != null) {
      _draft = region;
      _committed = null;
    }
    notifyListeners();
    return region != null;
  }

  void cancelInteraction() {
    _gesture = null;
    _dragRect = null;
    _applying = false;
    _revision++;
    notifyListeners();
  }

  void clear() {
    _draft = null;
    _committed = null;
    cancelInteraction();
  }

  Future<PdfAreaApplyResult> apply() async {
    if (!canApply) return PdfAreaApplyResult.invalid;
    final document = _document!;
    final bounds = _draft!;
    final revision = ++_revision;
    _applying = true;
    notifyListeners();
    bool readable;
    try {
      readable = await _verifyAccess(document);
    } catch (_) {
      readable = false;
    }
    if (_disposed || revision != _revision || !identical(document, _document)) {
      return PdfAreaApplyResult.superseded;
    }
    _applying = false;
    if (!readable) {
      previewFailed(document);
      return PdfAreaApplyResult.documentUnavailable;
    }
    _committed = PdfAreaSelection(
      documentId: _documentId!,
      document: document,
      bounds: bounds,
      rasterWidth: _width!,
      rasterHeight: _height!,
    );
    notifyListeners();
    return PdfAreaApplyResult.committed;
  }

  // A bounded access preflight, not a second picker or full integrity check.
  static Future<bool> _isReadable(SelectedPdf document) async {
    if (await document.content.length() != document.size) return false;
    await for (final chunk in document.content.openRead()) {
      if (chunk.isNotEmpty) return true; // return cancels the read subscription
    }
    return false;
  }

  @override
  void dispose() {
    _disposed = true;
    _pageBytes = null;
    _revision++;
    super.dispose();
  }
}

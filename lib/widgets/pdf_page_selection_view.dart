import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import '../models/pdf_page_preview.dart';
import '../services/pdf_area_selection_controller.dart';
import '../theme/app_theme.dart';
import '../utils/pdf_selection_geometry.dart';

class PdfPageSelectionView extends StatefulWidget {
  const PdfPageSelectionView({
    super.key,
    required this.page,
    required this.filename,
    required this.controller,
    required this.onDecodeError,
    required this.onInvalidSelection,
  });

  final PdfPagePreview page;
  final String filename;
  final PdfAreaSelectionController controller;
  final VoidCallback onDecodeError;
  final VoidCallback onInvalidSelection;

  @override
  State<PdfPageSelectionView> createState() => _PdfPageSelectionViewState();
}

class _PdfPageSelectionViewState extends State<PdfPageSelectionView> {
  final _pointers = <int>{};
  int? _pointer;
  int? _gesture;
  Offset? _start;
  PdfSelectionGeometry? _dragGeometry;
  List<double>? _dragTransform;
  bool _multiplePointers = false;

  void _resetPointers() {
    _pointers.clear();
    _pointer = _gesture = null;
    _start = null;
    _dragGeometry = null;
    _dragTransform = null;
    _multiplePointers = false;
  }

  RenderBox get _viewportBox => context.findRenderObject()! as RenderBox;

  bool _sameGeometry(PdfSelectionGeometry geometry) {
    if (_dragGeometry?.viewport != geometry.viewport ||
        _dragGeometry?.pageSize != geometry.pageSize ||
        _dragTransform == null) {
      return false;
    }
    final current = _viewportBox.getTransformTo(null).storage;
    for (var index = 0; index < current.length; index++) {
      if ((current[index] - _dragTransform![index]).abs() > 1e-7) return false;
    }
    return true;
  }

  void _down(PointerDownEvent event, PdfSelectionGeometry geometry) {
    _pointers.add(event.pointer);
    if (_pointers.length > 1) {
      _multiplePointers = true;
      _pointer = null;
      widget.controller.cancelInteraction();
      return;
    }
    if (_multiplePointers || event.buttons != kPrimaryButton) return;
    final gesture = widget.controller.beginDrag();
    if (gesture == null) return;
    _gesture = gesture;
    _pointer = event.pointer;
    _dragGeometry = geometry;
    _dragTransform = List<double>.of(_viewportBox.getTransformTo(null).storage);
    _start = _viewportBox.globalToLocal(event.position);
  }

  void _move(PointerMoveEvent event, PdfSelectionGeometry geometry) {
    if (event.pointer != _pointer || _multiplePointers || _gesture == null) {
      return;
    }
    if (!_sameGeometry(geometry)) {
      widget.controller.cancelInteraction();
      _resetPointers();
      return;
    }
    final rect = geometry.dragRect(
      _start!,
      _viewportBox.globalToLocal(event.position),
    );
    if (rect != null) widget.controller.updateDrag(_gesture!, rect);
  }

  void _up(PointerUpEvent event, PdfSelectionGeometry geometry) {
    _pointers.remove(event.pointer);
    if (event.pointer == _pointer &&
        !_multiplePointers &&
        _gesture != null &&
        widget.controller.activeGesture == _gesture) {
      if (_sameGeometry(geometry)) {
        final selected = geometry.selectionFromDrag(
          _start!,
          _viewportBox.globalToLocal(event.position),
        );
        if (!widget.controller.finishDrag(_gesture!, selected)) {
          widget.onInvalidSelection();
        }
      } else {
        widget.controller.cancelInteraction();
      }
    }
    if (_pointers.isEmpty) _resetPointers();
  }

  void _cancel(PointerCancelEvent event) {
    _pointers.remove(event.pointer);
    if (event.pointer == _pointer) widget.controller.cancelInteraction();
    if (_pointers.isEmpty) _resetPointers();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.controller.canDraw) {
      _resetPointers();
    } else if (_gesture != null &&
        widget.controller.activeGesture != _gesture) {
      if (_multiplePointers) {
        _pointer = _gesture = null;
        _start = null;
        _dragGeometry = null;
        _dragTransform = null;
      } else {
        _resetPointers();
      }
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final geometry = PdfSelectionGeometry(
          viewport: constraints.biggest,
          pageSize: Size(
            widget.page.width.toDouble(),
            widget.page.height.toDouble(),
          ),
        );
        final pageBounds = geometry.pageBounds;
        final region = widget.controller.visibleRegion;
        return Stack(
          key: const ValueKey('pdf-selection-viewport'),
          children: [
            Positioned.fromRect(
              key: const ValueKey('pdf-page-position'),
              rect: pageBounds,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  widget.page.bytes,
                  fit: BoxFit.contain,
                  semanticLabel: 'First page of ${widget.filename}',
                  errorBuilder: (context, error, stackTrace) {
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => widget.onDecodeError(),
                    );
                    return const Center(child: Text('Preview unavailable.'));
                  },
                ),
              ),
            ),
            if (region != null)
              Positioned.fromRect(
                key: const ValueKey('pdf-overlay-position'),
                rect: pageBounds,
                child: IgnorePointer(
                  child: ClipRect(
                    child: CustomPaint(
                      key: const ValueKey('pdf-region-outline'),
                      painter: PdfRegionPainter(region: region),
                    ),
                  ),
                ),
              ),
            Positioned.fromRect(
              key: const ValueKey('pdf-hit-position'),
              rect: pageBounds,
              child: widget.controller.canDraw
                  ? Semantics(
                      label: 'Select watermark area on page one',
                      hint: 'Drag to select. Drag again to replace. Coordinates follow the displayed page.',
                      child: RawGestureDetector(
                        gestures: {
                          EagerGestureRecognizer:
                              GestureRecognizerFactoryWithHandlers<
                                EagerGestureRecognizer
                              >(EagerGestureRecognizer.new, (_) {}),
                        },
                        child: Listener(
                          key: const ValueKey('pdf-page-gesture-surface'),
                          behavior: HitTestBehavior.opaque,
                          onPointerDown: (event) => _down(event, geometry),
                          onPointerMove: (event) => _move(event, geometry),
                          onPointerUp: (event) => _up(event, geometry),
                          onPointerCancel: _cancel,
                        ),
                      ),
                    )
                  : const SizedBox(key: ValueKey('pdf-page-gesture-surface')),
            ),
          ],
        );
      },
    );
  }
}

class PdfRegionPainter extends CustomPainter {
  const PdfRegionPainter({required this.region});
  final Rect region;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTRB(
      region.left * size.width,
      region.top * size.height,
      region.right * size.width,
      region.bottom * size.height,
    );
    canvas.drawRect(
      rect,
      Paint()..color = AppColors.accent.withValues(alpha: 0.16),
    );
    // Inset the stroke so even edge-to-edge regions stay inside the PDF page.
    if (rect.width >= 2 && rect.height >= 2) {
      canvas.drawRect(
        rect.deflate(1),
        Paint()
          ..color = AppColors.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(PdfRegionPainter oldDelegate) =>
      oldDelegate.region != region;
}

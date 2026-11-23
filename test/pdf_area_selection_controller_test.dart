import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_watermark_remover/models/pdf_area_selection.dart';
import 'package:pdf_watermark_remover/services/pdf_area_selection_controller.dart';

void main() {
  PdfNormalizedRect area([Rect rect = const Rect.fromLTRB(0.1, 0.1, 0.5, 0.5)]) =>
      PdfNormalizedRect.tryCreate(rect)!;

  test('drawing is refused until enabled', () {
    final controller = PdfAreaSelectionController();
    expect(controller.canDraw, isFalse);
    expect(controller.beginDrag(), isNull);
    controller.enabled = true;
    expect(controller.beginDrag(), isNotNull);
  });

  test('a completed drag becomes the area and notifies listeners', () {
    final controller = PdfAreaSelectionController()..enabled = true;
    var notifications = 0;
    controller.addListener(() => notifications++);
    final gesture = controller.beginDrag()!;
    controller.updateDrag(gesture, const Rect.fromLTRB(0.1, 0.1, 0.3, 0.3));
    expect(controller.isDrawing, isTrue);
    expect(controller.visibleRegion, const Rect.fromLTRB(0.1, 0.1, 0.3, 0.3));
    expect(controller.finishDrag(gesture, area()), isTrue);
    expect(controller.isDrawing, isFalse);
    expect(controller.area, area());
    expect(controller.visibleRegion, area().rect);
    expect(notifications, 3);
  });

  test('a too-small drag keeps the previous area', () {
    final controller = PdfAreaSelectionController()..enabled = true;
    controller.finishDrag(controller.beginDrag()!, area());
    final second = controller.beginDrag()!;
    expect(controller.finishDrag(second, null), isFalse);
    expect(controller.area, area());
  });

  test('stale gestures and out-of-range updates are ignored', () {
    final controller = PdfAreaSelectionController()..enabled = true;
    final first = controller.beginDrag()!;
    controller.cancelInteraction();
    expect(controller.finishDrag(first, area()), isFalse);
    expect(controller.area, isNull);
    final second = controller.beginDrag()!;
    controller.updateDrag(second, const Rect.fromLTRB(-0.1, 0, 0.5, 0.5));
    controller.updateDrag(second, const Rect.fromLTRB(0, 0, 1.5, 0.5));
    controller.updateDrag(second, const Rect.fromLTRB(0, 0, double.nan, 0.5));
    expect(controller.visibleRegion, isNull);
  });

  test('disabling cancels a drag but keeps the area; clear removes it', () {
    final controller = PdfAreaSelectionController()..enabled = true;
    controller.finishDrag(controller.beginDrag()!, area());
    controller.beginDrag();
    controller.enabled = false;
    expect(controller.isDrawing, isFalse);
    expect(controller.hasArea, isTrue);
    controller.clear();
    expect(controller.hasArea, isFalse);
    expect(controller.visibleRegion, isNull);
  });

  test('normalized rectangles enforce bounds and the 2% minimum', () {
    expect(PdfNormalizedRect.tryCreate(const Rect.fromLTRB(0, 0, 1, 1)), isNotNull);
    expect(PdfNormalizedRect.tryCreate(const Rect.fromLTRB(0.1, 0.1, 0.11, 0.5)), isNull);
    expect(PdfNormalizedRect.tryCreate(const Rect.fromLTRB(-0.1, 0.1, 0.5, 0.5)), isNull);
    expect(PdfNormalizedRect.tryCreate(const Rect.fromLTRB(0.1, 0.1, 1.01, 0.5)), isNull);
    expect(area().toJson(), {'left': 0.1, 'top': 0.1, 'right': 0.5, 'bottom': 0.5});
  });
}

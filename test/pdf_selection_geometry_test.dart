import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_watermark_remover/models/pdf_area_selection.dart';
import 'package:pdf_watermark_remover/utils/pdf_selection_geometry.dart';

void main() {
  final portrait = PdfSelectionGeometry(
    viewport: const Size(400, 400),
    pageSize: const Size(200, 400),
  );
  final landscape = PdfSelectionGeometry(
    viewport: const Size(400, 400),
    pageSize: const Size(400, 200),
  );
  void closeRect(Rect actual, Rect expected) {
    expect(actual.left, closeTo(expected.left, 1e-10));
    expect(actual.top, closeTo(expected.top, 1e-10));
    expect(actual.right, closeTo(expected.right, 1e-10));
    expect(actual.bottom, closeTo(expected.bottom, 1e-10));
  }

  test('Portrait contain fit excludes horizontal letterboxing', () {
    expect(portrait.pageBounds, const Rect.fromLTWH(100, 0, 200, 400));
    expect(
      portrait.selectionFromDrag(const Offset(50, 100), const Offset(200, 200)),
      isNull,
    );
  });

  test('Landscape contain fit excludes vertical letterboxing', () {
    expect(landscape.pageBounds, const Rect.fromLTWH(0, 100, 400, 200));
    expect(
      landscape.selectionFromDrag(
        const Offset(100, 50),
        const Offset(200, 200),
      ),
      isNull,
    );
    closeRect(
      landscape
          .selectionFromDrag(const Offset(40, 120), const Offset(320, 260))!
          .rect,
      const Rect.fromLTRB(.1, .1, .8, .8),
    );
  });

  test('Maps visible drag into normalized page coordinates', () {
    closeRect(
      portrait
          .selectionFromDrag(const Offset(120, 40), const Offset(240, 320))!
          .rect,
      const Rect.fromLTRB(.1, .1, .7, .8),
    );
  });

  test('Reverse-direction drags yield the same ordered region', () {
    final a = portrait.selectionFromDrag(
      const Offset(120, 40),
      const Offset(240, 320),
    );
    final b = portrait.selectionFromDrag(
      const Offset(240, 320),
      const Offset(120, 40),
    );
    expect(a, b);
  });

  test('An inside start and outside end clamp to the page edges', () {
    closeRect(
      portrait
          .selectionFromDrag(const Offset(140, 80), const Offset(900, 900))!
          .rect,
      const Rect.fromLTRB(.2, .2, 1, 1),
    );
    closeRect(
      portrait
          .selectionFromDrag(const Offset(140, 80), const Offset(-100, -100))!
          .rect,
      const Rect.fromLTRB(0, 0, .2, .2),
    );
  });

  for (final viewport in [
    const Size(200, 400),
    const Size(400, 800),
    const Size(400, 400),
    const Size(800, 300),
    const Size(312, 220),
  ]) {
    test('Round-trip mapping is invariant at viewport $viewport', () {
      final geometry = PdfSelectionGeometry(
        viewport: viewport,
        pageSize: const Size(360, 640),
      );
      const normalized = Rect.fromLTRB(.15, .25, .75, .8);
      final visible = geometry.toVisible(normalized);
      closeRect(
        geometry.selectionFromDrag(visible.topLeft, visible.bottomRight)!.rect,
        normalized,
      );
    });
  }

  test('Portrait and native rotated landscape rasters use displayed top-left coordinates', () {
    for (final size in [const Size(360, 640), const Size(640, 360)]) {
      final geometry = PdfSelectionGeometry(
        viewport: const Size(312, 220),
        pageSize: size,
      );
      const expected = Rect.fromLTRB(.2, .3, .8, .7);
      final visible = geometry.toVisible(expected);
      closeRect(
        geometry.selectionFromDrag(visible.topLeft, visible.bottomRight)!.rect,
        expected,
      );
    }
  });

  test('Zero-area and one-dimensional drags cannot become selections', () {
    for (final end in [
      const Offset(150, 100),
      const Offset(150, 200),
      const Offset(200, 100),
    ]) {
      expect(portrait.selectionFromDrag(const Offset(150, 100), end), isNull);
    }
  });

  test('Visible extents below eight logical pixels are rejected', () {
    expect(
      portrait.selectionFromDrag(
        const Offset(150, 100),
        const Offset(157, 108),
      ),
      isNull,
    );
    expect(
      portrait.selectionFromDrag(
        const Offset(150, 100),
        const Offset(158, 108),
      ),
      isNotNull,
    );
  });

  test('Two-percent normalized minimum also applies on very large views', () {
    final geometry = PdfSelectionGeometry(
      viewport: const Size(1000, 1000),
      pageSize: const Size(1000, 1000),
    );
    expect(
      geometry.selectionFromDrag(
        const Offset(100, 100),
        const Offset(110, 140),
      ),
      isNull,
    );
    expect(
      geometry.selectionFromDrag(
        const Offset(100, 100),
        const Offset(130, 140),
      ),
      isNotNull,
    );
  });

  for (final invalid in [
    const Rect.fromLTRB(-.1, 0, .5, .5),
    const Rect.fromLTRB(0, -.1, .5, .5),
    const Rect.fromLTRB(0, 0, 1.1, .5),
    const Rect.fromLTRB(0, 0, .5, 1.1),
    const Rect.fromLTRB(.8, .2, .3, .7),
    const Rect.fromLTRB(.1, .1, .1, .8),
    const Rect.fromLTRB(double.nan, 0, 1, 1),
    const Rect.fromLTRB(0, 0, double.infinity, 1),
  ]) {
    test('Normalized model rejects invalid rectangle $invalid', () {
      expect(PdfNormalizedRect.tryCreate(invalid), isNull);
    });
  }

  test('Invalid geometry and non-finite pointer positions are rejected', () {
    for (final size in [
      Size.zero,
      const Size(-1, 20),
      const Size(double.infinity, 20),
    ]) {
      final geometry = PdfSelectionGeometry(
        viewport: size,
        pageSize: const Size(100, 200),
      );
      expect(geometry.pageBounds, Rect.zero);
      expect(geometry.dragRect(Offset.zero, const Offset(20, 20)), isNull);
      expect(
        PdfSelectionGeometry(
          viewport: const Size(100, 200),
          pageSize: size,
        ).pageBounds,
        Rect.zero,
      );
    }
    expect(
      portrait.dragRect(const Offset(150, 100), const Offset(double.nan, 50)),
      isNull,
    );
  });
}

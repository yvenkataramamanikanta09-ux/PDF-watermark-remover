"""Geometry-only tests: no PDF parser, renderer, or fixtures are needed."""

from dataclasses import FrozenInstanceError
import hashlib
import json
import math
import unittest

from pdf_watermark_engine.geometry import (
    GeometryError,
    NormalizedRect,
    PageGeometry,
    geometry_digest,
    normalized_to_pdf,
    pdf_to_normalized,
    validate_raster,
)


class GeometryTests(unittest.TestCase):
    def geometry(self, rotation=0, **overrides):
        values = dict(page_number=1, media_box=(10, -20, 210, 80),
                      crop_box=(20, -10, 180, 70), rotation=rotation)
        values.update(overrides)
        return PageGeometry(**values)

    def assertCoordinates(self, actual, expected):
        for value, target in zip(actual, expected):
            self.assertAlmostEqual(value, target, places=10)

    def assertRect(self, actual, expected):
        self.assertCoordinates(
            (actual.left, actual.top, actual.right, actual.bottom), expected,
        )

    def test_all_clockwise_rotations_have_hard_coded_coordinates(self):
        rect = NormalizedRect(.1, .2, .6, .7)
        expected = {
            0: (30, 10, 130, 60),
            90: (50, -10, 150, 40),
            180: (90, 0, 190, 50),
            270: (70, 20, 170, 70),
        }
        for rotation, pdf_rect in expected.items():
            with self.subTest(rotation=rotation):
                page = self.geometry(rotation)
                self.assertCoordinates(
                    normalized_to_pdf(page, rect, render_box="mediaBox"), pdf_rect,
                )
                self.assertRect(
                    pdf_to_normalized(page, pdf_rect, render_box="mediaBox"),
                    (.1, .2, .6, .7),
                )

    def test_crop_box_and_negative_origin(self):
        rect = NormalizedRect(.1, .2, .6, .8)
        self.assertCoordinates(
            normalized_to_pdf(self.geometry(), rect, render_box="cropBox"),
            (36, 6, 116, 54),
        )
        page = self.geometry(media_box=(-600, -800, 0, 0),
                             crop_box=(-550, -700, -50, -50))
        self.assertCoordinates(
            normalized_to_pdf(page, rect, render_box="cropBox"),
            (-500, -570, -250, -180),
        )

    def test_user_unit_does_not_scale_raw_pdf_coordinates(self):
        rect = NormalizedRect(.1, .2, .6, .8)
        for rotation in (0, 90, 180, 270):
            self.assertEqual(
                normalized_to_pdf(self.geometry(rotation), rect, render_box="cropBox"),
                normalized_to_pdf(self.geometry(rotation, user_unit=2.5), rect,
                                  render_box="cropBox"),
            )

    def test_roundtrip_all_rotations_and_boxes(self):
        rectangles = ((0, 0, 1, 1), (.17, .23, .73, .89),
                      (.5, .5, .52, .52), (0, .4, .02, 1))
        for rotation in (0, 90, 180, 270):
            for box in ("cropBox", "mediaBox"):
                for coordinates in rectangles:
                    with self.subTest(rotation=rotation, box=box, rect=coordinates):
                        page = self.geometry(rotation)
                        rect = NormalizedRect(*coordinates)
                        pdf_rect = normalized_to_pdf(page, rect, render_box=box)
                        self.assertRect(pdf_to_normalized(page, pdf_rect,
                                                         render_box=box), coordinates)

    def test_full_page_maps_to_selected_box(self):
        for rotation in (0, 90, 180, 270):
            page = self.geometry(rotation)
            for box, expected in (("cropBox", page.crop_box),
                                  ("mediaBox", page.media_box)):
                self.assertEqual(normalized_to_pdf(
                    page, NormalizedRect(0, 0, 1, 1), render_box=box,
                ), expected)

    def test_rotation_normalizes_exact_multiples(self):
        for supplied, expected in ((-90, 270), (360, 0), (450, 90), (90.0, 90),
                                   (90 * 10 ** 100 + 90, 90)):
            with self.subTest(rotation=supplied):
                self.assertEqual(self.geometry(supplied).rotation, expected)

    def test_invalid_rotations(self):
        for rotation in (1, 45, 90.0000000001, 89.9999999999,
                         math.inf, math.nan, True, "90", None,
                         90 * 10 ** 100 + 1):
            with self.subTest(rotation=rotation):
                with self.assertRaises(GeometryError):
                    self.geometry(rotation)

    def test_invalid_page_boxes(self):
        bad_boxes = ((0, 0, 0, 100), (0, 0, 100, 0), (100, 0, 0, 100),
                     (0, 100, 100, 0), (0, 0, math.inf, 100),
                     (0, math.nan, 100, 100), (0, 0, 100), "0,0,100,100",
                     (False, 0, 100, 100), None)
        for field in ("media_box", "crop_box"):
            for box in bad_boxes:
                with self.subTest(field=field, box=box):
                    with self.assertRaises(GeometryError):
                        self.geometry(**{field: box})

    def test_crop_must_be_fully_inside_media(self):
        for box in ((9, -10, 180, 70), (20, -21, 180, 70),
                    (20, -10, 211, 70), (20, -10, 180, 81)):
            with self.subTest(box=box):
                with self.assertRaises(GeometryError):
                    self.geometry(crop_box=box)

    def test_invalid_page_number_user_unit_and_dimension_limit(self):
        for page_number in (0, -1, 1.0, True, "1", None):
            with self.subTest(page_number=page_number):
                with self.assertRaises(GeometryError):
                    self.geometry(page_number=page_number)
        for unit in (0, -1, math.inf, math.nan, True, "1", None):
            with self.subTest(user_unit=unit):
                with self.assertRaises(GeometryError):
                    self.geometry(user_unit=unit)
        with self.assertRaises(GeometryError):
            self.geometry(media_box=(0, 0, 1_000_001, 100),
                          crop_box=(0, 0, 100, 100))
        with self.assertRaises(GeometryError):
            self.geometry(user_unit=10_000)

    def test_invalid_normalized_rectangles(self):
        bad = ((-.01, 0, .5, .5), (0, 0, 1.01, .5), (0, -.01, .5, .5),
               (0, 0, .5, 1.01), (.5, 0, .5, .5), (.6, 0, .5, .5),
               (0, .6, .5, .5), (0, 0, .019, .5), (0, 0, .5, .019),
               (math.nan, 0, .5, .5), (0, 0, math.inf, .5),
               (True, 0, 1, 1), ("0", 0, 1, 1))
        for coordinates in bad:
            with self.subTest(rect=coordinates):
                with self.assertRaises(GeometryError):
                    NormalizedRect(*coordinates)

    def test_minimum_extent_tolerates_binary_rounding(self):
        self.assertLess(.52 - .5, .02 + 1e-15)
        NormalizedRect(.5, .5, .52, .52)
        with self.assertRaises(GeometryError):
            NormalizedRect(.5, .5, .519999, .52)

    def test_render_box_is_explicit_and_unambiguous(self):
        page, rect = self.geometry(), NormalizedRect(0, 0, 1, 1)
        with self.assertRaises(TypeError):
            normalized_to_pdf(page, rect)
        with self.assertRaises(TypeError):
            pdf_to_normalized(page, page.crop_box)
        with self.assertRaises(TypeError):
            validate_raster(page, raster_width=200, raster_height=100)
        for box in (None, "", "auto", "crop", "cropbox", "CropBox", "media", True):
            with self.subTest(box=box):
                for operation in (
                    lambda: normalized_to_pdf(page, rect, render_box=box),
                    lambda: pdf_to_normalized(page, page.crop_box, render_box=box),
                    lambda: validate_raster(page, render_box=box,
                                            raster_width=200, raster_height=100),
                ):
                    with self.assertRaises(GeometryError):
                        operation()

    def test_inverse_rejects_malformed_or_outside_rectangles(self):
        bad = ((19, 0, 100, 50), (30, -11, 100, 50), (30, 0, 181, 50),
               (30, 0, 100, 71), (30, 0, 30, 50), (30, 0, 100),
               (30, 0, math.inf, 50), (30, math.nan, 100, 50),
               (30, 0, 31, 1), None)
        for rect in bad:
            with self.subTest(rect=rect):
                with self.assertRaises(GeometryError):
                    pdf_to_normalized(self.geometry(), rect, render_box="cropBox")

    def test_geometry_and_rect_are_frozen(self):
        with self.assertRaises(FrozenInstanceError):
            self.geometry().rotation = 90
        with self.assertRaises(FrozenInstanceError):
            NormalizedRect(0, 0, 1, 1).left = .1

    def test_digest_is_canonical_and_sensitive_to_all_metadata(self):
        page = self.geometry()
        expected_json = json.dumps({
            "page_number": 1, "media_box": [10.0, -20.0, 210.0, 80.0],
            "crop_box": [20.0, -10.0, 180.0, 70.0], "rotation": 0,
            "user_unit": 1.0,
        }, sort_keys=True, separators=(",", ":"), allow_nan=False)
        self.assertEqual(geometry_digest(page),
                         hashlib.sha256(expected_json.encode("utf-8")).hexdigest())
        self.assertEqual(geometry_digest(page), geometry_digest(self.geometry(360)))
        variants = (self.geometry(page_number=2), self.geometry(90),
                    self.geometry(user_unit=2), self.geometry(crop_box=(21, -10, 180, 70)),
                    self.geometry(media_box=(9, -20, 210, 80)))
        for variant in variants:
            self.assertNotEqual(geometry_digest(page), geometry_digest(variant))
        self.assertEqual(
            geometry_digest(self.geometry(media_box=(-0.0, -20, 210, 80))),
            geometry_digest(self.geometry(media_box=(0, -20, 210, 80))),
        )

    def test_raster_aspect_uses_rotation_and_selected_box(self):
        for rotation in (0, 90, 180, 270):
            page = self.geometry(rotation, user_unit=2)
            width, height = (200, 100) if rotation in (0, 180) else (100, 200)
            validate_raster(page, render_box="mediaBox",
                            raster_width=width, raster_height=height)
            crop_width, crop_height = ((160, 80) if rotation in (0, 180)
                                       else (80, 160))
            validate_raster(page, render_box="cropBox", raster_width=crop_width,
                            raster_height=crop_height)
        page = self.geometry(crop_box=(20, -10, 100, 70))
        validate_raster(page, render_box="cropBox", raster_width=100, raster_height=100)
        with self.assertRaises(GeometryError):
            validate_raster(page, render_box="mediaBox", raster_width=100,
                            raster_height=100)

    def test_raster_allows_two_pixel_rounding(self):
        validate_raster(self.geometry(), render_box="mediaBox",
                        raster_width=16_384, raster_height=8192)
        validate_raster(self.geometry(), render_box="mediaBox",
                        raster_width=401, raster_height=202)
        validate_raster(self.geometry(90), render_box="mediaBox",
                        raster_width=202, raster_height=400)
        with self.assertRaises(GeometryError):
            validate_raster(self.geometry(), render_box="mediaBox",
                            raster_width=400, raster_height=203)

    def test_invalid_raster_dimensions_and_aspect(self):
        for value in (0, -1, 16_385, 100.0, True, math.inf, math.nan, "100", None):
            for field in ("raster_width", "raster_height"):
                arguments = dict(raster_width=200, raster_height=100)
                arguments[field] = value
                with self.subTest(field=field, value=value):
                    with self.assertRaises(GeometryError):
                        validate_raster(self.geometry(), render_box="mediaBox", **arguments)
        for rotation in (0, 90, 180, 270):
            with self.subTest(rotation=rotation):
                with self.assertRaises(GeometryError):
                    validate_raster(self.geometry(rotation), render_box="mediaBox",
                                    raster_width=200, raster_height=200)


if __name__ == "__main__":
    unittest.main()

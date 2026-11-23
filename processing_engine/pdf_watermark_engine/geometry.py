"""Pure coordinate conversions between a rendered page and raw PDF user units.

The normalized rectangle uses the top-left of the *rotated, rendered* page as
its origin. The caller must identify whether that renderer used CropBox or
MediaBox; there is deliberately no implicit box selection. ``UserUnit`` is a
uniform physical scale and does not alter returned raw PDF coordinates.
"""

from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
import math
from numbers import Real
from typing import Sequence


# Bound both raw and physical dimensions to avoid nonsensical page metadata.
MAX_PAGE_DIMENSION = 1_000_000.0
MAX_RASTER_DIMENSION = 16_384
MIN_NORMALIZED_EXTENT = 0.02
_EXTENT_TOLERANCE = 1e-12
_RASTER_PIXEL_TOLERANCE = 2.0


class GeometryError(ValueError):
    """The supplied page, rectangle, or render dimensions are invalid."""


def _finite_number(value: object, label: str) -> float:
    if isinstance(value, bool) or not isinstance(value, Real):
        raise GeometryError(f"{label} must be a finite number")
    try:
        result = float(value)
    except (OverflowError, TypeError, ValueError) as exc:
        raise GeometryError(f"{label} must be a finite number") from exc
    if not math.isfinite(result):
        raise GeometryError(f"{label} must be a finite number")
    # Give semantically identical metadata a stable digest, including -0.0.
    return 0.0 if result == 0.0 else result


def _ordered_box(value: object, label: str) -> tuple[float, float, float, float]:
    if isinstance(value, (str, bytes)) or not isinstance(value, Sequence):
        raise GeometryError(f"{label} must contain four coordinates")
    if len(value) != 4:
        raise GeometryError(f"{label} must contain four coordinates")
    box = tuple(_finite_number(item, f"{label}[{index}]")
                for index, item in enumerate(value))
    left, bottom, right, top = box
    if left >= right or bottom >= top:
        raise GeometryError(f"{label} must have positive width and height")
    return box


@dataclass(frozen=True)
class PageGeometry:
    """Validated metadata for one PDF page; ``page_number`` is one-based."""

    page_number: int
    media_box: tuple[float, float, float, float]
    crop_box: tuple[float, float, float, float]
    rotation: int
    user_unit: float = 1.0

    def __post_init__(self) -> None:
        if (isinstance(self.page_number, bool)
                or not isinstance(self.page_number, int)
                or self.page_number < 1):
            raise GeometryError("page_number must be a positive integer")
        media_box = _ordered_box(self.media_box, "media_box")
        crop_box = _ordered_box(self.crop_box, "crop_box")
        if (crop_box[0] < media_box[0] or crop_box[1] < media_box[1]
                or crop_box[2] > media_box[2] or crop_box[3] > media_box[3]):
            raise GeometryError("crop_box must be fully inside media_box")

        user_unit = _finite_number(self.user_unit, "user_unit")
        if user_unit <= 0:
            raise GeometryError("user_unit must be positive")
        for label, box in (("media_box", media_box), ("crop_box", crop_box)):
            for dimension in (box[2] - box[0], box[3] - box[1]):
                physical_dimension = dimension * user_unit
                if (not math.isfinite(dimension)
                        or dimension > MAX_PAGE_DIMENSION
                        or not math.isfinite(physical_dimension)
                        or physical_dimension > MAX_PAGE_DIMENSION):
                    raise GeometryError(f"{label} dimensions exceed the page limit")

        if isinstance(self.rotation, int) and not isinstance(self.rotation, bool):
            # Preserve exact divisibility for large integers before normalizing.
            rotation = self.rotation
        else:
            number = _finite_number(self.rotation, "rotation")
            rotation = int(number)
            if self.rotation != rotation:
                raise GeometryError("rotation must be an integral multiple of 90")
        if rotation % 90 != 0:
            raise GeometryError("rotation must be an integral multiple of 90")
        object.__setattr__(self, "media_box", media_box)
        object.__setattr__(self, "crop_box", crop_box)
        object.__setattr__(self, "rotation", rotation % 360)
        object.__setattr__(self, "user_unit", user_unit)


@dataclass(frozen=True)
class NormalizedRect:
    """A rendered top-left rectangle in [0, 1], at least 2% on each axis."""

    left: float
    top: float
    right: float
    bottom: float

    def __post_init__(self) -> None:
        for name in ("left", "top", "right", "bottom"):
            value = _finite_number(getattr(self, name), name)
            if not 0.0 <= value <= 1.0:
                raise GeometryError(f"{name} must be within [0, 1]")
            object.__setattr__(self, name, value)
        if self.left >= self.right or self.top >= self.bottom:
            raise GeometryError("rectangle must have positive width and height")
        if (self.right - self.left + _EXTENT_TOLERANCE < MIN_NORMALIZED_EXTENT
                or self.bottom - self.top + _EXTENT_TOLERANCE
                < MIN_NORMALIZED_EXTENT):
            raise GeometryError("rectangle must cover at least 0.02 on each axis")


def _render_box(
    geometry: PageGeometry, render_box: str,
) -> tuple[float, float, float, float]:
    if not isinstance(geometry, PageGeometry):
        raise GeometryError("geometry must be PageGeometry")
    if isinstance(render_box, str) and render_box == "cropBox":
        return geometry.crop_box
    if isinstance(render_box, str) and render_box == "mediaBox":
        return geometry.media_box
    raise GeometryError("render_box must explicitly be 'cropBox' or 'mediaBox'")


def _display_to_unrotated(s: float, t: float, rotation: int) -> tuple[float, float]:
    if rotation == 0:
        return s, t
    if rotation == 90:
        return t, 1.0 - s
    if rotation == 180:
        return 1.0 - s, 1.0 - t
    return 1.0 - t, s  # 270 degrees clockwise


def _unrotated_to_display(u: float, v: float, rotation: int) -> tuple[float, float]:
    if rotation == 0:
        return u, v
    if rotation == 90:
        return 1.0 - v, u
    if rotation == 180:
        return 1.0 - u, 1.0 - v
    return v, 1.0 - u  # 270 degrees clockwise


def normalized_to_pdf(
    geometry: PageGeometry,
    rect: NormalizedRect,
    *,
    render_box: str,
) -> tuple[float, float, float, float]:
    """Return raw PDF (left, bottom, right, top) for a rendered rectangle."""
    x0, y0, x1, y1 = _render_box(geometry, render_box)
    if not isinstance(rect, NormalizedRect):
        raise GeometryError("rect must be NormalizedRect")
    width, height = x1 - x0, y1 - y0
    points = []
    for s, t in ((rect.left, rect.top), (rect.right, rect.top),
                 (rect.right, rect.bottom), (rect.left, rect.bottom)):
        u, v = _display_to_unrotated(s, t, geometry.rotation)
        # Clamp arithmetic at exact box edges to keep full-page conversions in box.
        x = min(x1, max(x0, x0 + u * width))
        y = min(y1, max(y0, y1 - v * height))
        points.append((x, y))
    return (min(point[0] for point in points),
            min(point[1] for point in points),
            max(point[0] for point in points),
            max(point[1] for point in points))


def pdf_to_normalized(
    geometry: PageGeometry,
    pdf_rect: tuple[float, float, float, float],
    *,
    render_box: str,
) -> NormalizedRect:
    """Invert a within-box raw PDF rectangle, preserving the 2% minimum extent."""
    x0, y0, x1, y1 = _render_box(geometry, render_box)
    left, bottom, right, top = _ordered_box(pdf_rect, "pdf_rect")
    if left < x0 or bottom < y0 or right > x1 or top > y1:
        raise GeometryError("pdf_rect must be fully inside the render_box")
    width, height = x1 - x0, y1 - y0
    points = []
    for x, y in ((left, bottom), (left, top), (right, bottom), (right, top)):
        u, v = (x - x0) / width, (y1 - y) / height
        points.append(_unrotated_to_display(u, v, geometry.rotation))
    # Division at the boundary can move a coordinate by an ulp. The preceding
    # raw-box containment check ensures this clamp cannot accept an outside rect.
    return NormalizedRect(
        min(1.0, max(0.0, min(point[0] for point in points))),
        min(1.0, max(0.0, min(point[1] for point in points))),
        min(1.0, max(0.0, max(point[0] for point in points))),
        min(1.0, max(0.0, max(point[1] for point in points))),
    )


def effective_crop_box(media_box, crop_box) -> tuple[float, float, float, float]:
    """PDF semantics: the visible crop box is its intersection with the media box.

    Both inputs are raw ``(x0, y0, x1, y1)`` boxes in any corner order. An empty
    intersection is an invalid page and raises ``GeometryError``.
    """
    media = _normalized_corners(media_box, "media_box")
    crop = _normalized_corners(crop_box, "crop_box")
    box = (max(media[0], crop[0]), max(media[1], crop[1]),
           min(media[2], crop[2]), min(media[3], crop[3]))
    if box[0] >= box[2] or box[1] >= box[3]:
        raise GeometryError("crop_box does not intersect media_box")
    return box


def _normalized_corners(value, label) -> tuple[float, float, float, float]:
    if isinstance(value, (str, bytes)) or not isinstance(value, Sequence) or len(value) != 4:
        raise GeometryError(f"{label} must contain four coordinates")
    x0, y0, x1, y1 = (_finite_number(item, f"{label}[{index}]") for index, item in enumerate(value))
    return min(x0, x1), min(y0, y1), max(x0, x1), max(y0, y1)


def pdf_rect_to_unit(
    geometry: PageGeometry,
    pdf_rect: tuple[float, float, float, float],
    *,
    render_box: str,
) -> tuple[float, float, float, float] | None:
    """Map any raw PDF rectangle to rendered top-left unit coordinates.

    Unlike :func:`pdf_to_normalized`, the rectangle is clipped to the render box
    and no minimum extent applies. Returns ``(left, top, right, bottom)`` in
    ``[0, 1]`` or ``None`` when nothing of the rectangle is visible.
    """
    x0, y0, x1, y1 = _render_box(geometry, render_box)
    left, bottom, right, top = _normalized_corners(pdf_rect, "pdf_rect")
    left, bottom = max(left, x0), max(bottom, y0)
    right, top = min(right, x1), min(top, y1)
    if left > right or bottom > top:
        return None
    width, height = x1 - x0, y1 - y0
    points = [_unrotated_to_display((x - x0) / width, (y1 - y) / height, geometry.rotation)
              for x, y in ((left, bottom), (left, top), (right, bottom), (right, top))]
    return (min(1.0, max(0.0, min(point[0] for point in points))),
            min(1.0, max(0.0, min(point[1] for point in points))),
            min(1.0, max(0.0, max(point[0] for point in points))),
            min(1.0, max(0.0, max(point[1] for point in points))))


def geometry_digest(geometry: PageGeometry) -> str:
    """SHA256 of canonical JSON for all validated page geometry metadata."""
    if not isinstance(geometry, PageGeometry):
        raise GeometryError("geometry must be PageGeometry")
    metadata = {
        "page_number": geometry.page_number,
        "media_box": geometry.media_box,
        "crop_box": geometry.crop_box,
        "rotation": geometry.rotation,
        "user_unit": geometry.user_unit,
    }
    encoded = json.dumps(metadata, sort_keys=True, separators=(",", ":"),
                         allow_nan=False).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def validate_raster(
    geometry: PageGeometry,
    *,
    render_box: str,
    raster_width: int,
    raster_height: int,
) -> None:
    """Check raster bounds and rotated aspect ratio, allowing two rounded pixels.

    The aspect error is measured on the shorter image axis. That allows the
    normal rounding of either dimension without magnifying it on a long page.
    """
    x0, y0, x1, y1 = _render_box(geometry, render_box)
    for label, value in (("raster_width", raster_width),
                         ("raster_height", raster_height)):
        if (isinstance(value, bool) or not isinstance(value, int)
                or not 1 <= value <= MAX_RASTER_DIMENSION):
            raise GeometryError(
                f"{label} must be an integer in [1, {MAX_RASTER_DIMENSION}]"
            )
    display_width, display_height = x1 - x0, y1 - y0
    if geometry.rotation in (90, 270):
        display_width, display_height = display_height, display_width
    if display_width >= display_height:
        pixel_error = abs(raster_height - raster_width * display_height / display_width)
    else:
        pixel_error = abs(raster_width - raster_height * display_width / display_height)
    if pixel_error > _RASTER_PIXEL_TOLERANCE + _EXTENT_TOLERANCE:
        raise GeometryError("raster aspect ratio does not match the rotated render_box")

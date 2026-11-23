"""Independent PDFium readability/geometry checks, rendering and page objects."""
from __future__ import annotations

from contextlib import closing
import ctypes
from dataclasses import dataclass
import hashlib
import math

import pypdfium2 as pdfium
import pypdfium2.raw as pdfium_c

from .geometry import GeometryError, effective_crop_box
from .models import EngineFailure, Outcome


def pdfium_crop_box(page):
    """The box PDFium displays: crop box intersected with the media box.

    ``FPDF_GetPageBoundingBox`` honours boxes inherited from ``/Pages`` nodes,
    unlike ``FPDFPage_GetMediaBox``/``GetCropBox``, which read only the page
    dictionary (pypdfium2 then silently falls back to US Letter).
    """
    rect = pdfium_c.FS_RECTF()
    if not pdfium_c.FPDF_GetPageBoundingBox(page, rect):
        raise EngineFailure(Outcome.INVALID_PDF, "independent_page_box_mismatch")
    try:
        return effective_crop_box((rect.left, rect.bottom, rect.right, rect.top),
                                  (rect.left, rect.bottom, rect.right, rect.top))
    except GeometryError:
        raise EngineFailure(Outcome.INVALID_PDF, "independent_page_box_mismatch") from None


def _explicit_media_box(page):
    values = [ctypes.c_float() for _ in range(4)]
    if not pdfium_c.FPDFPage_GetMediaBox(page, *values):
        return None  # Inherited: covered by the displayed-box comparison.
    left, bottom, right, top = (value.value for value in values)
    return min(left, right), min(bottom, top), max(left, right), max(bottom, top)


def check_page_geometry(page, geometry):
    comparisons = [(pdfium_crop_box(page), geometry.crop_box)]
    media = _explicit_media_box(page)
    if media is not None:
        comparisons.append((media, geometry.media_box))
    for actual, expected in comparisons:
        if any(abs(a - b) > max(1e-3, abs(b) * 1e-6) for a, b in zip(actual, expected)):
            raise EngineFailure(Outcome.INVALID_PDF, "independent_page_box_mismatch")
    if page.get_rotation() != geometry.rotation:
        raise EngineFailure(Outcome.INVALID_PDF, "independent_rotation_mismatch")


def verify_render(path, geometries, limits):
    hashes = []
    try:
        with pdfium.PdfDocument(path) as document:
            if len(document) != len(geometries):
                raise EngineFailure(Outcome.INVALID_PDF, "independent_page_count_mismatch")
            for index, geometry in enumerate(geometries):
                with closing(document[index]) as page:
                    check_page_geometry(page, geometry)
                    width, height = page.get_size()
                    if not all(math.isfinite(value) and value > 0 for value in (width, height)):
                        raise EngineFailure(Outcome.INVALID_PDF, "independent_invalid_page_size")
                    scale = limits.render_long_edge / max(width, height)
                    # No init_forms, JavaScript, document actions, or link execution.
                    # The structural graph separately validates retained annotations.
                    with closing(page.render(scale=scale, draw_annots=False, may_draw_forms=False,
                                     rev_byteorder=True, force_bitmap_format=pdfium.raw.FPDFBitmap_BGRA,
                                     fill_color=(255, 255, 255, 255))) as bitmap:
                        if bitmap.width * bitmap.height > (limits.render_long_edge + 2) ** 2:
                            raise EngineFailure(Outcome.FAILED, "independent_raster_limit")
                        hashes.append(hashlib.sha256(bytes(bitmap.buffer)).hexdigest())
        return hashes
    except EngineFailure:
        raise
    except (MemoryError, RecursionError):
        raise
    except Exception:
        raise EngineFailure(Outcome.INVALID_PDF, "independent_renderer_unreadable") from None


def render_size(page, long_edge: int) -> tuple[int, int]:
    """Raster size of the displayed (cropped, rotated) page with an exact long edge."""
    width = pdfium_c.FPDF_GetPageWidthF(page)
    height = pdfium_c.FPDF_GetPageHeightF(page)
    if not all(math.isfinite(value) and value > 0 for value in (width, height)):
        raise EngineFailure(Outcome.INVALID_PDF, "independent_invalid_page_size")
    if width >= height:
        return long_edge, max(1, round(height * long_edge / width))
    return max(1, round(width * long_edge / height)), long_edge


def render_image(page, size: tuple[int, int], *, annotations: bool = True):
    """Render onto white at an exact size; page rotation and crop box applied.

    No forms environment is initialized, so no JavaScript or form actions run.
    Annotation appearance streams are drawn when ``annotations`` is true.
    """
    width, height = size
    bitmap = pdfium.PdfBitmap.new_native(width, height, pdfium_c.FPDFBitmap_BGR)
    try:
        pdfium_c.FPDFBitmap_FillRect(bitmap, 0, 0, width, height, 0xFFFFFFFF)
        flags = pdfium_c.FPDF_ANNOT if annotations else 0
        pdfium_c.FPDF_RenderPageBitmap(bitmap, page, 0, 0, width, height, 0, flags)
        return bitmap.to_pil().convert("RGB")
    finally:
        bitmap.close()


@dataclass(frozen=True)
class PageObjectInfo:
    type: int
    bounds: tuple[float, float, float, float] | None
    marks: int
    artifact_hint: bool
    text_mode: int | None


def _wide(function, *arguments) -> str:
    size = ctypes.c_ulong()
    if not function(*arguments, None, 0, ctypes.byref(size)) or size.value < 2:
        return ""
    buffer = ctypes.create_string_buffer(size.value)
    function(*arguments, ctypes.cast(buffer, ctypes.POINTER(ctypes.c_ushort)), size.value, ctypes.byref(size))
    return buffer.raw[:size.value].decode("utf-16-le", "replace").rstrip("\x00")


def _bounds(handle):
    left, bottom, right, top = (ctypes.c_float() for _ in range(4))
    if not pdfium_c.FPDFPageObj_GetBounds(handle, left, bottom, right, top):
        return None
    values = (left.value, bottom.value, right.value, top.value)
    return values if all(math.isfinite(value) for value in values) else None


def page_objects(page) -> list[PageObjectInfo]:
    """Top-level PDFium page objects in content order."""
    result = []
    for index in range(pdfium_c.FPDFPage_CountObjects(page)):
        handle = pdfium_c.FPDFPage_GetObject(page, index)
        kind = pdfium_c.FPDFPageObj_GetType(handle)
        marks = pdfium_c.FPDFPageObj_CountMarks(handle)
        hint = False
        for number in range(max(0, marks)):
            mark = pdfium_c.FPDFPageObj_GetMark(handle, number)
            if (_wide(pdfium_c.FPDFPageObjMark_GetName, mark) == "Artifact" and
                    pdfium_c.FPDFPageObjMark_GetParamValueType(mark, b"Subtype") == pdfium_c.FPDF_OBJECT_NAME):
                hint = True
        mode = pdfium_c.FPDFTextObj_GetTextRenderMode(handle) if kind == pdfium_c.FPDF_PAGEOBJ_TEXT else None
        result.append(PageObjectInfo(kind, _bounds(handle), marks, hint, mode))
    return result


def text_characters(page) -> list[tuple[int, tuple[float, float, float, float]]]:
    """Non-generated text-page characters with tight boxes (left, bottom, right, top)."""
    characters = []
    with closing(page.get_textpage()) as text:
        for index in range(pdfium_c.FPDFText_CountChars(text)):
            if pdfium_c.FPDFText_IsGenerated(text, index) == 1:
                continue
            left, right, bottom, top = (ctypes.c_double() for _ in range(4))
            if not pdfium_c.FPDFText_GetCharBox(text, index, left, right, bottom, top):
                continue
            characters.append((pdfium_c.FPDFText_GetUnicode(text, index),
                               (left.value, bottom.value, right.value, top.value)))
    return characters

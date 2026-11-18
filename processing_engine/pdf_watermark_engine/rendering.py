"""Independent PDFium readability/geometry and unchanged base-content checks."""
from __future__ import annotations

import hashlib
import math
from contextlib import closing

import pypdfium2 as pdfium

from .models import EngineFailure, Outcome


def verify_render(path, geometries, limits):
    hashes = []
    try:
        with pdfium.PdfDocument(path) as document:
            if len(document) != len(geometries):
                raise EngineFailure(Outcome.INVALID_PDF, "independent_page_count_mismatch")
            for index, geometry in enumerate(geometries):
                with closing(document[index]) as page:
                    for actual, expected in ((page.get_mediabox(), geometry.media_box),
                                             (page.get_cropbox(), geometry.crop_box)):
                        if any(abs(a - b) > 1e-3 for a, b in zip(actual, expected)):
                            raise EngineFailure(Outcome.INVALID_PDF, "independent_page_box_mismatch")
                    if page.get_rotation() != geometry.rotation:
                        raise EngineFailure(Outcome.INVALID_PDF, "independent_rotation_mismatch")
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

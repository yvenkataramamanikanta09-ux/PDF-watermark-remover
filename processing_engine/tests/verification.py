"""Independent PDFium observations and pypdf structural evidence for fixtures."""
from contextlib import closing
import hashlib

import pypdfium2 as pdfium
from pypdf import PdfReader


def sha256(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def observations(path, *, annotations=True):
    result = []
    with pdfium.PdfDocument(path) as document:
        for index in range(len(document)):
            with closing(document[index]) as page:
                kinds = []
                for number in range(pdfium.raw.FPDFPage_GetAnnotCount(page)):
                    annotation = pdfium.raw.FPDFPage_GetAnnot(page, number)
                    try:
                        kinds.append(pdfium.raw.FPDFAnnot_GetSubtype(annotation))
                    finally:
                        pdfium.raw.FPDFPage_CloseAnnot(annotation)
                with closing(page.get_textpage()) as text:
                    extracted = text.get_text_bounded()
                with closing(page.render(scale=1, draw_annots=annotations,
                                         may_draw_forms=False, rev_byteorder=True,
                                         force_bitmap_format=pdfium.raw.FPDFBitmap_BGRA)) as bitmap:
                    result.append({"pixels": hashlib.sha256(bytes(bitmap.buffer)).hexdigest(),
                                   "size": (bitmap.width, bitmap.height), "text": extracted,
                                   "annotation_types": kinds, "rotation": page.get_rotation(),
                                   "media_box": page.get_mediabox(), "crop_box": page.get_cropbox()})
    return result


def structure(path):
    with PdfReader(path, strict=True) as reader:
        return [{"content": page.get_contents().get_data(),
                 "image": page["/Resources"]["/XObject"]["/Im1"].get_data(),
                 "annotations": [
                     (str(item.get_object()["/Subtype"]), str(item.get_object().get("/NM")),
                      str(item.get_object().get("/Contents")),
                      str(item.get_object().get("/A", {}).get("/URI")))
                     for item in page["/Annots"]
                     if item.get_object()["/Subtype"] != "/Watermark"]}
                for page in reader.pages]

from __future__ import annotations

from dataclasses import dataclass
import hashlib
import math

from pypdf.generic import (ArrayObject, ContentStream, DictionaryObject,
                           FloatObject, IndirectObject, NameObject, NumberObject, StreamObject)

from .document import reference_key, resolve


@dataclass(frozen=True)
class Candidate:
    page_number: int
    index: int
    reference: tuple[int, int] | None
    subtype: str
    rect: tuple[float, float, float, float] | None
    supported: bool
    reason: str
    candidate_id: str

    def report(self):
        return {"candidate_id": self.candidate_id, "page_number": self.page_number,
                "subtype": self.subtype, "pdf_user_space_rect": self.rect,
                "supported": self.supported, "reason": self.reason}


def numbers(value, count):
    value = resolve(value)
    if not isinstance(value, ArrayObject) or len(value) != count:
        return None
    if any(not isinstance(resolve(item), (NumberObject, FloatObject)) for item in value):
        return None
    try:
        result = tuple(float(resolve(item)) for item in value)
    except (TypeError, ValueError, OverflowError):
        return None
    return result if all(math.isfinite(item) for item in result) else None


def contains(outer, inner):
    return all((inner[0] >= outer[0] - 1e-7, inner[1] >= outer[1] - 1e-7,
                inner[2] <= outer[2] + 1e-7, inner[3] <= outer[3] + 1e-7))


def scan(reader, geometries, graph, revision, limits):
    candidates = []
    for page_index, page in enumerate(reader.pages):
        annotations = resolve(page.get("/Annots", ArrayObject()))
        for index, reference in enumerate(annotations):
            annotation = resolve(reference)
            subtype = resolve(annotation.get("/Subtype"))
            stamp_hint = (str(subtype) == "/Stamp" and str(resolve(annotation.get("/Name"))) == "/Watermark")
            if str(subtype) != "/Watermark" and not stamp_hint:
                continue
            key = reference_key(reference)
            rect = numbers(annotation.get("/Rect"), 4)
            reason = "explicit_watermark_annotation"
            if stamp_hint:
                reason = "ambiguous_custom_stamp_name"
            elif not isinstance(subtype, NameObject) or not isinstance(reference, IndirectObject):
                reason = "nonstandard_annotation_reference_or_subtype"
            elif isinstance(annotation, StreamObject) or str(resolve(annotation.get("/Type", NameObject("/Annot")))) != "/Annot":
                reason = "invalid_annotation_type"
            elif rect is None or rect[0] >= rect[2] or rect[1] >= rect[3] or not contains(geometries[page_index].crop_box, rect):
                reason = "unsupported_annotation_rectangle"
            elif any(name in annotation for name in ("/A", "/AA", "/Popup", "/IRT", "/Parent", "/Kids", "/StructParent", "/OC", "/FixedPrint")):
                reason = "interactive_tagged_or_fixed_print_watermark"
            elif (not isinstance(resolve(annotation.get("/F", NumberObject(0))), NumberObject) or
                  resolve(annotation.get("/F", NumberObject(0))) not in (0, 4)):
                reason = "hidden_locked_or_transformed_annotation_flags"
            elif "/P" in annotation and reference_key(annotation.raw_get("/P")) != reference_key(page.indirect_reference):
                reason = "annotation_page_reference_mismatch"
            elif graph.incoming.get(key) != ["/Annots[]"]:
                reason = "shared_or_dependent_annotation_reference"
            else:
                appearance = resolve(annotation.get("/AP"))
                normal = appearance.get("/N") if isinstance(appearance, DictionaryObject) else None
                form = resolve(normal)
                bbox = numbers(form.get("/BBox"), 4) if isinstance(form, StreamObject) else None
                if (not isinstance(normal, IndirectObject) or not isinstance(form, StreamObject) or
                        not isinstance(resolve(form.get("/Subtype")), NameObject) or
                        str(resolve(form.get("/Subtype"))) != "/Form" or bbox is None or
                        bbox[0] >= bbox[2] or bbox[1] >= bbox[3]):
                    reason = "unsupported_normal_appearance"
                elif len(form.get_data()) > limits.max_appearance_bytes:
                    reason = "appearance_size_limit"
                elif not form.get_data() or not ContentStream(form, reader).operations:
                    reason = "empty_normal_appearance"
                elif "/Matrix" in form:
                    matrix = numbers(form.get("/Matrix"), 6)
                    if matrix is None or abs(matrix[0] * matrix[3] - matrix[1] * matrix[2]) < 1e-12:
                        reason = "ambiguous_appearance_matrix"
            supported = reason == "explicit_watermark_annotation"
            identifier = hashlib.sha256(f"{revision}:{page_index + 1}:{key}:{index}".encode()).hexdigest()
            candidates.append(Candidate(page_index + 1, index, key, str(subtype), rect,
                                        supported, reason, identifier))
    return candidates

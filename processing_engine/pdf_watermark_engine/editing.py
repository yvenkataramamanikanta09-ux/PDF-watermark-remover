"""Content-level removal (Acrobat watermark artifacts and selected areas).

Planning uses three independent views of each page that must agree before an
edit is allowed: this package's byte tokenizer/replay (``content.py``), pypdf's
operator parse, and PDFium's page objects (type, marks and bounds). Edits only
splice painting operators out of the original content bytes. Every output is
validated against the source with PDFium renders, PDFium text and a pypdf
object-graph comparison before the caller may publish it.
"""
from __future__ import annotations

from contextlib import closing
from dataclasses import dataclass, field
from pathlib import Path

import pypdfium2 as pdfium
from PIL import ImageChops, ImageDraw
from pypdf import PdfReader
from pypdf.generic import (ArrayObject, DecodedStreamObject, DictionaryObject, IndirectObject,
                           NameObject, NumberObject, StreamObject)

from .annotations import numbers
from .content import (PDFIUM_TYPES, EditError, PageContent, analyze_page, operator_sequence,
                      page_streams, removal_edit, splice, text_dependency_blocked, tokenize)
from .document import Graph, clone_document, load_document, reference_key, resolve, write_pdf
from .geometry import pdf_rect_to_unit
from .models import EngineFailure, Outcome
from .rendering import check_page_geometry, page_objects, render_image, render_size, text_characters

CONTAINMENT_TOLERANCE = 0.5      # PDF points
REGION_DILATION_PIXELS = 2
PIXEL_TOLERANCE = 16             # per-channel delta out of 255
TEXT_POSITION_TOLERANCE = 0.5    # PDF points
HIDDEN_ANNOTATION_FLAGS = 2 | 32  # Hidden, NoView
CLIP_TEXT_MODES = (4, 5, 6, 7)
INVISIBLE_TEXT_MODES = (3, 7)


@dataclass
class Removal:
    kind: str
    bounds: tuple[float, float, float, float] | None
    site: int | None = None
    annotation: int | None = None
    reference: tuple[int, int] | None = None


@dataclass
class PagePlan:
    index: int
    content: PageContent | None = None
    removals: list[Removal] = field(default_factory=list)
    extra_annotations: list[int] = field(default_factory=list)  # e.g. popups of removed stamps
    region: tuple[float, float, float, float] | None = None
    eligible_inside: int = 0
    annotations_inside: int = 0

    @property
    def content_removals(self):
        return [removal for removal in self.removals if removal.site is not None]

    @property
    def annotation_indices(self):
        return {removal.annotation for removal in self.removals if removal.annotation is not None} | set(self.extra_annotations)


def contained(inner, outer, tolerance=CONTAINMENT_TOLERANCE) -> bool:
    return inner is not None and (inner[0] >= outer[0] - tolerance and inner[1] >= outer[1] - tolerance and
                                  inner[2] <= outer[2] + tolerance and inner[3] <= outer[3] + tolerance)


def mapping_error(content: PageContent, objects, page) -> str | None:
    """Return why this page's content/PDFium/pypdf views disagree, or None."""
    if not content.mappable:
        return content.error
    if len(content.sites) != len(objects):
        return "content_object_count_mismatch"
    for site, info in zip(content.sites, objects):
        if PDFIUM_TYPES[site.kind] != info.type or site.mark_depth != info.marks:
            return "content_object_mismatch"
        if site.watermark_artifact and not info.artifact_hint:
            return "content_mark_mismatch"
    try:
        contents = page.get_contents()
        expected = [operator for _, operator in contents.operations] if contents is not None else []
    except Exception:
        return "content_independent_parse_failed"
    if operator_sequence(content.operations) != expected:
        return "content_operator_sequence_mismatch"
    return None


def _removable(content: PageContent, indices, objects, *, allow_invisible: bool):
    """Split site indices into (removable, blocked) with byte edits checked."""
    removable, blocked = set(), set()
    for index in indices:
        site, info = content.sites[index], objects[index]
        if site.kind == "text":
            modes = {site.text_mode, info.text_mode}
            if modes & set(CLIP_TEXT_MODES):
                blocked.add(index)
                continue
            if not allow_invisible and modes & set(INVISIBLE_TEXT_MODES):
                blocked.add(index)
                continue
        try:
            removal_edit(content, site)
        except EditError:
            blocked.add(index)
            continue
        removable.add(index)
    dependent = text_dependency_blocked(content, removable)
    return removable - dependent, blocked | dependent


# --- watermark artifacts -------------------------------------------------------

@dataclass
class ArtifactScan:
    plans: dict[int, PagePlan] = field(default_factory=dict)
    unsupported_pages: dict[int, str] = field(default_factory=dict)

    @property
    def count(self) -> int:
        return sum(len(plan.removals) for plan in self.plans.values())


def scan_artifacts(reader, pdf_path, page_indices, *, restrict=None) -> ArtifactScan:
    """Find removable ``/Artifact <</Subtype /Watermark>>`` page objects.

    ``restrict`` optionally maps page index -> PDF rectangle; only artifact
    objects fully inside it are planned. A page is all-or-nothing: if any of its
    selected artifact objects cannot be removed exactly, nothing is planned there.
    """
    scan = ArtifactScan()
    candidates = {}
    for index in page_indices:
        page = reader.pages[index]
        content = analyze_page(page, require_watermark_hint=True)
        if content.error:
            if any(b"Watermark" in data for data in content.streams) or _properties_mention_watermark(page):
                scan.unsupported_pages[index] = content.error
            continue
        if any(site.watermark_artifact for site in content.sites):
            candidates[index] = content
    if not candidates:
        return scan
    with pdfium.PdfDocument(str(pdf_path)) as document:
        for index, content in candidates.items():
            with closing(document[index]) as pdf_page:
                objects = page_objects(pdf_page)
            error = mapping_error(content, objects, reader.pages[index])
            if error:
                scan.unsupported_pages[index] = error
                continue
            selected = [number for number, site in enumerate(content.sites) if site.watermark_artifact]
            if restrict is not None:
                region = restrict.get(index)
                selected = [number for number in selected
                            if region is not None and contained(objects[number].bounds, region)]
            if not selected:
                continue
            removable, blocked = _removable(content, selected, objects, allow_invisible=True)
            if blocked:
                scan.unsupported_pages[index] = "watermark_artifact_not_separable"
                continue
            plan = PagePlan(index, content)
            plan.removals = [Removal("watermark_artifact", objects[number].bounds, site=number)
                             for number in sorted(removable)]
            scan.plans[index] = plan
    return scan


def _properties_mention_watermark(page) -> bool:
    resources = resolve(page.get("/Resources"))
    properties = resolve(resources.get("/Properties")) if isinstance(resources, DictionaryObject) else None
    if not isinstance(properties, DictionaryObject):
        return False
    return any(str(resolve(resolve(value).get("/Subtype"))) == "/Watermark"
               for value in properties.values() if isinstance(resolve(value), DictionaryObject))


# --- selected area -------------------------------------------------------------------

def plan_area(reader, pdf_path, regions: dict[int, tuple]) -> tuple[dict[int, PagePlan], dict]:
    """Plan removal of everything fully inside each page's region."""
    plans, report = {}, {"pages_not_editable": [], "objects_kept_not_separable": 0}
    with pdfium.PdfDocument(str(pdf_path)) as document:
        for index, region in regions.items():
            page = reader.pages[index]
            plan = PagePlan(index, region=region)
            with closing(document[index]) as pdf_page:
                objects = page_objects(pdf_page)
            inside = [number for number, info in enumerate(objects)
                      if contained(info.bounds, region) and
                      not (info.type == PDFIUM_TYPES["text"] and info.text_mode in INVISIBLE_TEXT_MODES)]
            if inside:
                content = analyze_page(page)
                error = mapping_error(content, objects, page)
                if error:
                    report["pages_not_editable"].append(index + 1)
                else:
                    plan.content = content
                    removable, blocked = _removable(content, inside, objects, allow_invisible=False)
                    report["objects_kept_not_separable"] += len(blocked)
                    plan.removals = [Removal("area_object", objects[number].bounds, site=number)
                                     for number in sorted(removable)]
                    plan.eligible_inside = len(removable) + len(blocked)
            annotations, popups, total = area_annotations(page, region)
            plan.annotations_inside = total
            plan.removals += annotations
            plan.extra_annotations = popups
            if plan.removals:
                plans[index] = plan
    return plans, report


def area_annotations(page, region):
    """/Watermark and /Stamp annotations whose /Rect is fully inside ``region``."""
    removals, popups, total = [], [], 0
    annotations = resolve(page.get("/Annots", ArrayObject()))
    positions = {reference_key(item): number for number, item in enumerate(annotations)
                 if reference_key(item) is not None}
    for number, item in enumerate(annotations):
        annotation = resolve(item)
        if str(resolve(annotation.get("/Subtype"))) not in ("/Watermark", "/Stamp"):
            continue
        flags = resolve(annotation.get("/F", NumberObject(0)))
        if isinstance(flags, int) and int(flags) & HIDDEN_ANNOTATION_FLAGS:
            continue
        rect = numbers(annotation.get("/Rect"), 4)
        if rect is None:
            continue
        rect = (min(rect[0], rect[2]), min(rect[1], rect[3]), max(rect[0], rect[2]), max(rect[1], rect[3]))
        if not contained(rect, region):
            continue
        total += 1
        removals.append(Removal("area_annotation", rect, annotation=number, reference=reference_key(item)))
        popup = positions.get(reference_key(annotation.raw_get("/Popup"))) if "/Popup" in annotation else None
        if popup is not None:
            popups.append(popup)
    return removals, popups, total


# --- applying edits --------------------------------------------------------------------

def _new_stream(writer, data: bytes) -> IndirectObject:
    stream = DecodedStreamObject()
    stream.set_data(data)
    return writer._add_object(stream.flate_encode())


def _do_names(data_by_stream, resources) -> set[str]:
    names = set()
    for operation in tokenize(data_by_stream, resources):
        if operation.operator == b"Do" and operation.operands:
            names.add(str(operation.operands[-1]))
    return names


def apply_plans(writer, plans: dict[int, PagePlan]) -> None:
    for index, plan in plans.items():
        page = writer.pages[index]
        if plan.content_removals:
            content = plan.content
            edits = [removal_edit(content, content.sites[removal.site]) for removal in plan.content_removals]
            changed = splice(content, edits)
            raw = resolve(page.raw_get("/Contents"))
            if isinstance(raw, ArrayObject):
                page[NameObject("/Contents")] = ArrayObject(
                    _new_stream(writer, changed[number]) if number in changed else item
                    for number, item in enumerate(raw))
            elif isinstance(raw, StreamObject) and set(changed) == {0}:
                page[NameObject("/Contents")] = _new_stream(writer, changed[0])
            else:
                raise EngineFailure(Outcome.FAILED, "content_stream_layout_changed")
            removed_names = {content.sites[removal.site].xobject for removal in plan.content_removals
                             if content.sites[removal.site].xobject is not None}
            _drop_unused_xobjects(page, content, changed, removed_names)
        if plan.annotation_indices:
            annotations = resolve(page.get("/Annots", ArrayObject()))
            page[NameObject("/Annots")] = ArrayObject(
                item for number, item in enumerate(annotations) if number not in plan.annotation_indices)


def _drop_unused_xobjects(page, content, changed, removed):
    """Detach XObjects whose only uses were removed, via a page-private resource dict."""
    resources = resolve(page.get("/Resources"))
    if not isinstance(resources, DictionaryObject) or not removed:
        return
    xobjects = resolve(resources.get("/XObject"))
    if not isinstance(xobjects, DictionaryObject):
        return
    streams = [changed.get(number, data) for number, data in enumerate(content.streams)]
    remaining = _do_names(streams, resources)
    drop = {name for name in removed if name not in remaining and "/" + name in xobjects}
    if not drop:
        return
    for key, value in xobjects.items():
        value = resolve(value)
        if (key[1:] not in drop and isinstance(value, StreamObject) and
                str(resolve(value.get("/Subtype"))) == "/Form" and "/Resources" not in value):
            return  # A form without resources may inherit these names.
    private = DictionaryObject(resources)
    private[NameObject("/XObject")] = DictionaryObject(
        (key, value) for key, value in xobjects.items() if key[1:] not in drop)
    page[NameObject("/Resources")] = private


# --- validation ---------------------------------------------------------------------------

def _device_rects(geometry, regions, size):
    width, height = size
    rects = []
    for region in regions:
        unit = pdf_rect_to_unit(geometry, region, render_box="cropBox")
        if unit is None:
            continue
        rects.append((unit[0] * width - REGION_DILATION_PIXELS, unit[1] * height - REGION_DILATION_PIXELS,
                      unit[2] * width + REGION_DILATION_PIXELS, unit[3] * height + REGION_DILATION_PIXELS))
    return rects


def _intersects(box, regions, margin):
    return any(box[0] <= region[2] + margin and box[2] >= region[0] - margin and
               box[1] <= region[3] + margin and box[3] >= region[1] - margin for region in regions)


def compare_renders(source_path, output_path, geometries, regions: dict[int, list], limits):
    """Pixels and text outside each page's allowed regions must be unchanged.

    Returns the 1-based pages whose rendering changed at all.
    """
    changed_pages = []
    with pdfium.PdfDocument(str(source_path)) as source, pdfium.PdfDocument(str(output_path)) as output:
        if len(source) != len(geometries) or len(output) != len(geometries):
            raise EngineFailure(Outcome.FAILED, "output_page_count_changed")
        for index, geometry in enumerate(geometries):
            allowed = regions.get(index, [])
            with closing(source[index]) as before_page, closing(output[index]) as after_page:
                check_page_geometry(before_page, geometry)
                try:
                    check_page_geometry(after_page, geometry)
                except EngineFailure:
                    raise EngineFailure(Outcome.FAILED, "output_page_geometry_changed") from None
                size = render_size(before_page, limits.render_long_edge)
                before = render_image(before_page, size)
                after = render_image(after_page, size)
                difference = ImageChops.difference(before, after)
                red, green, blue = difference.split()
                delta = ImageChops.lighter(ImageChops.lighter(red, green), blue)
                threshold = delta.point(lambda value: 255 if value > PIXEL_TOLERANCE else 0)
                if threshold.getbbox() is not None:
                    changed_pages.append(index + 1)
                    rects = _device_rects(geometry, allowed, size)
                    if rects:
                        draw = ImageDraw.Draw(threshold)
                        for rect in rects:
                            draw.rectangle(rect, fill=0)
                    if threshold.getbbox() is not None:
                        raise EngineFailure(Outcome.FAILED, "content_outside_selection_changed")
                margin = REGION_DILATION_PIXELS * max(
                    geometry.crop_box[2] - geometry.crop_box[0],
                    geometry.crop_box[3] - geometry.crop_box[1]) / limits.render_long_edge
                before_text = [item for item in text_characters(before_page)
                               if not _intersects(item[1], allowed, margin)]
                after_text = [item for item in text_characters(after_page)
                              if not _intersects(item[1], allowed, margin)]
                if len(before_text) != len(after_text) or any(
                        first[0] != second[0] or
                        any(abs(a - b) > TEXT_POSITION_TOLERANCE for a, b in zip(first[1], second[1]))
                        for first, second in zip(before_text, after_text)):
                    raise EngineFailure(Outcome.FAILED, "text_outside_selection_changed")
    return changed_pages


def write_and_validate(reader, plans, source_path, job: Path, limits, geometries, *, mode: str):
    """Apply ``plans`` to a clone, write, and validate; returns the processed path.

    Raises ``EngineFailure(FAILED, <code>)`` on any failed check. The caller
    publishes nothing unless this returns.
    """
    removed_references = frozenset(removal.reference for plan in plans.values() for removal in plan.removals
                                   if removal.reference is not None) | frozenset(
        reference_key(resolve(reader.pages[plan.index].get("/Annots", ArrayObject()))[number])
        for plan in plans.values() for number in plan.extra_annotations)
    edited_pages = sorted(index for index, plan in plans.items() if plan.content_removals)
    skips = {reference_key(reader.pages[index].indirect_reference): ("/Contents", "/Resources")
             for index in edited_pages}
    expected_digest = Graph(limits, removed_references, skips).digest(reader)
    writer = clone_document(reader)
    try:
        apply_plans(writer, plans)
        write_pdf(writer, job / "detached.pdf", limits)
    finally:
        writer.close()
    with PdfReader(job / "detached.pdf", strict=True) as detached:
        cleaned = clone_document(detached)
        try:
            write_pdf(cleaned, job / "processed.pdf", limits)
        finally:
            cleaned.close()
    output_path = job / "processed.pdf"
    output_reader, output_geometries, _ = load_document(output_path, limits)
    try:
        if output_geometries != geometries:
            raise EngineFailure(Outcome.FAILED, "output_page_geometry_changed")
        output_skips = {reference_key(output_reader.pages[index].indirect_reference): ("/Contents", "/Resources")
                        for index in edited_pages}
        if Graph(limits, frozenset(), output_skips).digest(output_reader) != expected_digest:
            raise EngineFailure(Outcome.FAILED, "structural_preservation_check_failed")
        _check_removed_objects(output_reader, output_path, plans, mode)
    finally:
        output_reader.close()
    # Area mode may change only the mapped selection; automatic removal only the
    # removed objects' own bounds (artifact objects and annotation rectangles).
    if mode == "area":
        regions = {index: [plan.region] for index, plan in plans.items()}
    else:
        regions = {index: [removal.bounds for removal in plan.removals if removal.bounds is not None]
                   for index, plan in plans.items()}
    changed = compare_renders(source_path, output_path, geometries, regions, limits)
    if any(page - 1 not in plans for page in changed):
        raise EngineFailure(Outcome.FAILED, "unexpected_page_change")
    return output_path


def _check_removed_objects(output_reader, output_path, plans, mode):
    """Re-derive what remains on edited pages; removed objects must be gone."""
    with pdfium.PdfDocument(str(output_path)) as document:
        for index, plan in plans.items():
            page = output_reader.pages[index]
            if plan.content_removals:
                content = analyze_page(page)
                with closing(document[index]) as pdf_page:
                    objects = page_objects(pdf_page)
                if mapping_error(content, objects, page):
                    raise EngineFailure(Outcome.FAILED, "output_content_unverifiable")
                if mode == "auto":
                    if any(site.watermark_artifact for site in content.sites):
                        raise EngineFailure(Outcome.FAILED, "watermark_artifact_absence_check_failed")
                else:
                    remaining = sum(1 for info in objects if contained(info.bounds, plan.region) and not (
                        info.type == PDFIUM_TYPES["text"] and info.text_mode in INVISIBLE_TEXT_MODES))
                    if remaining != plan.eligible_inside - len(plan.content_removals):
                        raise EngineFailure(Outcome.FAILED, "area_object_absence_check_failed")
            if mode == "area":
                _, _, total = area_annotations(page, plan.region)
                removed = sum(1 for removal in plan.removals if removal.annotation is not None)
                if total != plan.annotations_inside - removed:
                    raise EngineFailure(Outcome.FAILED, "area_annotation_absence_check_failed")

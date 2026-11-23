from __future__ import annotations

from contextlib import closing
from pathlib import Path

import pypdfium2 as pdfium
from pypdf import PdfReader
from pypdf.generic import ArrayObject, NameObject

from .annotations import contains, scan
from .document import (Graph, clone_document, load_document, page_report, resolve,
                       trim_trailing_bytes, write_pdf)
from .editing import Removal, PagePlan, plan_area, scan_artifacts, write_and_validate
from .geometry import (GeometryError, NormalizedRect, geometry_digest,
                       normalized_to_pdf, validate_raster)
from .models import (APPLY_TO, REMOVAL_KINDS, REMOVAL_MODES, EngineFailure, EngineResult,
                     Limits, ManualSelection, Outcome)
from .rendering import render_image, render_size, verify_render

__all__ = ["run_job", "clone_document", "write_pdf"]


def validated_selection(selection, geometries, revision, size, document_id):
    """Check an attested page-one selection; returns (selection, rect, page-one PDF rect)."""
    try:
        selection = ManualSelection.from_dict(selection)
        if (selection.document_id != document_id or selection.source_sha256 != revision or
                type(selection.source_size) is not int or selection.source_size != size):
            raise EngineFailure(Outcome.FAILED, "manual_document_identity_or_revision_mismatch")
        if type(selection.page_number) is not int or selection.page_number != 1:
            raise EngineFailure(Outcome.FAILED, "manual_selection_supports_page_one_only")
        if selection.coordinate_space != "renderedPageTopLeft":
            raise EngineFailure(Outcome.FAILED, "ambiguous_manual_coordinate_space")
        geometry = geometries[0]
        if selection.geometry_sha256 != geometry_digest(geometry):
            raise EngineFailure(Outcome.FAILED, "manual_page_geometry_mismatch")
        validate_raster(geometry, render_box=selection.render_box,
                        raster_width=selection.raster_width, raster_height=selection.raster_height)
        rect = NormalizedRect(*selection.rect)
        return selection, rect, normalized_to_pdf(geometry, rect, render_box=selection.render_box)
    except EngineFailure:
        raise
    except (TypeError, ValueError, KeyError, GeometryError):
        raise EngineFailure(Outcome.FAILED, "invalid_or_ambiguous_manual_mapping") from None


def selected_candidates(candidates, selection, geometries, revision, size, document_id):
    supported = [candidate for candidate in candidates if candidate.supported]
    if selection is None:
        return supported
    _, _, mapped = validated_selection(selection, geometries, revision, size, document_id)
    # A partial intersection does not authorize deleting the entire object.
    return [candidate for candidate in supported if candidate.page_number == 1 and contains(mapped, candidate.rect)]


def render_preview(pdf_path, job: Path, geometry, long_edge: int, limits) -> dict:
    """Render page one (crop box, rotation applied, annotations drawn) to PNG."""
    if isinstance(long_edge, bool) or not isinstance(long_edge, int) or not 16 <= long_edge <= 4096:
        raise EngineFailure(Outcome.FAILED, "invalid_preview_size")
    target = job / "preview.png"
    with pdfium.PdfDocument(str(pdf_path)) as document, closing(document[0]) as page:
        width, height = render_size(page, long_edge)
        image = render_image(page, (width, height), annotations=True)
    with target.open("xb") as stream:
        image.save(stream, format="PNG", optimize=False)
    if target.stat().st_size > limits.max_output_bytes:
        raise EngineFailure(Outcome.FAILED, "preview_size_limit")
    return {"page_number": 1, "width": width, "height": height, "render_box": "cropBox",
            "geometry_sha256": geometry_digest(geometry)}


def _check_signed(graph, reader, result):
    if graph.signed or "/Perms" in reader.root_object:
        result.outcome = Outcome.UNSUPPORTED
        result.code = "signed_or_certified_document_not_modified"
        return True
    return False


def run_job(request, limits: Limits, *, in_process: bool = False):
    """Run one job.\n\n    A worker process is started inside its job directory, so the directory must be the\n    current one. In-process runs (Android) cannot change the process-wide directory and\n    only check the job folder's name.\n    """
    job = Path(request["job"]).resolve()
    if (not in_process and job != Path.cwd().resolve()) or not job.name.startswith("pdfwm_"):
        raise EngineFailure(Outcome.FAILED, "invalid_job_directory")
    path = job / "input.pdf"
    revision, size = request["sha256"], request["size"]
    document_id = "sha256:" + revision
    action = request["action"]
    if action not in ("detect", "analyze", "remove"):
        raise EngineFailure(Outcome.FAILED, "invalid_action")
    mode = request.get("mode", "auto")
    apply_to = request.get("apply_to", "all_pages")
    if action == "remove" and (mode not in REMOVAL_MODES or apply_to not in APPLY_TO):
        raise EngineFailure(Outcome.FAILED, "invalid_mode_or_scope")
    trimmed = trim_trailing_bytes(path)
    reader = None
    try:
        reader, geometries, graph = load_document(path, limits)
        candidates = scan(reader, geometries, graph, revision, limits)
        supported = [candidate for candidate in candidates if candidate.supported]
        unsupported = [candidate for candidate in candidates if not candidate.supported]
        source_renders = verify_render(path, geometries, limits)
        scope = list(range(len(geometries))) if apply_to == "all_pages" else [0]
        artifacts = None
        if action != "remove" or mode == "auto":
            restrict = None
            if action == "remove" and request.get("selection") is not None:
                _, _, mapped = validated_selection(request["selection"], geometries, revision, size, document_id)
                scope, restrict = [0], {0: mapped}
            artifacts = scan_artifacts(reader, path, scope if action == "remove" else range(len(geometries)),
                                       restrict=restrict)
        pages = [page_report(geometry) for geometry in geometries]
        if artifacts is not None:
            for index, page in enumerate(pages):
                plan = artifacts.plans.get(index)
                page["watermark_artifact_count"] = len(plan.removals) if plan else 0
        artifact_count = artifacts.count if artifacts is not None else 0
        unsupported_artifacts = artifacts.unsupported_pages if artifacts is not None else {}
        if supported or artifact_count:
            outcome = Outcome.SUPPORTED_DETECTED
        elif unsupported or unsupported_artifacts:
            outcome = Outcome.UNSUPPORTED
        else:
            outcome = Outcome.NONE_DETECTED
        result = EngineResult(outcome, "annotation_scan_complete", revision, size, document_id,
                              len(geometries), len(supported), len(unsupported),
                              candidates=[candidate.report() for candidate in candidates],
                              pages=pages,
                              checks={"strict_parser_readable": True, "independent_pdfium_readable": True,
                                      "all_pages_rendered": True, "signed_document": graph.signed},
                              artifact_count=artifact_count)
        if unsupported_artifacts:
            result.checks["unsupported_artifact_pages"] = sorted(index + 1 for index in unsupported_artifacts)
        if trimmed:
            result.checks["trailing_bytes_after_eof_ignored"] = trimmed
        if action == "detect":
            return result
        if action == "analyze":
            result.preview = render_preview(path, job, geometries[0], request.get("long_edge", 1024), limits)
            return result
        if mode == "area":
            processed = _remove_area(request, reader, graph, geometries, result, path, job, limits,
                                     revision, size, document_id, scope)
        else:
            processed = _remove_auto(request, reader, graph, geometries, result, path, job, limits,
                                     revision, size, document_id, scope, candidates, supported,
                                     unsupported, artifacts, source_renders)
        if processed and request.get("preview"):
            result.preview = render_preview(job / "processed.pdf", job, geometries[0],
                                            request.get("long_edge", 1024), limits)
        if result.outcome == Outcome.REMOVED:
            total = sum(result.removed_by_kind.values())
            if (total <= 0 or total != result.removed_count or
                    set(result.removed_by_kind) - set(REMOVAL_KINDS) or not result.pages_changed):
                raise EngineFailure(Outcome.FAILED, "inconsistent_removal_report")
        return result
    finally:
        if reader is not None:
            reader.close()


def _finish(result, plans, code):
    removed = {}
    for plan in plans.values():
        for removal in plan.removals:
            removed[removal.kind] = removed.get(removal.kind, 0) + 1
    result.outcome = Outcome.REMOVED
    result.code = code
    result.removed_by_kind = removed
    result.removed_count = sum(removed.values())
    result.pages_changed = sorted(index + 1 for index, plan in plans.items() if plan.removals)
    result.checks.update({"page_geometry_unchanged": True, "non_edited_graph_unchanged": True,
                          "removed_objects_absent": True, "content_outside_removed_area_unchanged": True,
                          "text_outside_removed_area_unchanged": True,
                          "output_independently_readable": True})


def _remove_area(request, reader, graph, geometries, result, path, job, limits,
                 revision, size, document_id, scope):
    if request.get("selection") is None:
        raise EngineFailure(Outcome.FAILED, "area_selection_required")
    selection, rect, _ = validated_selection(request["selection"], geometries, revision, size, document_id)
    if _check_signed(graph, reader, result):
        return False
    try:
        regions = {index: normalized_to_pdf(geometries[index], rect, render_box=selection.render_box)
                   for index in scope}
    except GeometryError:
        raise EngineFailure(Outcome.FAILED, "invalid_or_ambiguous_manual_mapping") from None
    plans, report = plan_area(reader, path, regions)
    result.checks.update({"area_pages_not_editable": report["pages_not_editable"],
                          "area_objects_kept_not_separable": report["objects_kept_not_separable"]})
    if not plans:
        result.outcome = Outcome.NONE_DETECTED
        result.code = ("area_content_structure_unsupported" if report["pages_not_editable"]
                       else "no_removable_objects_in_selection")
        if report["pages_not_editable"]:
            result.outcome = Outcome.UNSUPPORTED
        return False
    write_and_validate(reader, plans, path, job, limits, geometries, mode="area")
    _finish(result, plans, "selected_area_objects_removed")
    return True


def _remove_auto(request, reader, graph, geometries, result, path, job, limits, revision, size,
                 document_id, scope, candidates, supported, unsupported, artifacts, source_renders):
    selected = selected_candidates(candidates, request.get("selection"), geometries, revision, size, document_id)
    selected = [candidate for candidate in selected if candidate.page_number - 1 in scope]
    if not selected and not artifacts.plans:
        result.outcome = (Outcome.UNSUPPORTED if (unsupported or artifacts.unsupported_pages)
                          and not supported and not artifacts.count else Outcome.NONE_DETECTED)
        result.code = "no_supported_objects_in_scope"
        return False
    if _check_signed(graph, reader, result):
        return False
    if artifacts.plans:
        plans = dict(artifacts.plans)
        for candidate in selected:
            plan = plans.setdefault(candidate.page_number - 1, PagePlan(candidate.page_number - 1))
            plan.removals.append(Removal("watermark_annotation", candidate.rect,
                                         annotation=candidate.index, reference=candidate.reference))
        write_and_validate(reader, plans, path, job, limits, geometries, mode="auto")
        _verify_remaining_annotations(job / "processed.pdf", limits, revision, len(supported) - len(selected))
        _finish(result, plans, "supported_watermarks_removed")
        result.checks["unsupported_candidates_preserved"] = len(unsupported)
        return True
    _remove_annotations_strict(reader, geometries, graph, selected, supported, unsupported,
                               result, job, limits, revision, source_renders)
    plans = {}
    for candidate in selected:
        plans.setdefault(candidate.page_number - 1, PagePlan(candidate.page_number - 1)).removals.append(
            Removal("watermark_annotation", candidate.rect))
    _finish(result, plans, "supported_annotation_objects_removed")
    result.checks.update({"non_watermark_graph_unchanged": True, "base_content_render_unchanged": True,
                          "unsupported_candidates_preserved": len(unsupported)})
    for key in ("non_edited_graph_unchanged", "content_outside_removed_area_unchanged",
                "text_outside_removed_area_unchanged"):
        result.checks.pop(key, None)
    return True


def _verify_remaining_annotations(output, limits, revision, expected):
    output_reader, output_geometries, output_graph = load_document(output, limits)
    try:
        remaining = scan(output_reader, output_geometries, output_graph, revision, limits)
        if sum(candidate.supported for candidate in remaining) != expected:
            raise EngineFailure(Outcome.FAILED, "watermark_absence_check_failed")
        _check_orphan_watermarks(output_reader, output_graph)
    finally:
        output_reader.close()


def _check_orphan_watermarks(output_reader, output_graph):
    # Also check raw xref annotation objects, not just the visible /Annots.
    from pypdf.generic import DictionaryObject, IndirectObject
    for generation, entries in output_reader.xref.items():
        for object_id in entries:
            if object_id == 0:
                continue
            obj = output_reader.get_object(IndirectObject(object_id, generation, output_reader))
            if (isinstance(obj, DictionaryObject) and str(resolve(obj.get("/Subtype"))) == "/Watermark"
                    and (object_id, generation) not in output_graph.references):
                raise EngineFailure(Outcome.FAILED, "removed_annotation_object_retained")


def _remove_annotations_strict(reader, geometries, graph, selected, supported, unsupported,
                               result, job, limits, revision, source_renders):
    """Stage 6A pipeline: annotation-only removal with full graph equivalence."""
    removed_refs = frozenset(candidate.reference for candidate in selected)
    expected_digest = Graph(limits, removed_refs).digest(reader)
    writer = clone_document(reader)
    try:
        indices = {(candidate.page_number - 1, candidate.index) for candidate in selected}
        for page_index, page in enumerate(writer.pages):
            annotations = resolve(page.get("/Annots", ArrayObject()))
            kept = ArrayObject([annotation for index, annotation in enumerate(annotations)
                                if (page_index, index) not in indices])
            if "/Annots" in page:
                page[NameObject("/Annots")] = kept
        write_pdf(writer, job / "detached.pdf", limits)
    finally:
        writer.close()
    # A second whole-document clone traverses only reachable root objects:
    # detached annotation dictionaries and exclusively owned AP resources
    # cannot linger as orphaned objects in the published PDF.
    with PdfReader(job / "detached.pdf", strict=True) as detached:
        cleaned = clone_document(detached)
        try:
            write_pdf(cleaned, job / "processed.pdf", limits)
        finally:
            cleaned.close()
    output_reader, output_geometries, output_graph = load_document(job / "processed.pdf", limits)
    try:
        if output_geometries != geometries or output_graph.digest(output_reader) != expected_digest:
            raise EngineFailure(Outcome.FAILED, "structural_preservation_check_failed")
        remaining = scan(output_reader, output_geometries, output_graph, revision, limits)
        if sum(candidate.supported for candidate in remaining) != len(supported) - len(selected):
            raise EngineFailure(Outcome.FAILED, "watermark_absence_check_failed")
        _check_orphan_watermarks(output_reader, output_graph)
    finally:
        output_reader.close()
    output_renders = verify_render(job / "processed.pdf", output_geometries, limits)
    if output_renders != source_renders:
        raise EngineFailure(Outcome.FAILED, "base_content_render_changed")

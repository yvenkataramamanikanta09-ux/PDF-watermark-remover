from __future__ import annotations

from pathlib import Path

from pypdf import PdfReader, PdfWriter
from pypdf.generic import ArrayObject, NameObject

from .annotations import contains, scan
from .document import Graph, load_document, page_report, reference_key, resolve
from .geometry import (GeometryError, NormalizedRect, geometry_digest,
                       normalized_to_pdf, validate_raster)
from .models import EngineFailure, EngineResult, Limits, ManualSelection, Outcome
from .rendering import verify_render
from .storage import BoundedWriter


def write_pdf(writer, path, limits):
    with path.open("xb") as stream:
        writer.write(BoundedWriter(stream, limits.max_output_bytes))


def clone_document(reader):
    """Clone reachable objects, retaining the source's nested page tree.

    pypdf's whole-document clone flattens /Pages and rewrites leaf /Parent.
    Restore those links using its existing object translations before writing.
    The final graph audit rejects any other unintended transformation.
    """
    writer = PdfWriter(clone_from=reader, strict=True, keep_initial_header=True)
    pending = [reader.root_object.raw_get("/Pages")]
    visited = set()
    while pending:
        reference = pending.pop()
        key = reference_key(reference)
        if key in visited:
            writer.close()
            raise EngineFailure(Outcome.INVALID_PDF, "cyclic_or_shared_page_tree")
        visited.add(key)
        source = resolve(reference)
        cloned = resolve(reference.clone(writer))
        for field in ("/Parent", "/Kids"):
            if field in source:
                cloned[NameObject(field)] = source.raw_get(field).clone(writer)
        if "/Kids" in source:
            pending.extend(resolve(source.raw_get("/Kids")))
    return writer


def selected_candidates(candidates, selection, geometries, revision, size, document_id):
    supported = [candidate for candidate in candidates if candidate.supported]
    if selection is None:
        return supported
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
        mapped = normalized_to_pdf(geometry, NormalizedRect(*selection.rect), render_box=selection.render_box)
        # A partial intersection does not authorize deleting the entire object.
        return [candidate for candidate in supported if candidate.page_number == 1 and contains(mapped, candidate.rect)]
    except EngineFailure:
        raise
    except (TypeError, ValueError, KeyError, GeometryError):
        raise EngineFailure(Outcome.FAILED, "invalid_or_ambiguous_manual_mapping") from None


def run_job(request, limits: Limits):
    job = Path(request["job"]).resolve()
    if job != Path.cwd().resolve() or not job.name.startswith("pdfwm_"):
        raise EngineFailure(Outcome.FAILED, "invalid_job_directory")
    path = job / "input.pdf"
    revision, size = request["sha256"], request["size"]
    document_id = "sha256:" + revision
    reader = None
    output_reader = None
    try:
        reader, geometries, graph = load_document(path, limits)
        candidates = scan(reader, geometries, graph, revision, limits)
        supported = [candidate for candidate in candidates if candidate.supported]
        unsupported = [candidate for candidate in candidates if not candidate.supported]
        source_renders = verify_render(path, geometries, limits)
        outcome = Outcome.SUPPORTED_DETECTED if supported else Outcome.UNSUPPORTED if unsupported else Outcome.NONE_DETECTED
        result = EngineResult(outcome, "annotation_scan_complete", revision, size, document_id,
                              len(geometries), len(supported), len(unsupported),
                              candidates=[candidate.report() for candidate in candidates],
                              pages=[page_report(geometry) for geometry in geometries],
                              checks={"strict_parser_readable": True, "independent_pdfium_readable": True,
                                      "all_pages_rendered": True, "signed_document": graph.signed})
        if request["action"] == "detect":
            return result
        if request["action"] != "remove":
            raise EngineFailure(Outcome.FAILED, "invalid_action")
        selected = selected_candidates(candidates, request.get("selection"), geometries, revision, size, document_id)
        if not selected:
            result.outcome = Outcome.UNSUPPORTED if unsupported and not supported else Outcome.NONE_DETECTED
            result.code = "no_supported_objects_in_scope"
            return result
        if graph.signed or "/Perms" in reader.root_object:
            result.outcome = Outcome.UNSUPPORTED
            result.code = "signed_or_certified_document_not_modified"
            return result
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
        if output_geometries != geometries or output_graph.digest(output_reader) != expected_digest:
            raise EngineFailure(Outcome.FAILED, "structural_preservation_check_failed")
        remaining = scan(output_reader, output_geometries, output_graph, revision, limits)
        if sum(candidate.supported for candidate in remaining) != len(supported) - len(selected):
            raise EngineFailure(Outcome.FAILED, "watermark_absence_check_failed")
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
        output_renders = verify_render(job / "processed.pdf", output_geometries, limits)
        if output_renders != source_renders:
            raise EngineFailure(Outcome.FAILED, "base_content_render_changed")
        result.outcome = Outcome.REMOVED
        result.code = "supported_annotation_objects_removed"
        result.removed_count = len(selected)
        result.checks.update({"page_geometry_unchanged": True, "non_watermark_graph_unchanged": True,
                              "removed_objects_absent": True, "base_content_render_unchanged": True,
                              "output_independently_readable": True,
                              "unsupported_candidates_preserved": len(unsupported)})
        return result
    finally:
        if output_reader is not None:
            output_reader.close()
        if reader is not None:
            reader.close()

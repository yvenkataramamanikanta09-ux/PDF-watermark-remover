from __future__ import annotations

from collections import defaultdict
from dataclasses import asdict
import hashlib
import json
import math
from pathlib import Path
import re

from pypdf import PdfReader
from pypdf.errors import DependencyError
from pypdf.generic import (ArrayObject, BooleanObject, ByteStringObject, DictionaryObject,
                           FloatObject, IndirectObject, NameObject, NullObject, NumberObject,
                           StreamObject, TextStringObject)

from .geometry import GeometryError, PageGeometry, effective_crop_box, geometry_digest
from .models import EngineFailure, Limits, Outcome


def reference_key(value):
    if isinstance(value, IndirectObject):
        return value.idnum, value.generation
    return None


def resolve(value):
    seen = set()
    while isinstance(value, IndirectObject):
        key = reference_key(value)
        if key in seen or len(seen) > 64:
            raise EngineFailure(Outcome.INVALID_PDF, "invalid_reference_cycle")
        seen.add(key)
        value = value.get_object()
    return value


INHERITABLE_PAGE_ATTRIBUTES = ("/Resources", "/MediaBox", "/CropBox", "/Rotate")


class Graph:
    """Bounded logical graph digest; independent of rewritten object numbers."""
    def __init__(self, limits: Limits, removed=frozenset(), page_skips=None):
        self.limits = limits
        self.removed = removed
        # {page object reference: keys deliberately excluded from comparison}
        # e.g. the rewritten /Contents and /Resources of an edited page.
        self.page_skips = page_skips or {}
        self.references = {}
        self.incoming = defaultdict(list)
        self.nodes = 0
        self.decoded = 0
        self.signed = False

    def encode(self, value, depth=0, context="", skip=()):
        self.nodes += 1
        if depth > self.limits.max_graph_depth or self.nodes > self.limits.max_objects * 32:
            raise EngineFailure(Outcome.FAILED, "object_graph_limit")
        if isinstance(value, IndirectObject):
            key = reference_key(value)
            self.incoming[key].append(context)
            if key in self.references:
                return ["ref", self.references[key]]
            if len(self.references) >= self.limits.max_objects:
                raise EngineFailure(Outcome.FAILED, "object_count_limit")
            index = len(self.references)
            self.references[key] = index
            return ["object", index, self.encode(resolve(value), depth + 1, context,
                                                 self.page_skips.get(key, ()))]
        if isinstance(value, (DictionaryObject, StreamObject)):
            if (str(resolve(value.get("/FT"))) == "/Sig" or
                    str(resolve(value.get("/Type"))) in ("/Sig", "/DocTimeStamp") or
                    ("/ByteRange" in value and "/Contents" in value)):
                self.signed = True
            items = []
            for key, item in sorted(self._effective_items(value), key=lambda pair: str(pair[0])):
                if str(key) == "/Length" and isinstance(value, StreamObject):
                    continue  # Encoded byte length may be reserialized; data is checked.
                if str(key) in skip:
                    items.append([str(key), ["edited"]])
                    continue
                items.append([str(key), self.encode(item, depth + 1, str(key))])
            if isinstance(value, StreamObject):
                data = value.get_data()
                self.decoded += len(data)
                if self.decoded > self.limits.max_decoded_stream_bytes:
                    raise EngineFailure(Outcome.FAILED, "decoded_stream_limit")
                return ["stream", items, hashlib.sha256(data).hexdigest(), len(data)]
            return ["dictionary", items]
        if isinstance(value, ArrayObject):
            return ["array", [self.encode(item, depth + 1, context + "[]") for item in value
                              if not (context == "/Annots" and reference_key(item) in self.removed)]]
        if isinstance(value, NameObject):
            return ["name", str(value)]
        if isinstance(value, TextStringObject):
            return ["text", str(value)]
        if isinstance(value, (ByteStringObject, bytes)):
            return ["bytes", bytes(value).hex()]
        if isinstance(value, BooleanObject):
            return ["boolean", value.value]
        if isinstance(value, (FloatObject, NumberObject, int, float)):
            number = float(value)
            if not math.isfinite(number):
                raise EngineFailure(Outcome.INVALID_PDF, "non_finite_pdf_number")
            if isinstance(value, float) and number != 0.0:
                # pypdf serializes reals with 8 significant digits (FloatObject
                # .myrepr), so 1008.789063 is written as 1008.78906. Compare at
                # that precision, which is idempotent for already-written values.
                number = float(FloatObject(number).myrepr())
            return ["number", number]
        if value is None or isinstance(value, NullObject):
            return ["null"]
        raise EngineFailure(Outcome.INVALID_PDF, "unsupported_pdf_object")

    def _effective_items(self, value):
        """Items of a dictionary; page leaves also get inherited attributes.

        pypdf's whole-document clone writes inherited /Resources, /MediaBox,
        /CropBox and /Rotate explicitly on every page. That is semantically
        identical, so both sides are compared with inheritance resolved.
        """
        items = list(value.items())
        if isinstance(value, StreamObject) or str(resolve(value.get("/Type"))) != "/Page":
            return items
        present = {str(key) for key, _ in items}
        parent, depth = value.get("/Parent"), 0
        while parent is not None and depth < self.limits.max_graph_depth:
            node = resolve(parent)
            if not isinstance(node, DictionaryObject):
                break
            for key in INHERITABLE_PAGE_ATTRIBUTES:
                if key not in present and key in node:
                    items.append((NameObject(key), node.raw_get(key)))
                    present.add(key)
            parent, depth = node.get("/Parent"), depth + 1
        return items

    def digest(self, reader):
        # A graph can be inspected and then hashed again. Traversal indices
        # must always start afresh, including the incoming-reference audit.
        self.references.clear()
        self.incoming.clear()
        self.nodes = self.decoded = 0
        self.signed = False
        root = reader.trailer.raw_get("/Root")
        value = [self.encode(root)]
        if "/Info" in reader.trailer:
            value.append(self.encode(reader.trailer.raw_get("/Info")))
        return hashlib.sha256(json.dumps(value, ensure_ascii=True, separators=(",", ":")).encode()).hexdigest()


def page_geometry(page, number):
    def box(name, fallback=None):
        values = resolve(page.get(name, fallback))
        if not isinstance(values, ArrayObject) or len(values) != 4:
            raise GeometryError("Invalid page box")
        return tuple(float(resolve(value)) for value in values)
    media = box("/MediaBox")
    # A crop box extending beyond the media box is clipped to it (PDF 32000
    # 14.11.2); PDFium renders the same intersection. Empty -> invalid page.
    crop = effective_crop_box(media, box("/CropBox", page.get("/MediaBox")))
    return PageGeometry(number, media, crop,
                        float(resolve(page.get("/Rotate", 0))),
                        float(resolve(page.get("/UserUnit", 1))))


EOF_SEARCH_WINDOW = 4096


def trim_trailing_bytes(path: Path) -> int:
    """Drop bytes after the last ``%%EOF`` in the job's own snapshot copy.

    Scanners and printers often append padding or junk after the final
    ``%%EOF``. Only the private job copy is truncated; byte offsets before the
    marker are unchanged, and the recorded source hash still describes the
    original bytes. Returns the number of bytes removed (0 when none).
    """
    size = path.stat().st_size
    with path.open("rb") as stream:
        stream.seek(max(0, size - EOF_SEARCH_WINDOW))
        tail = stream.read()
    if tail.rstrip(b"\x00\t\n\f\r ").endswith(b"%%EOF"):
        return 0
    marker = tail.rfind(b"%%EOF")
    if marker < 0:
        raise EngineFailure(Outcome.INVALID_PDF, "invalid_pdf_header_or_eof")
    keep = size - len(tail) + marker + len(b"%%EOF")
    with path.open("r+b") as stream:
        stream.truncate(keep)
    return size - keep


def load_document(path: Path, limits: Limits):
    from pypdf import overwrite_configuration
    # The job process also has hard memory/time limits for other decoders.
    overwrite_configuration(
        maximum_declared_stream_length=limits.max_decoded_stream_bytes,
        array_based_stream_maximum_output_length=limits.max_decoded_stream_bytes,
        zlib_maximum_output_length=limits.max_decoded_stream_bytes,
        lzw_maximum_output_length=limits.max_decoded_stream_bytes,
        run_length_maximum_output_length=limits.max_decoded_stream_bytes,
        brotli_maximum_output_length=limits.max_decoded_stream_bytes,
        image_maximum_buffer_size=limits.max_decoded_stream_bytes,
        array_maximum_element_count=limits.max_objects,
        dictionary_maximum_element_count=limits.max_objects,
        page_tree_maximum_entries=limits.max_objects,
        page_tree_maximum_depth=limits.max_graph_depth,
        jbig2dec_binary=None,
    )
    with path.open("rb") as stream:
        header = stream.read(9)
        stream.seek(max(0, path.stat().st_size - 4096))
        tail = stream.read().rstrip(b"\x00\t\n\f\r ")
    if not re.fullmatch(rb"%PDF-(?:1\.[0-7]|2\.0)[\r\n]", header) or not tail.endswith(b"%%EOF"):
        raise EngineFailure(Outcome.INVALID_PDF, "invalid_pdf_header_or_eof")
    try:
        reader = PdfReader(path, strict=True, root_object_recovery_limit=0)
        if reader.is_encrypted:
            reader.close()
            raise EngineFailure(Outcome.PASSWORD_REQUIRED, "encrypted_documents_not_supported")
        object_count = sum(len(values) for values in reader.xref.values()) + len(reader.xref_objStm)
        if object_count > limits.max_objects:
            reader.close()
            raise EngineFailure(Outcome.FAILED, "object_count_limit")
        if not 1 <= len(reader.pages) <= limits.max_pages:
            reader.close()
            raise EngineFailure(Outcome.FAILED, "page_count_limit")
        geometries = [page_geometry(page, index + 1) for index, page in enumerate(reader.pages)]
        annotation_count = 0
        for page in reader.pages:
            annotations = resolve(page.get("/Annots", ArrayObject()))
            if not isinstance(annotations, ArrayObject):
                raise EngineFailure(Outcome.INVALID_PDF, "invalid_annotation_array")
            annotation_count += len(annotations)
            if annotation_count > limits.max_annotations:
                raise EngineFailure(Outcome.FAILED, "annotation_count_limit")
            for annotation in annotations:
                if not isinstance(resolve(annotation), DictionaryObject):
                    raise EngineFailure(Outcome.INVALID_PDF, "invalid_annotation_dictionary")
            content = page.get_contents()
            if content is not None:
                # Parse all active page content syntax, without rewriting it.
                _ = content.operations
        graph = Graph(limits)
        graph.digest(reader)
        return reader, geometries, graph
    except EngineFailure:
        raise
    except DependencyError:
        raise EngineFailure(Outcome.PASSWORD_REQUIRED, "encrypted_documents_not_supported") from None
    except (MemoryError, RecursionError):
        raise
    except Exception:
        raise EngineFailure(Outcome.INVALID_PDF, "invalid_pdf_structure") from None


def write_pdf(writer, path, limits):
    from .storage import BoundedWriter
    with path.open("xb") as stream:
        writer.write(BoundedWriter(stream, limits.max_output_bytes))


def clone_document(reader):
    """Clone reachable objects, retaining the source's nested page tree.

    pypdf's whole-document clone flattens /Pages and rewrites leaf /Parent.
    Restore those links using its existing object translations before writing.
    The final graph audit rejects any other unintended transformation.
    """
    from pypdf import PdfWriter
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


def page_report(geometry):
    result = asdict(geometry)
    result["geometry_sha256"] = geometry_digest(geometry)
    result["coordinate_space"] = "renderedPageTopLeft"
    result["manual_mapping_requires_explicit_render_box"] = True
    return result

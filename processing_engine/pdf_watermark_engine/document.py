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

from .geometry import GeometryError, PageGeometry, geometry_digest
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


class Graph:
    """Bounded logical graph digest; independent of rewritten object numbers."""
    def __init__(self, limits: Limits, removed=frozenset()):
        self.limits = limits
        self.removed = removed
        self.references = {}
        self.incoming = defaultdict(list)
        self.nodes = 0
        self.decoded = 0
        self.signed = False

    def encode(self, value, depth=0, context=""):
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
            return ["object", index, self.encode(resolve(value), depth + 1, context)]
        if isinstance(value, (DictionaryObject, StreamObject)):
            if (str(resolve(value.get("/FT"))) == "/Sig" or
                    str(resolve(value.get("/Type"))) in ("/Sig", "/DocTimeStamp") or
                    ("/ByteRange" in value and "/Contents" in value)):
                self.signed = True
            items = []
            for key, item in sorted(value.items(), key=lambda pair: str(pair[0])):
                if str(key) == "/Length" and isinstance(value, StreamObject):
                    continue  # Encoded byte length may be reserialized; data is checked.
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
            return ["number", number]
        if value is None or isinstance(value, NullObject):
            return ["null"]
        raise EngineFailure(Outcome.INVALID_PDF, "unsupported_pdf_object")

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
    return PageGeometry(number, media, box("/CropBox", page.get("/MediaBox")),
                        float(resolve(page.get("/Rotate", 0))),
                        float(resolve(page.get("/UserUnit", 1))))


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


def page_report(geometry):
    result = asdict(geometry)
    result["geometry_sha256"] = geometry_digest(geometry)
    result["coordinate_space"] = "renderedPageTopLeft"
    result["manual_mapping_requires_explicit_render_box"] = True
    return result

"""Byte-exact page content analysis and minimal operator splicing.

PDFium's own content regeneration (``FPDFPage_GenerateContent``) rewrites every
object of a stream and, in the pinned build, drops shadings, inline images and
character/word spacing. This module therefore never regenerates content.
Instead it:

1. tokenizes each content stream itself, keeping byte offsets;
2. replays the operators with PDFium's object-creation rules, producing one
   :class:`Site` per page object PDFium will create (path, text, image, form,
   shading), including the marked-content stack at that point;
3. lets the caller cross-check those sites against PDFium's actual page objects
   (types and mark depths) and pypdf's independent operator sequence; and
4. removes an object by splicing only its painting operator out of the original
   bytes (``f``/``S``/... become ``n``; ``Do``/``sh``/``Tj``/``TJ``/inline images
   are deleted; ``'``/``"`` keep their line-advance side effects). All other
   bytes, including graphics-state operators, stay identical.

Anything the tokenizer or replay cannot explain is reported as unmappable; the
caller then refuses to edit that page.
"""
from __future__ import annotations

from dataclasses import dataclass, field
import re

from pypdf.generic import ArrayObject, DictionaryObject, NameObject, StreamObject

from .document import resolve

_WS = b"\x00\t\n\x0c\r "
_WS_OR_COMMENT = re.compile(rb"(?:[\x00\t\n\x0c\r ]+|%[^\r\n]*)*")
_REGULAR = re.compile(rb"[^\x00\t\n\x0c\r ()<>\[\]{}/%]*")
_NUMBER = re.compile(rb"[+-]?(?:\d+\.?\d*|\.\d+)")
_HEX = re.compile(rb"[0-9A-Fa-f]*")
_INLINE_END = re.compile(rb"[\x00\t\n\x0c\r ]EI(?=[\x00\t\n\x0c\r ()<>\[\]{}/%]|$)")
_ESCAPES = {ord("n"): 10, ord("r"): 13, ord("t"): 9, ord("b"): 8, ord("f"): 12,
            ord("("): 40, ord(")"): 41, ord("\\"): 92}
MAX_PARAMS = 16  # PDFium keeps at most the last 16 operands of an operator.

PATH_PAINT = {b"S": (False, True), b"s": (True, True), b"f": (False, False), b"F": (False, False),
              b"f*": (False, False), b"B": (False, False), b"B*": (False, False),
              b"b": (True, False), b"b*": (True, False), b"n": (False, False)}
PDFIUM_TYPES = {"text": 1, "path": 2, "image": 3, "shading": 4, "form": 5}


class ContentSyntaxError(ValueError):
    """Content bytes that this tokenizer does not interpret like PDFium."""


class Name(str):
    """A decoded PDF name operand (without the leading slash)."""


class Keyword(str):
    """A bare keyword that is not an operator in this position."""


@dataclass
class Operation:
    operator: bytes
    operands: list         # at most the last MAX_PARAMS operands, like PDFium
    spans: list            # (stream, start, end) per kept operand
    stream: int
    start: int
    end: int
    leading: tuple | None = None  # (stream, start) of the first operand, kept or not

    @property
    def first(self):
        return self.leading if self.leading is not None else (self.stream, self.start)

    def single_stream(self) -> bool:
        return self.first[0] == self.stream


@dataclass
class Site:
    """One PDFium page object, with the operator that paints it."""
    kind: str
    op_index: int
    mark_depth: int
    watermark_artifact: bool
    text_mode: int = 0
    segment: int | None = None
    xobject: str | None = None


@dataclass
class PageContent:
    streams: list[bytes]
    operations: list[Operation] = field(default_factory=list)
    sites: list[Site] = field(default_factory=list)
    error: str | None = None
    has_watermark_section: bool = False

    @property
    def mappable(self) -> bool:
        return self.error is None


def _decode_name(raw: bytes) -> Name:
    if b"#" in raw:
        out = bytearray()
        index = 0
        while index < len(raw):
            if raw[index] == 0x23 and re.fullmatch(rb"[0-9A-Fa-f]{2}", raw[index + 1:index + 3]):
                out.append(int(raw[index + 1:index + 3], 16))
                index += 3
            else:
                out.append(raw[index])
                index += 1
        raw = bytes(out)
    return Name(raw.decode("latin-1"))


def _literal(data: bytes, pos: int) -> tuple[bytes, int]:
    depth, index, out, size = 1, pos + 1, bytearray(), len(data)
    while index < size:
        char = data[index]
        if char == 0x5C:
            index += 1
            if index >= size:
                break
            escaped = data[index]
            if escaped in _ESCAPES:
                out.append(_ESCAPES[escaped])
                index += 1
            elif 0x30 <= escaped <= 0x37:
                digits = re.match(rb"[0-7]{1,3}", data[index:index + 3]).group()
                out.append(int(digits, 8) & 0xFF)
                index += len(digits)
            elif escaped == 0x0D:
                index += 2 if data[index + 1:index + 2] == b"\n" else 1
            elif escaped == 0x0A:
                index += 1
            else:
                out.append(escaped)
                index += 1
        elif char == 0x28:
            depth += 1
            out.append(char)
            index += 1
        elif char == 0x29:
            depth -= 1
            index += 1
            if depth == 0:
                return bytes(out), index
            out.append(char)
        else:
            out.append(char)
            index += 1
    raise ContentSyntaxError("unterminated_string")


def _hex(data: bytes, pos: int) -> tuple[bytes, int]:
    end = data.find(b">", pos + 1)
    if end < 0:
        raise ContentSyntaxError("unterminated_hex_string")
    digits = bytes(byte for byte in data[pos + 1:end] if byte not in _WS)
    if _HEX.fullmatch(digits) is None:
        raise ContentSyntaxError("invalid_hex_string")
    if len(digits) % 2:
        digits += b"0"
    return bytes.fromhex(digits.decode("ascii")), end + 1


def _number(raw: bytes):
    match = _NUMBER.match(raw)
    if match is None or match.end() != len(raw):
        # PDFium reads the leading numeric prefix of malformed numbers.
        match = _NUMBER.match(raw)
        if match is None:
            return 0.0
        raw = match.group()
    try:
        return float(raw)
    except ValueError:
        return 0.0


def _is_number_start(char: int) -> bool:
    return 0x30 <= char <= 0x39 or char in b"+-."


class _Lexer:
    def __init__(self, data: bytes):
        self.data = data
        self.pos = 0

    def skip(self):
        self.pos = _WS_OR_COMMENT.match(self.data, self.pos).end()

    def token(self):
        """Return (kind, value, start, end) or None at end of data."""
        self.skip()
        data, pos = self.data, self.pos
        if pos >= len(data):
            return None
        char = data[pos]
        if char == 0x2F:  # /
            end = _REGULAR.match(data, pos + 1).end()
            self.pos = end
            return "value", _decode_name(data[pos + 1:end]), pos, end
        if char == 0x28:  # (
            value, end = _literal(data, pos)
            self.pos = end
            return "value", value, pos, end
        if char == 0x3C:  # <
            if data[pos + 1:pos + 2] == b"<":
                self.pos = pos + 2
                return "dict_open", None, pos, pos + 2
            value, end = _hex(data, pos)
            self.pos = end
            return "value", value, pos, end
        if char == 0x3E:  # >
            if data[pos + 1:pos + 2] == b">":
                self.pos = pos + 2
                return "dict_close", None, pos, pos + 2
            raise ContentSyntaxError("unexpected_delimiter")
        if char == 0x5B:
            self.pos = pos + 1
            return "array_open", None, pos, pos + 1
        if char == 0x5D:
            self.pos = pos + 1
            return "array_close", None, pos, pos + 1
        if char in b"{}":
            self.pos = pos + 1
            return "keyword", data[pos:pos + 1], pos, pos + 1
        if char == 0x29:
            raise ContentSyntaxError("unexpected_delimiter")
        end = _REGULAR.match(data, pos).end()
        word = data[pos:end]
        self.pos = end
        if _is_number_start(char):
            return "value", _number(word), pos, end
        if word == b"true":
            return "value", True, pos, end
        if word == b"false":
            return "value", False, pos, end
        if word == b"null":
            return "value", None, pos, end
        return "keyword", word, pos, end

    def object_after(self, first):
        """Complete a composite object whose opening token was ``first``."""
        kind = first[0]
        if kind == "value":
            return first[1], first[3]
        if kind == "array_open":
            items = []
            while True:
                token = self.token()
                if token is None:
                    raise ContentSyntaxError("unterminated_array")
                if token[0] == "array_close":
                    return items, token[3]
                if token[0] == "keyword":
                    raise ContentSyntaxError("keyword_in_array")
                items.append(self.object_after(token)[0])
        if kind == "dict_open":
            items = []
            while True:
                token = self.token()
                if token is None:
                    raise ContentSyntaxError("unterminated_dictionary")
                if token[0] == "dict_close":
                    break
                if token[0] == "keyword":
                    raise ContentSyntaxError("keyword_in_dictionary")
                items.append(self.object_after(token)[0])
            if len(items) % 2:
                raise ContentSyntaxError("odd_dictionary")
            result = {}
            for index in range(0, len(items), 2):
                if not isinstance(items[index], Name):
                    raise ContentSyntaxError("dictionary_key")
                result[items[index]] = items[index + 1]
            return result, token[3]
        raise ContentSyntaxError("unexpected_token")


_ABBREVIATED_COLOR = {"G": 1, "DeviceGray": 1, "CalGray": 1, "RGB": 3, "DeviceRGB": 3, "CalRGB": 3,
                      "Lab": 3, "CMYK": 4, "DeviceCMYK": 4, "I": 1, "Indexed": 1,
                      "Separation": 1, "Pattern": 1}


def _components(colorspace, resources) -> int:
    if isinstance(colorspace, list) and colorspace:
        family = str(colorspace[0])
        if family in ("I", "Indexed", "Separation"):
            return 1
        if family == "DeviceN" and len(colorspace) > 1 and isinstance(colorspace[1], list):
            return len(colorspace[1])
        if family in ("ICCBased",):
            raise ContentSyntaxError("inline_image_colorspace")
        if family in _ABBREVIATED_COLOR:
            return _ABBREVIATED_COLOR[family]
        raise ContentSyntaxError("inline_image_colorspace")
    if isinstance(colorspace, Name):
        if str(colorspace) in _ABBREVIATED_COLOR:
            return _ABBREVIATED_COLOR[str(colorspace)]
        spaces = resolve(resources.get("/ColorSpace")) if resources is not None else None
        value = resolve(spaces.get("/" + colorspace)) if isinstance(spaces, DictionaryObject) else None
        if isinstance(value, NameObject):
            return _ABBREVIATED_COLOR.get(str(value)[1:], 3)
        if isinstance(value, ArrayObject) and value:
            family = str(resolve(value[0]))[1:]
            if family == "ICCBased" and len(value) > 1:
                return int(resolve(resolve(value[1]).get("/N", 3)))
            if family == "DeviceN" and len(value) > 1:
                return len(resolve(value[1]))
            if family in _ABBREVIATED_COLOR:
                return _ABBREVIATED_COLOR[family]
        raise ContentSyntaxError("inline_image_colorspace")
    return 3 if colorspace is None else 3


def _inline_image(lexer: _Lexer, resources) -> tuple[dict, int]:
    """Parse ``BI <dict> ID <data> EI``; returns (settings, end offset after EI)."""
    items = []
    while True:
        token = lexer.token()
        if token is None:
            raise ContentSyntaxError("unterminated_inline_image")
        if token[0] == "keyword":
            if token[1] != b"ID":
                raise ContentSyntaxError("inline_image_dictionary")
            break
        items.append(lexer.object_after(token)[0])
    if len(items) % 2:
        raise ContentSyntaxError("inline_image_dictionary")
    settings = {str(items[index]): items[index + 1] for index in range(0, len(items), 2)}
    data = lexer.data
    start = token[3]
    if start < len(data) and data[start] in _WS:
        start += 1
    filters = settings.get("F", settings.get("Filter"))
    if filters is None or filters == []:
        if settings.get("IM", settings.get("ImageMask")) is True:
            components, bits = 1, 1
        else:
            components = _components(settings.get("CS", settings.get("ColorSpace")), resources)
            bits = settings.get("BPC", settings.get("BitsPerComponent"))
        width = settings.get("W", settings.get("Width"))
        height = settings.get("H", settings.get("Height"))
        if not all(isinstance(value, float) and value > 0 and value == int(value)
                   for value in (width, height, bits)):
            raise ContentSyntaxError("inline_image_dimensions")
        length = ((int(width) * int(bits) * components + 7) // 8) * int(height)
        position = start + length
        lexer.pos = position
        while True:
            token = lexer.token()
            if token is None:
                raise ContentSyntaxError("inline_image_end")
            if token[0] == "keyword" and token[1] == b"EI":
                return settings, token[3]
            if token[0] == "keyword":
                raise ContentSyntaxError("inline_image_end")
    match = _INLINE_END.search(data, start)
    if match is None:
        raise ContentSyntaxError("inline_image_end")
    lexer.pos = match.end()
    return settings, match.end()


def tokenize(streams: list[bytes], resources) -> list[Operation]:
    operations = []
    operands, spans = [], []
    for stream_index, data in enumerate(streams):
        lexer = _Lexer(data)
        while True:
            token = lexer.token()
            if token is None:
                break
            kind, value, start, end = token
            if kind == "keyword":
                if value == b"BI":
                    settings, finish = _inline_image(lexer, resources)
                    operations.append(Operation(b"BI", [settings], [], stream_index, start, finish))
                    operands, spans = [], []
                    continue
                if value in (b"ID", b"EI", b"{", b"}"):
                    raise ContentSyntaxError("unexpected_keyword")
                operations.append(Operation(value, operands[-MAX_PARAMS:], spans[-MAX_PARAMS:],
                                            stream_index, start, end,
                                            (spans[0][0], spans[0][1]) if spans else None))
                operands, spans = [], []
                continue
            if kind in ("array_close", "dict_close"):
                raise ContentSyntaxError("unbalanced_delimiter")
            obj, finish = lexer.object_after(token)
            operands.append(obj)
            spans.append((stream_index, start, finish))
    return operations


def _param(operation: Operation, index_from_end: int):
    """PDFium's ``GetObject(i)``: operands are addressed from the last one."""
    if index_from_end >= len(operation.operands):
        return None
    return operation.operands[len(operation.operands) - 1 - index_from_end]


def _number_param(operation, index_from_end):
    value = _param(operation, index_from_end)
    return value if isinstance(value, float) else 0.0


def _string_param(operation, index_from_end):
    value = _param(operation, index_from_end)
    if isinstance(value, (bytes, Name)):
        return value
    return None


def _resource(resources, category, name):
    if resources is None or name is None:
        return None
    group = resolve(resources.get(category))
    if not isinstance(group, DictionaryObject):
        return None
    return resolve(group.get("/" + str(name)))


def is_watermark_properties(properties) -> bool:
    # DictionaryObject is itself a dict subclass: test it first.
    if isinstance(properties, DictionaryObject):
        subtype = resolve(properties.get("/Subtype"))
        return isinstance(subtype, NameObject) and str(subtype) == "/Watermark"
    if isinstance(properties, dict):
        subtype = properties.get(Name("Subtype"))
        return isinstance(subtype, Name) and str(subtype) == "Watermark"
    return False


class _Path:
    def __init__(self):
        self.points = []  # [type, closed]
        self.start = (0.0, 0.0)
        self.current = (0.0, 0.0)

    def add(self, point, kind):
        if (kind == "M" and self.points and not self.points[-1][1] and self.points[-1][0] == "M"
                and self.current == point):
            return
        self.current = point
        if kind == "M":
            self.start = point
            if self.points and self.points[-1][0] == "M" and not self.points[-1][1]:
                return
        elif not self.points:
            return
        self.points.append(["M" if kind == "M" else kind, False])

    def add_closed(self, point):
        self.current = point
        if self.points:
            self.points.append(["L", True])

    def close(self):
        if not self.points:
            return
        if self.start != self.current:
            self.add_closed(self.start)
        else:
            self.points[-1][1] = True

    def finish(self, paints: bool) -> bool:
        points, self.points = self.points, []
        if len(points) < 2:
            return False
        return paints


def walk(operations: list[Operation], resources) -> tuple[list[Site], bool]:
    """Replay PDFium's page-object creation; returns (sites, has_watermark_section)."""
    sites = []
    state = {"font": False, "mode": 0}
    stack = []
    marks = []  # watermark flag per PDFium mark entry
    path = _Path()
    segment = 0
    watermark_seen = False
    for index, operation in enumerate(operations):
        op = operation.operator
        count = len(operation.operands)

        def site(kind, **extra):
            sites.append(Site(kind, index, len(marks), any(marks), **extra))

        if op == b"q":
            stack.append(dict(state))
        elif op == b"Q":
            if stack:
                state = stack.pop()
        elif op in (b"BT", b"ET", b"Td", b"TD", b"Tm", b"T*"):
            segment += 1
        elif op == b"Tf":
            state["font"] = True
        elif op == b"Tr":
            state["mode"] = int(_number_param(operation, 0))
        elif op == b"gs":
            graphics = _resource(resources, "/ExtGState", _string_param(operation, 0))
            if isinstance(graphics, DictionaryObject) and "/Font" in graphics:
                state["font"] = True
        elif op in (b"Tj", b"'", b'"'):
            if op == b'"' and count != 3:
                continue
            if op != b"Tj":
                segment += 1
            text = _string_param(operation, 0)
            if text and state["font"]:
                site("text", text_mode=state["mode"], segment=segment)
        elif op == b"TJ":
            array = _param(operation, 0)
            if isinstance(array, list) and any(isinstance(item, bytes) for item in array) and state["font"]:
                site("text", text_mode=state["mode"], segment=segment)
        elif op == b"m":
            if count == 2:
                path.add((_number_param(operation, 1), _number_param(operation, 0)), "M")
        elif op == b"l":
            if count == 2:
                path.add((_number_param(operation, 1), _number_param(operation, 0)), "L")
        elif op == b"c":
            if count == 6:
                for pair in ((5, 4), (3, 2), (1, 0)):
                    path.add((_number_param(operation, pair[0]), _number_param(operation, pair[1])), "B")
        elif op in (b"v", b"y"):
            if count == 4:
                if op == b"v":
                    path.add(path.current, "B")
                    path.add((_number_param(operation, 3), _number_param(operation, 2)), "B")
                    path.add((_number_param(operation, 1), _number_param(operation, 0)), "B")
                else:
                    path.add((_number_param(operation, 3), _number_param(operation, 2)), "B")
                    path.add((_number_param(operation, 1), _number_param(operation, 0)), "B")
                    path.add((_number_param(operation, 1), _number_param(operation, 0)), "B")
        elif op == b"re":
            x, y = _number_param(operation, 3), _number_param(operation, 2)
            w, h = _number_param(operation, 1), _number_param(operation, 0)
            path.add((x, y), "M")
            path.add((x + w, y), "L")
            path.add((x + w, y + h), "L")
            path.add((x, y + h), "L")
            path.add_closed((x, y))
        elif op == b"h":
            path.close()
        elif op in PATH_PAINT:
            close_first, stroke = PATH_PAINT[op]
            if close_first:
                path.close()
            paints = op != b"n"
            if path.finish(paints):
                site("path")
        elif op == b"Do":
            name = _string_param(operation, 0)
            xobject = _resource(resources, "/XObject", name)
            if isinstance(xobject, StreamObject):
                subtype = str(resolve(xobject.get("/Subtype")))
                if subtype == "/Form":
                    site("form", xobject=str(name))
                elif subtype == "/Image":
                    site("image", xobject=str(name))
        elif op == b"BI":
            site("image")
        elif op == b"sh":
            shading = _resource(resources, "/Shading", _string_param(operation, 0))
            if isinstance(shading, (DictionaryObject, StreamObject)):
                site("shading")
        elif op == b"BMC":
            marks.append(False)
        elif op == b"BDC":
            properties = _param(operation, 0)
            tag = _string_param(operation, 1)
            if isinstance(properties, Name):
                resolved = _resource(resources, "/Properties", properties)
                if not isinstance(resolved, DictionaryObject):
                    continue
                properties = resolved
            elif not isinstance(properties, dict):
                continue
            flag = tag == "Artifact" and is_watermark_properties(properties)
            watermark_seen = watermark_seen or flag
            marks.append(flag)
        elif op == b"EMC":
            if marks:
                marks.pop()
    return sites, watermark_seen


def page_streams(page) -> tuple[list, bool]:
    """Return (stream objects or None, contents_is_array) for a pypdf page."""
    contents = resolve(page.get("/Contents"))
    if contents is None:
        return [], True
    if isinstance(contents, ArrayObject):
        return [resolve(item) if isinstance(resolve(item), StreamObject) else None for item in contents], True
    if isinstance(contents, StreamObject):
        return [contents], False
    return [], True


def analyze_page(page, *, require_watermark_hint: bool = False) -> PageContent:
    """Tokenize and replay a pypdf page's content (all streams, in order)."""
    objects, _ = page_streams(page)
    streams = [stream.get_data() if stream is not None else b"" for stream in objects]
    content = PageContent(streams)
    if require_watermark_hint and not any(b"Artifact" in data for data in streams):
        return content
    resources = resolve(page.get("/Resources"))
    if not isinstance(resources, DictionaryObject):
        resources = None
    try:
        content.operations = tokenize(streams, resources)
        content.sites, content.has_watermark_section = walk(content.operations, resources)
    except ContentSyntaxError as error:
        content.error = "content_" + str(error)
    except (ValueError, TypeError, AttributeError, KeyError, IndexError):
        content.error = "content_unparseable"
    return content


def operator_sequence(operations) -> list[bytes]:
    return [b"INLINE IMAGE" if operation.operator == b"BI" else operation.operator
            for operation in operations]


# --- editing -----------------------------------------------------------------

class EditError(ValueError):
    pass


def removal_edit(content: PageContent, site: Site):
    """Return (stream, start, end, replacement) that removes one site's painting."""
    operation = content.operations[site.op_index]
    op = operation.operator
    if not operation.single_stream():
        raise EditError("operator_spans_content_streams")
    stream = operation.stream
    if site.kind == "path":
        return stream, operation.start, operation.end, b"n"
    if site.kind in ("form", "image", "shading"):
        start = operation.first[1]
        return stream, start, operation.end, b" "
    if site.kind == "text":
        start = operation.first[1]
        if op in (b"Tj", b"TJ"):
            return stream, start, operation.end, b" "
        if op == b"'":
            return stream, start, operation.end, b" T* "
        if op == b'"':
            data = content.streams[stream]
            spans = operation.spans[-3:]
            word, char = (data[span[1]:span[2]] for span in spans[:2])
            return stream, start, operation.end, b" " + word + b" Tw " + char + b" Tc T* "
    raise EditError("unsupported_site")


def text_dependency_blocked(content: PageContent, removed: set[int]) -> set[int]:
    """Sites (by index) whose removal would move later, retained text.

    ``Tj``/``TJ`` advance the text matrix but not the line matrix. Removing a
    show operator is invisible to later text only when every later show in the
    same line segment (up to the next ``Td``/``TD``/``Tm``/``T*``/``'``/``"``/``BT``)
    is removed too.
    """
    blocked = set()
    by_segment = {}
    for index, site in enumerate(content.sites):
        if site.kind == "text":
            by_segment.setdefault(site.segment, []).append(index)
    for indices in by_segment.values():
        kept = [index for index in indices if index not in removed]
        if not kept:
            continue
        last_kept = max(kept)
        blocked.update(index for index in indices if index in removed and index < last_kept)
    return blocked


def splice(content: PageContent, edits) -> dict[int, bytes]:
    """Apply non-overlapping byte edits; returns {stream index: new bytes}."""
    by_stream = {}
    for stream, start, end, replacement in edits:
        by_stream.setdefault(stream, []).append((start, end, replacement))
    result = {}
    for stream, items in by_stream.items():
        items.sort()
        data = content.streams[stream]
        out, position = bytearray(), 0
        for start, end, replacement in items:
            if start < position or end > len(data) or start > end:
                raise EditError("overlapping_edits")
            out += data[position:start]
            out += replacement
            position = end
        out += data[position:]
        result[stream] = bytes(out)
    return result

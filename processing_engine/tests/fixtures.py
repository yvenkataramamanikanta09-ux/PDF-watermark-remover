"""Deterministic, locally authored PDF fixtures for the Stage 6A engine tests.

Importing this module creates no files.  Call :func:`create_fixture` explicitly
after the PDF workflow marker has been run.  No third-party PDF assets, system
fonts, random identifiers, timestamps, or image encoders are needed.

The default watermark rectangle is ``(150, 320, 450, 440)`` in raw PDF user
space.  For cropped pages its bounds stay at the same fractions of the crop:
25--75 percent horizontally and 40--55 percent vertically.  Every page has
three ordinary annotations, in addition to the optional watermark and ambiguous
stamp.  A synthetic signature field is a test marker, never a valid signature.
"""

from __future__ import annotations

import math
from collections.abc import Sequence
from pathlib import Path

from pypdf import PageObject, PdfWriter
from pypdf.generic import (
    ArrayObject,
    ByteStringObject,
    DecodedStreamObject,
    DictionaryObject,
    FloatObject,
    IndirectObject,
    NameObject,
    NumberObject,
    RectangleObject,
    TextStringObject,
)


Box = tuple[float, float, float, float]
MEDIA_BOX: Box = (0.0, 0.0, 600.0, 800.0)
DEFAULT_WATERMARK_RECT: Box = (150.0, 320.0, 450.0, 440.0)
ORDINARY_ANNOTATIONS_PER_PAGE = 3
ENCRYPTION_PASSWORD = "test-secret"
_FILE_ID = bytes.fromhex("06360a0102030405060708090a0b0c0d")


class _FixtureWriter(PdfWriter):
    """Keep pypdf's RC4 encryption setup from generating random file IDs."""

    def generate_file_identifiers(self) -> None:
        # pypdf 7.1.0 encrypt() calls this method even when _ID already exists.
        self._ID = ArrayObject(
            [ByteStringObject(_FILE_ID), ByteStringObject(_FILE_ID)]
        )


def _number(value: float) -> str:
    """Use stable decimal operands in our own, uncompressed content streams."""
    return f"{value:.6f}".rstrip("0").rstrip(".") or "0"


def _validated_crop(value: Sequence[float]) -> Box:
    if isinstance(value, (str, bytes)) or len(value) != 4:
        raise ValueError("A crop must have four numeric bounds.")
    if any(isinstance(item, bool) or not isinstance(item, (int, float))
           or not math.isfinite(item) for item in value):
        raise ValueError("Crop bounds must be finite numbers.")
    left, bottom, right, top = (float(item) for item in value)
    if not (0 <= left < right <= 600 and 0 <= bottom < top <= 800):
        raise ValueError("A crop must have positive area inside the media box.")
    return left, bottom, right, top


def _crop_relative_rect(crop: Box, canonical: Box) -> Box:
    left, bottom, right, top = crop
    width, height = right - left, top - bottom
    x1, y1, x2, y2 = canonical
    return (
        left + width * x1 / 600,
        bottom + height * y1 / 800,
        left + width * x2 / 600,
        bottom + height * y2 / 800,
    )


def watermark_rect(crop: Sequence[float] = MEDIA_BOX) -> Box:
    """Return the explicit watermark's unrotated PDF-space rectangle."""
    return _crop_relative_rect(_validated_crop(crop), DEFAULT_WATERMARK_RECT)


def _rgb(values: tuple[float, float, float]) -> ArrayObject:
    return ArrayObject([FloatObject(value) for value in values])


def _form(
    writer: PdfWriter,
    font: IndirectObject,
    content: str,
    width: float,
    height: float,
) -> IndirectObject:
    appearance = DecodedStreamObject()
    appearance.set_data(content.encode("ascii"))
    appearance.update({
        NameObject("/Type"): NameObject("/XObject"),
        NameObject("/Subtype"): NameObject("/Form"),
        NameObject("/FormType"): NumberObject(1),
        NameObject("/BBox"): RectangleObject((0, 0, width, height)),
        NameObject("/Resources"): DictionaryObject({
            NameObject("/Font"): DictionaryObject({NameObject("/F1"): font}),
        }),
    })
    return writer._add_object(appearance)


def _stamp_appearance(
    writer: PdfWriter, font: IndirectObject, *, ambiguous: bool = False,
) -> IndirectObject:
    color = "0.78 0.35 0.02" if ambiguous else "0.04 0.52 0.18"
    label = "REVIEW" if ambiguous else "APPROVED"
    return _form(
        writer, font,
        f"q\n{color} RG\n{color} rg\n3 w\n3 3 154 54 re S\n"
        f"BT /F1 23 Tf 12 21 Td ({label}) Tj ET\nQ\n",
        160, 60,
    )


def _add_annotation(
    writer: PdfWriter,
    page: PageObject,
    *,
    subtype: str,
    rect: Box,
    name: str,
    fields: dict[NameObject, object] | None = None,
) -> IndirectObject:
    annotation = DictionaryObject({
        NameObject("/Type"): NameObject("/Annot"),
        NameObject("/Subtype"): NameObject(subtype),
        NameObject("/Rect"): RectangleObject(rect),
        NameObject("/NM"): TextStringObject(name),
        NameObject("/F"): NumberObject(4),  # Print, with no hidden flags.
        NameObject("/P"): page.indirect_reference,
    })
    if fields:
        annotation.update(fields)
    reference = writer._add_object(annotation)
    page[NameObject("/Annots")].append(reference)
    return reference


ARTIFACT_KINDS = ("separate", "named", "inline")
# Canonical (600 x 800) areas, mapped into each page's crop like the watermark.
OVERLAY_SELECTION: Box = (170.0, 310.0, 440.0, 500.0)
ARTIFACT_SELECTION: Box = (140.0, 310.0, 460.0, 450.0)


def selection_rect(crop: Sequence[float] = MEDIA_BOX, canonical: Box = OVERLAY_SELECTION) -> Box:
    """Crop-relative PDF rectangle for a canonical selection area."""
    return _crop_relative_rect(_validated_crop(crop), canonical)


def _crop_matrix(crop: Box) -> str:
    left, bottom, right, top = crop
    return " ".join(_number(value) for value in (
        (right - left) / 600, 0, 0, (top - bottom) / 800, left, bottom,
    ))


def _artifact_section(kind: str) -> str:
    """Acrobat "Add Watermark" style marked content, in canonical coordinates."""
    properties = "/MC0" if kind == "named" else "<</Subtype /Watermark /Type /Pagination>>"
    if kind == "inline":
        # Text objects directly inside the artifact, in the body stream.
        return (f"/Artifact {properties} BDC\nq /GSwm gs 0.86 0.06 0.08 rg\n"
                "BT /F1 36 Tf 0.9397 0.342 -0.342 0.9397 175 330 Tm (CONFIDENTIAL) Tj ET\n"
                "BT /F1 18 Tf 0.9397 0.342 -0.342 0.9397 230 325 Tm (do not copy) Tj ET\nQ\nEMC\n")
    return (f"/Artifact {properties} BDC\nq /GSwm gs 1 0 0 1 150 320 cm /FmWM Do Q\nEMC\n")


def _overlay() -> str:
    """Ordinary page content (not an artifact) that a user would select."""
    return ("q /GSov gs 0.85 0.1 0.1 rg\n"
            "BT /F1 40 Tf 0.866 0.5 -0.5 0.866 200 330 Tm (DRAFT COPY) Tj ET\n"
            "q 40 0 0 40 300 380 cm /ImOv Do Q\nQ\n")


def _page_content(page_number: int, crop: Box, extra: str = "") -> bytes:
    matrix = _crop_matrix(crop)
    # A canonical layout is scaled into the crop without changing /Rotate.
    return (
        f"q\n{matrix} cm\n"
        "0.12 0.16 0.22 rg\n"
        f"BT /F1 22 Tf 60 728 Td (Ordinary report page {page_number}) Tj ET\n"
        "BT /F1 12 Tf 60 700 Td (Selectable text and original page artwork) Tj ET\n"
        "q 72 0 0 72 60 610 cm /Im1 Do Q\n"
        "BT /F1 11 Tf 146 641 Td (Embedded RGB image) Tj ET\n"
        # The chart crosses behind the entire explicit watermark area.
        "0.91 0.95 1 rg\n120 240 360 280 re f\n"
        "0.10 0.36 0.78 RG\n2 w\n120 240 360 280 re S\n"
        "0.55 0.72 0.93 RG\n0.7 w\n"
        "120 310 m 480 310 l S\n120 380 m 480 380 l S\n"
        "120 450 m 480 450 l S\n"
        "0.18 0.48 0.86 rg\n"
        "155 240 46 100 re f\n232 240 46 170 re f\n"
        "309 240 46 140 re f\n386 240 46 230 re f\n"
        "0.04 0.22 0.58 RG\n4 w\n"
        "140 285 m 210 365 l 280 335 l 350 425 l 455 485 l S\n"
        "0.12 0.16 0.22 rg\n"
        "BT /F1 12 Tf 120 219 Td (Blue chart must survive annotation removal) Tj ET\n"
        f"{extra}"
        "0.10 0.28 0.68 rg\n"
        "BT /F1 12 Tf 60 105 Td (Keep this ordinary link) Tj ET\n"
        "0.12 0.16 0.22 rg\n"
        "BT /F1 10 Tf 60 66 Td (Locally authored Stage 6A test fixture) Tj ET\n"
        "Q\n"
    ).encode("ascii")


def _add_ordinary_annotations(
    writer: PdfWriter, page: PageObject, page_number: int, crop: Box,
    approved_appearance: IndirectObject,
) -> None:
    _add_annotation(
        writer, page, subtype="/Link",
        rect=_crop_relative_rect(crop, (60, 100, 250, 123)),
        name=f"stage6-link-{page_number}",
        fields={
            NameObject("/Border"): ArrayObject([NumberObject(0)] * 3),
            NameObject("/A"): DictionaryObject({
                NameObject("/S"): NameObject("/URI"),
                NameObject("/URI"): TextStringObject("https://example.com/keep"),
            }),
        },
    )
    _add_annotation(
        writer, page, subtype="/Text",
        rect=_crop_relative_rect(crop, (60, 560, 84, 584)),
        name=f"stage6-note-{page_number}",
        fields={
            NameObject("/Name"): NameObject("/Comment"),
            NameObject("/Contents"): TextStringObject(
                "Discussion: the word watermark appears in this ordinary note. "
                "Keep this review comment."
            ),
            NameObject("/C"): _rgb((1, 0.8, 0.1)),
        },
    )
    _add_annotation(
        writer, page, subtype="/Stamp",
        rect=_crop_relative_rect(crop, (380, 650, 540, 710)),
        name=f"stage6-approved-{page_number}",
        fields={
            NameObject("/Name"): NameObject("/Approved"),
            NameObject("/Contents"): TextStringObject("Ordinary approval stamp."),
            NameObject("/AP"): DictionaryObject({
                NameObject("/N"): approved_appearance,
            }),
        },
    )


def _nest_pages(writer: PdfWriter) -> None:
    """Insert a real intermediate /Pages node, retaining indirect leaves."""
    root_reference = writer._pages
    root = root_reference.get_object()
    leaves = ArrayObject(list(root["/Kids"]))
    branch = DictionaryObject({
        NameObject("/Type"): NameObject("/Pages"),
        NameObject("/Parent"): root_reference,
        NameObject("/Count"): NumberObject(len(leaves)),
        NameObject("/Kids"): leaves,
    })
    branch_reference = writer._add_object(branch)
    for leaf in leaves:
        leaf.get_object()[NameObject("/Parent")] = branch_reference
    root[NameObject("/Kids")] = ArrayObject([branch_reference])


def _add_synthetic_signature(writer: PdfWriter) -> None:
    """Add structural signature markers with deliberately invalid CMS data."""
    value = writer._add_object(DictionaryObject({
        NameObject("/Type"): NameObject("/Sig"),
        NameObject("/Filter"): NameObject("/Adobe.PPKLite"),
        NameObject("/SubFilter"): NameObject("/adbe.pkcs7.detached"),
        NameObject("/ByteRange"): ArrayObject([
            NumberObject(0), NumberObject(1), NumberObject(2), NumberObject(3),
        ]),
        NameObject("/Contents"): ByteStringObject(b"STAGE6_SYNTHETIC_NOT_A_SIGNATURE"),
        NameObject("/Reason"): TextStringObject(
            "Synthetic signature detection fixture; not a valid signature."
        ),
    }))
    field = writer._add_object(DictionaryObject({
        NameObject("/FT"): NameObject("/Sig"),
        NameObject("/T"): TextStringObject("stage6-synthetic-signature"),
        NameObject("/V"): value,
    }))
    writer._root_object[NameObject("/AcroForm")] = writer._add_object(
        DictionaryObject({
            NameObject("/Fields"): ArrayObject([field]),
            NameObject("/SigFlags"): NumberObject(3),
        })
    )


def create_marker_fixture(path: Path, *, rotation: int, crop: Sequence[float],
                          marker: Box, media: Box = MEDIA_BOX) -> Path:
    """One page, white, with a single black square at raw PDF ``marker``.

    ``crop`` is written verbatim, so it may extend beyond the media box.
    """
    writer = PdfWriter()
    page = writer.add_blank_page(width=media[2] - media[0], height=media[3] - media[1])
    page.mediabox = RectangleObject(media)
    page[NameObject("/CropBox")] = ArrayObject([FloatObject(value) for value in crop])
    page[NameObject("/Rotate")] = NumberObject(rotation)
    left, bottom, right, top = marker
    content = DecodedStreamObject()
    content.set_data(f"0 0 0 rg {_number(left)} {_number(bottom)} {_number(right - left)} "
                     f"{_number(top - bottom)} re f\n".encode("ascii"))
    page[NameObject("/Contents")] = writer._add_object(content)
    path = Path(path)
    with path.open("wb") as output:
        writer.write(output)
    writer.close()
    return path


def create_fixture(
    path: Path,
    *,
    page_count: int = 1,
    rotations: Sequence[int] | None = None,
    crops: Sequence[Sequence[float] | None] | None = None,
    watermarks: bool = True,
    malformed_appearance: bool = False,
    stamp_hint: bool = False,
    encrypted: bool = False,
    signed: bool = False,
    nested_pages: bool = False,
    artifact: str | None = None,
    overlay: bool = False,
) -> Path:
    """Write one deterministic PDF and return its path.

    ``rotations`` and ``crops`` must contain one value per page when supplied;
    a ``None`` crop means the default media box.  Rotation is clockwise and
    does not alter the raw annotation coordinates.  ``malformed_appearance``
    uses a visible appearance-state dictionary that Stage 6A intentionally
    cannot process.  ``stamp_hint`` adds an ambiguous /Stamp named /Watermark,
    which must be reported as unsupported rather than automatically removed.

    ``signed`` adds synthetic signature structure only.  ``encrypted`` uses
    RC4-128 with user and owner password ``test-secret``; it requires no AES
    dependency.  Input assets and network services are never accessed.

    ``artifact`` adds an Acrobat-style ``/Artifact <</Subtype /Watermark>>``
    page-content watermark: ``"separate"`` (a Form XObject in its own appended
    content stream, inline property dictionary, as Acrobat writes it),
    ``"named"`` (same, via a ``/Properties`` resource) or ``"inline"`` (text
    objects inside the body stream).  ``overlay`` adds ordinary (unmarked)
    semi-transparent rotated text plus an image inside ``OVERLAY_SELECTION``.
    """
    if artifact is not None and artifact not in ARTIFACT_KINDS:
        raise ValueError("Unknown artifact kind.")
    if isinstance(page_count, bool) or not isinstance(page_count, int) or page_count < 1:
        raise ValueError("page_count must be a positive integer.")
    page_rotations = list(rotations) if rotations is not None else [0] * page_count
    page_crops = list(crops) if crops is not None else [None] * page_count
    if len(page_rotations) != page_count or len(page_crops) != page_count:
        raise ValueError("rotations and crops must have one entry per page.")
    for rotation in page_rotations:
        if isinstance(rotation, bool) or not isinstance(rotation, int) or rotation % 90:
            raise ValueError("Page rotations must be integer multiples of 90 degrees.")
    normalized_crops = [
        _validated_crop(crop if crop is not None else MEDIA_BOX)
        for crop in page_crops
    ]

    writer = _FixtureWriter()
    writer.pdf_header = "%PDF-1.7"
    writer.generate_file_identifiers()
    writer.add_metadata({
        "/Title": "Stage 6A locally authored regression fixture",
        "/Author": "Local test suite",
        "/Creator": "Stage 6A deterministic fixture builder",
        "/Producer": "Stage 6A deterministic fixture builder",
        "/Subject": "Selectable text, embedded image, chart, and annotations",
    })
    font = writer._add_object(DictionaryObject({
        NameObject("/Type"): NameObject("/Font"),
        NameObject("/Subtype"): NameObject("/Type1"),
        NameObject("/BaseFont"): NameObject("/Helvetica"),
        NameObject("/Encoding"): NameObject("/WinAnsiEncoding"),
    }))
    image = DecodedStreamObject()
    image.set_data(bytes(
        component
        for y in range(8)
        for x in range(8)
        for component in (32 + x * 24, 48 + y * 22, 192 if (x + y) % 2 else 96)
    ))
    image.update({
        NameObject("/Type"): NameObject("/XObject"),
        NameObject("/Subtype"): NameObject("/Image"),
        NameObject("/Width"): NumberObject(8),
        NameObject("/Height"): NumberObject(8),
        NameObject("/ColorSpace"): NameObject("/DeviceRGB"),
        NameObject("/BitsPerComponent"): NumberObject(8),
    })
    image_reference = writer._add_object(image)
    approved_appearance = _stamp_appearance(writer, font)
    ambiguous_appearance = _stamp_appearance(writer, font, ambiguous=True) if stamp_hint else None
    watermark_appearance = _form(
        writer, font,
        "q\n0.86 0.06 0.08 RG\n0.86 0.06 0.08 rg\n"
        "3 w\n3 3 294 114 re S\n"
        "BT /F1 39 Tf 23 46 Td (WATERMARK) Tj ET\nQ\n",
        300, 120,
    ) if watermarks else None
    artifact_form = _form(
        writer, font,
        "q 0.86 0.06 0.08 rg 0.86 0.06 0.08 RG 2 w\n"
        "BT /F1 34 Tf 0.9397 0.342 -0.342 0.9397 20 12 Tm (CONFIDENTIAL) Tj ET\n"
        "10 6 m 290 108 l S\nQ\n",
        300, 120,
    ) if artifact in ("separate", "named") else None
    translucent = writer._add_object(DictionaryObject({
        NameObject("/Type"): NameObject("/ExtGState"),
        NameObject("/ca"): FloatObject(0.35), NameObject("/CA"): FloatObject(0.35),
    })) if artifact or overlay else None
    overlay_image = None
    if overlay:
        overlay_image = DecodedStreamObject()
        overlay_image.set_data(bytes(
            component for y in range(4) for x in range(4)
            for component in ((200, 30, 30) if (x + y) % 2 else (250, 210, 40))))
        overlay_image.update({
            NameObject("/Type"): NameObject("/XObject"),
            NameObject("/Subtype"): NameObject("/Image"),
            NameObject("/Width"): NumberObject(4),
            NameObject("/Height"): NumberObject(4),
            NameObject("/ColorSpace"): NameObject("/DeviceRGB"),
            NameObject("/BitsPerComponent"): NumberObject(8),
        })
        overlay_image = writer._add_object(overlay_image)

    for index, crop in enumerate(normalized_crops):
        page_number = index + 1
        page = writer.add_blank_page(width=600, height=800)
        page.cropbox = RectangleObject(crop)
        page[NameObject("/Rotate")] = NumberObject(page_rotations[index] % 360)
        xobjects = DictionaryObject({NameObject("/Im1"): image_reference})
        resources = DictionaryObject({
            NameObject("/Font"): DictionaryObject({NameObject("/F1"): font}),
            NameObject("/XObject"): xobjects,
        })
        if translucent is not None:
            resources[NameObject("/ExtGState")] = DictionaryObject({
                NameObject("/GSwm"): translucent, NameObject("/GSov"): translucent})
        if artifact_form is not None:
            xobjects[NameObject("/FmWM")] = artifact_form
        if overlay_image is not None:
            xobjects[NameObject("/ImOv")] = overlay_image
        if artifact == "named":
            resources[NameObject("/Properties")] = DictionaryObject({
                NameObject("/MC0"): DictionaryObject({
                    NameObject("/Subtype"): NameObject("/Watermark"),
                    NameObject("/Type"): NameObject("/Pagination"),
                })})
        page[NameObject("/Resources")] = resources
        extra = (_artifact_section(artifact) if artifact == "inline" else "") + (_overlay() if overlay else "")
        content = DecodedStreamObject()
        content.set_data(_page_content(page_number, crop, extra))
        if artifact in ("separate", "named"):
            appended = DecodedStreamObject()
            appended.set_data(f"q {_crop_matrix(crop)} cm\n{_artifact_section(artifact)}Q\n".encode("ascii"))
            page[NameObject("/Contents")] = ArrayObject([
                writer._add_object(content), writer._add_object(appended)])
        else:
            page[NameObject("/Contents")] = writer._add_object(content)
        page[NameObject("/Annots")] = ArrayObject()
        _add_ordinary_annotations(writer, page, page_number, crop, approved_appearance)

        if watermarks:
            normal_appearance = (
                DictionaryObject({NameObject("/Visible"): watermark_appearance})
                if malformed_appearance else watermark_appearance
            )
            watermark_fields = {
                NameObject("/Contents"): TextStringObject("Locally authored explicit watermark."),
                NameObject("/AP"): DictionaryObject({NameObject("/N"): normal_appearance}),
                NameObject("/C"): _rgb((0.86, 0.06, 0.08)),
            }
            if malformed_appearance:
                watermark_fields[NameObject("/AS")] = NameObject("/Visible")
            _add_annotation(
                writer, page, subtype="/Watermark", rect=watermark_rect(crop),
                name=f"stage6-watermark-{page_number}", fields=watermark_fields,
            )
        if stamp_hint:
            _add_annotation(
                writer, page, subtype="/Stamp",
                rect=_crop_relative_rect(crop, (380, 150, 540, 210)),
                name=f"stage6-ambiguous-stamp-{page_number}",
                fields={
                    NameObject("/Name"): NameObject("/Watermark"),
                    NameObject("/Contents"): TextStringObject("Ambiguous stamp; keep unless supported."),
                    NameObject("/AP"): DictionaryObject({NameObject("/N"): ambiguous_appearance}),
                },
            )

    if nested_pages:
        _nest_pages(writer)
    if signed:
        _add_synthetic_signature(writer)
    if encrypted:
        writer.encrypt(ENCRYPTION_PASSWORD, algorithm="RC4-128")

    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as output:
        writer.write(output)
    writer.close()
    return path

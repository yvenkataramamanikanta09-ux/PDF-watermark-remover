"""Produce and independently verify four real before/after PDF pages.

Run with the engine's [verify] extra. All documents are locally generated;
this tool never accepts a user's PDF as input and never overwrites outputs.
"""
from contextlib import closing
import argparse
import importlib.metadata
import json
from pathlib import Path
import platform
import sys
import tempfile

import pypdfium2 as pdfium
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tests"))
from fixtures import create_fixture  # noqa: E402
from verification import observations, sha256, structure  # noqa: E402
from pdf_watermark_engine.api import PdfWatermarkEngine  # noqa: E402
from pdf_watermark_engine.models import Outcome  # noqa: E402


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=Path("output/pdf"))
    args = parser.parse_args()
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    before, after = (output / name for name in ("stage6a-before.pdf", "stage6a-after.pdf"))
    manifest, comparison = (output / name for name in ("stage6a-evidence.json", "stage6a-comparison.png"))
    if any(path.exists() for path in (before, after, manifest, comparison)):
        parser.error("Choose a new output directory; existing evidence is never overwritten.")
    options = dict(page_count=4, rotations=[0, 90, 180, 270],
                   crops=[(0, 0, 600, 800), (30, 70, 550, 750),
                          (100, 120, 510, 710), (20, 40, 580, 780)])
    create_fixture(before, **options)
    original_hash = sha256(before)
    engine = PdfWatermarkEngine()
    detected = engine.detect(before)
    result = engine.remove(before, after, expected_sha256=original_hash)
    assert result.outcome == Outcome.REMOVED, result.to_dict()
    assert result.removed_count == 4
    assert sha256(before) == original_hash
    temporary_root = Path("tmp/pdfs").resolve()
    temporary_root.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="stage6a_demo_", dir=temporary_root) as temporary:
        expected = create_fixture(Path(temporary) / "expected.pdf", watermarks=False, **options)
        original_pages = observations(before)
        processed_pages = observations(after)
        expected_pages = observations(expected)
        assert processed_pages == expected_pages
        assert structure(before) == structure(after)
        for source, processed in zip(original_pages, processed_pages):
            assert source["pixels"] != processed["pixels"]
            assert source["text"] == processed["text"]
            assert len(source["annotation_types"]) == 4
            assert len(processed["annotation_types"]) == 3
            assert pdfium.raw.FPDF_ANNOT_WATERMARK not in processed["annotation_types"]

    sheet = Image.new("RGB", (1240, 2100), "#e8ebf0")
    draw = ImageDraw.Draw(sheet)
    for column, path in enumerate((before, after)):
        with pdfium.PdfDocument(path) as document:
            for index in range(len(document)):
                with closing(document[index]) as page:
                    with closing(page.render(scale=.6, draw_annots=True, may_draw_forms=False)) as bitmap:
                        page_image = bitmap.to_pil().convert("RGB")
                        x, y = 20 + column * 620, 45 + index * 515
                        sheet.paste(page_image, (x, y))
                        label = "BEFORE: explicit watermark" if column == 0 else "AFTER: watermark removed; content preserved"
                        draw.text((x, y - 25), f"Page {index + 1} | {label} | rotation {page.get_rotation()}", fill="#172838")
    sheet.save(comparison)
    result_json = result.to_dict()
    result_json["output_path"] = after.name
    evidence = {
        "fixture": "Deterministic locally generated four-page annotation fixture",
        "environment": {"python": platform.python_version(), "platform": platform.platform(),
                        "pypdf": importlib.metadata.version("pypdf"),
                        "pypdfium2": importlib.metadata.version("pypdfium2"),
                        "pdfium": str(pdfium.PDFIUM_INFO),
                        "Pillow": importlib.metadata.version("Pillow")},
        "before": {"file": before.name, "sha256": original_hash, "bytes": before.stat().st_size},
        "after": {"file": after.name, "sha256": sha256(after), "bytes": after.stat().st_size},
        "detection": {"outcome": detected.outcome.value, "supported_count": detected.supported_count},
        "removal": result_json,
        "independent_checks": {"pdfium_page_count": 4, "watermark_counts_before": [1] * 4,
                               "watermark_counts_after": [0] * 4,
                               "ordinary_annotation_counts_after": [3] * 4,
                               "all_pages_pixel_equal_to_generated_clean_fixture": True,
                               "visible_watermark_difference_on_every_page": True,
                               "pdfium_text_unchanged": True,
                               "raw_page_content_and_image_bytes_unchanged": True,
                               "links_review_notes_and_approval_stamps_unchanged": True,
                               "original_sha256_unchanged": True,
                               "rotations": [page["rotation"] for page in processed_pages],
                               "crop_boxes": [page["crop_box"] for page in processed_pages],
                               "processed_pixel_sha256": [page["pixels"] for page in processed_pages]},
    }
    manifest.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"removed": result.removed_count, "independently_verified_pages": 4,
                      "output_directory": str(output), "original_sha256": original_hash,
                      "processed_sha256": sha256(after)}, indent=2))


if __name__ == "__main__":
    main()

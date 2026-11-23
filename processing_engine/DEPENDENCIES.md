# Dependency evaluation and licensing

Reviewed against official sources on 2026-11-14 and updated for 0.2.0 on
2026-11-18. Runtime dependencies are pypdf, pypdfium2 and, since 0.2.0, Pillow.
No processing library was added to Flutter.

| Library | Capabilities and limits | Licensing/dependency assessment | Decision |
| --- | --- | --- | --- |
| pypdf **7.1.0** | Inspects the Python object graph and annotation dictionaries, clones whole documents, serializes them and replaces content-stream objects. It also parses content as an independent operator-sequence check. It has no page renderer, and strict parsing is not universal conformance validation. | BSD-3-Clause. No extra runtime package is needed for this unencrypted scope. | Selected for precise annotation and content-stream edits, backed by graph checks and independent render checks. |
| pypdfium2 **5.15.2** | Native PDFium page rendering and preview PNGs, page boxes and rotations, page objects (type, bounds, content marks), annotation inspection and text-page characters. It is independent of pypdf. The native code adds attack surface, and the platform wheels need maintenance. | Wrapper is Apache-2.0 OR BSD-3-Clause. PDFium and its bundled third-party notices also apply. Installed native version: **159.0.8149.0@sourcebuild-toolchained**. | Selected for independent validation and object geometry. No forms or JavaScript are initialized. PDFium's content regeneration (`FPDFPage_GenerateContent`) is **not** used, because it loses content in this build (see README). |
| pikepdf / qpdf | Strong low-level PDF object editing, parsing and structural checking. Does not render pages. C++/native dependencies and additional installation footprint. | pikepdf MPL-2.0 has file-level source obligations; qpdf Apache-2.0. Can be evaluated for a commercial product with those obligations. | Viable alternative or future third validator; not installed for this module. |
| PyMuPDF / MuPDF | Integrated rendering, annotation APIs, text/graphics inspection and editing; powerful but no automatic guarantee of correct watermark classification. | AGPL or a separate commercial agreement from Artifex. A proprietary distribution cannot silently assume the open-source terms fit. | Not used, imported or declared by this engine, even if present elsewhere on the machine. |
| Pillow **12.3.0** | Encodes preview PNGs. Computes the before/after pixel differences (`ImageChops`) and masks that validate every content edit. It is also used by the demo comparison sheet. It has no PDF parsing or removal role. | MIT-CMU for Pillow. Binary wheels bundle further component notices (libjpeg-turbo, zlib, libpng, FreeType and others). | **Runtime dependency since 0.2.0** (it was the optional `[verify]` extra before). The `[verify]` extra remains, empty, for compatibility. |

**Android build (the APK):** the same three libraries run on the phone through Chaquopy 17.2 with Python 3.13 on arm64-v8a. pypdf 7.1.0 is pure Python. pypdfium2 5.15.2 is installed from its PyPI wheel `py3-none-android_23_arm64_v8a` (it bundles `libpdfium.so`, about 6.6 MB). PyPI has no Android wheel for Pillow, so the APK uses **Pillow 11.0.0** from Chaquopy's own repository (with its `chaquopy-freetype` and `chaquopy-libjpeg` dependencies); the engine only uses `ImageChops` and `ImageDraw`, which behave the same in 11 and 12. Distributing the APK means distributing Python (PSF licence), PDFium, Pillow and these libraries together, so keep their notices; Chaquopy itself is MIT-licensed.

Official sources: [pypdf license](https://raw.githubusercontent.com/py-pdf/pypdf/7.1.0/LICENSE),
[pypdf release](https://github.com/py-pdf/pypdf/releases/tag/7.1.0),
[pypdfium2 capabilities and licensing](https://github.com/pypdfium2-team/pypdfium2/blob/5.15.2/README.md),
[pikepdf](https://github.com/pikepdf/pikepdf),
[qpdf license](https://qpdf.readthedocs.io/en/stable/license.html),
[PyMuPDF licensing](https://pymupdf.readthedocs.io/en/latest/about.html#license-and-copyright),
[Pillow license](https://github.com/python-pillow/Pillow/blob/12.3.0/LICENSE).

The dependency choice avoids adding an AGPL processing dependency. PyMuPDF/MuPDF
(`fitz`) is still rejected and is not imported, declared or used anywhere in the
engine or its tests. It does not
replace a distribution-specific license review. Preserve copyright notices,
license texts and disclaimers in redistributed packages. Keep PDFium's complete
bundled notices for the exact binary/platform; the wrapper license alone is
insufficient. These dependencies do not set the license of this application's
new code, and no license for the user's application has been invented.

`third_party/` contains verbatim notice files copied from the installed pinned
distributions for review: pypdf's LICENSE, pypdfium2's LICENSES and BUILD_LICENSES
trees, and Pillow's LICENSE. Pillow ships at runtime now, so its LICENSE copy
(`third_party/pillow-12.3.0/LICENSE`) is part of the runtime notice set. The
notices of the exact Pillow wheel that is deployed must ship with it too. pypdfium2 source headers retain their original
copyright/SPDX notices (including geisserml and other contributors). Retain the
original distributed packages and their headers/notices when bundling; these
review copies are not a substitute for the exact shipped wheel's full notices.
The upstream PDFium notice tree includes files for multiple build variants;
their presence does not mean every optional component is enabled in this build.

## Security and version choice

The globally installed pypdf 6.16.2 was not reused. Upstream has since fixed
parser resource-exhaustion issues, including repeated cross-reference stream
offsets in [GHSA-59jv-x5x2-gg4c](https://github.com/py-pdf/pypdf/security/advisories/GHSA-59jv-x5x2-gg4c)
(patched in 7.0.0) and dictionary cloning/page-tree issues. The project uses a
separate venv with pinned 7.1.0 and its actual configuration API for decoder and
page-tree limits. See also [pypdf advisories](https://github.com/py-pdf/pypdf/security/advisories).

PDFium is pinned through pypdfium2 5.15.2 rather than the older global renderer.
Record the native build as well as the wrapper version, and review
[upstream releases](https://github.com/pypdfium2-team/pypdfium2/releases) before
deployment. Exact version pins make this tested environment reproducible;
they must not prevent deliberate security upgrades and revalidation.

Runtime dependency inspection (`pip check`) passed for the 0.2.0 environment as well. No cryptography dependency,
FastAPI, OCR engine, external decoder executable, Poppler or qpdf executable is
required. Independent checks use native PDFium; a qpdf/veraPDF conformance audit
was not performed and is not claimed.

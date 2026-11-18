import 'dart:convert';

import 'package:pdf_watermark_remover/models/pdf_page_preview.dart';
import 'package:pdf_watermark_remover/models/selected_pdf.dart';
import 'package:pdf_watermark_remover/services/pdf_preview_service.dart';

PdfPagePreview testPagePreview({int pageCount = 2}) => PdfPagePreview(
  bytes: base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAIAAAA2iEnWAAAAFElEQVR4nGP8//8/AwMDEwMYQCkAORsDA3CXx5UAAAAASUVORK5CYII=',
  ),
  width: 2,
  height: 3,
  pageCount: pageCount,
);

class FakePdfPreviewService implements PdfPreviewService {
  FakePdfPreviewService({this.error, this.onRender});

  Object? error;
  Future<PdfPagePreview> Function(SelectedPdf, PdfPreviewCancellation)?
  onRender;
  final documents = <SelectedPdf>[];
  final cancellations = <PdfPreviewCancellation>[];
  int get calls => documents.length;

  @override
  Future<PdfPagePreview> renderFirstPage(
    SelectedPdf pdf, {
    required PdfPreviewCancellation cancellation,
  }) async {
    documents.add(pdf);
    cancellations.add(cancellation);
    cancellation.throwIfCancelled();
    if (error != null) throw error!;
    return onRender == null
        ? testPagePreview()
        : await onRender!(pdf, cancellation);
  }
}

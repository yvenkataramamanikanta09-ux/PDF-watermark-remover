import 'package:material_ui/material_ui.dart';

import '../models/pdf_page_preview.dart';
import '../services/pdf_preview_service.dart';
import '../services/pdf_area_selection_controller.dart';
import '../theme/app_theme.dart';
import 'pdf_page_selection_view.dart';

class PdfDocumentPreviewCard extends StatelessWidget {
  const PdfDocumentPreviewCard({
    super.key,
    required this.filename,
    required this.preview,
    required this.error,
    required this.onRetry,
    required this.onBack,
    required this.onDecodeError,
    required this.selectionController,
    required this.onInvalidSelection,
  });

  final String filename;
  final PdfPagePreview? preview;
  final PdfPreviewException? error;
  final VoidCallback onRetry;
  final VoidCallback onBack;
  final VoidCallback onDecodeError;
  final PdfAreaSelectionController selectionController;
  final VoidCallback onInvalidSelection;

  @override
  Widget build(BuildContext context) {
    final page = preview;
    return Container(
      constraints: const BoxConstraints(minHeight: 250),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.preview,
        border: Border.all(color: AppColors.previewBorder),
        borderRadius: BorderRadius.circular(20),
      ),
      child: error != null
          ? _errorContent(error!)
          : page == null
          ? const SizedBox(
              height: 220,
              child: Center(
                child: Text(
                  'Loading first page…',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 14,
                  ),
                ),
              ),
            )
          : SizedBox(
              height: 220,
              child: PdfPageSelectionView(
                page: page,
                filename: filename,
                controller: selectionController,
                onDecodeError: onDecodeError,
                onInvalidSelection: onInvalidSelection,
              ),
            ),
    );
  }

  Widget _errorContent(PdfPreviewException error) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 220),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.info_outline, color: AppColors.accent, size: 28),
          const SizedBox(height: 12),
          Text(
            error.message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.secondaryText,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              if (error.failure == PdfPreviewFailure.renderFailed)
                TextButton(onPressed: onRetry, child: const Text('Try again')),
              TextButton(
                onPressed: onBack,
                child: const Text('Back to Upload'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

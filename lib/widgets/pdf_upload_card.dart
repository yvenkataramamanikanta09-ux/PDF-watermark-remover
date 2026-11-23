import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// The upload card of the design. It is a Material card with a ripple, so the
/// whole card opens the file picker as well as the Choose PDF button.
class PdfUploadCard extends StatelessWidget {
  const PdfUploadCard({super.key, this.onTap, this.formatText = 'PDF only'});

  final VoidCallback? onTap;

  /// Shown in the chip, e.g. "PDF only • up to 64 MB".
  final String formatText;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 315),
          padding: const EdgeInsets.fromLTRB(19, 34, 19, 33),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: _UploadCloudIcon()),
              const SizedBox(height: 28),
              Text(
                'Select a PDF file to upload',
                textAlign: TextAlign.center,
                style: textTheme.titleLarge,
              ),
              const SizedBox(height: 20),
              Text(
                'Choose a PDF from your device.',
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(color: AppColors.secondaryText),
              ),
              const SizedBox(height: 40),
              Center(
                child: Chip(
                  key: const ValueKey('format-chip'),
                  avatar: const Icon(Icons.picture_as_pdf_outlined),
                  label: Text('Supported format: $formatText'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UploadCloudIcon extends StatelessWidget {
  const _UploadCloudIcon();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: 76,
        height: 76,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Image.asset(
          'assets/images/upload_cloud.png',
          width: 32,
          height: 32,
        ),
      ),
    );
  }
}

import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

class PdfUploadCard extends StatelessWidget {
  const PdfUploadCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 315),
      padding: const EdgeInsets.fromLTRB(19, 34, 19, 33),
      decoration: BoxDecoration(
        color: AppColors.preview,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.previewBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: _UploadCloudIcon()),
          const SizedBox(height: 28),
          const Text(
            'Select a PDF file to upload',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.primaryText,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              height: 21 / 18,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Choose a PDF from your device.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.secondaryText,
              fontSize: 14,
              fontWeight: FontWeight.w400,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 55),
          const Text(
            'Supported format: PDF only',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.primaryText,
              fontSize: 14,
              fontWeight: FontWeight.w400,
              height: 1.5,
            ),
          ),
        ],
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

import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

class UploadPdfButton extends StatelessWidget {
  const UploadPdfButton({
    super.key,
    required this.onPressed,
    this.label = 'Upload PDF',
  });

  final VoidCallback? onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.buttonText,
        disabledBackgroundColor: AppColors.accent,
        disabledForegroundColor: AppColors.buttonText,
        minimumSize: const Size.fromHeight(56),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 16,
          fontWeight: FontWeight.w600,
          height: 1.25,
        ),
      ),
      child: Text(label),
    );
  }
}

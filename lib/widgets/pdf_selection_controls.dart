import 'package:material_ui/material_ui.dart';

import '../services/pdf_area_selection_controller.dart';
import '../theme/app_theme.dart';

/// Fits the existing manual-selection helper space; card/footer positions stay.
class PdfSelectionControls extends StatelessWidget {
  const PdfSelectionControls({super.key, required this.controller});
  final PdfAreaSelectionController controller;

  @override
  Widget build(BuildContext context) {
    Widget mode(
      PdfSelectionMode value,
      IconData icon,
      String label,
      String hint,
    ) {
      final selected = controller.mode == value;
      return Tooltip(
        message: hint,
        child: Semantics(
          selected: selected,
          child: TextButton.icon(
            onPressed: controller.isReady && !controller.isApplying
                ? () => controller.setMode(value)
                : null,
            icon: Icon(icon, size: 16),
            label: Text(label),
            style: TextButton.styleFrom(
              foregroundColor: selected
                  ? AppColors.accent
                  : AppColors.secondaryText,
              disabledForegroundColor: AppColors.secondaryText,
              minimumSize: const Size(0, 48),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              textStyle: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }

    final buttons = <Widget>[
      mode(
        PdfSelectionMode.select,
        Icons.crop_free,
        'Select',
        'Drag on the PDF page to select or replace an area. Zoom and pan are unavailable.',
      ),
      mode(
        PdfSelectionMode.view,
        Icons.visibility_outlined,
        'View',
        'Scroll to view the document without changing the selected area.',
      ),
      TextButton.icon(
        onPressed: controller.hasRegion || controller.isDrawing
            ? controller.clear
            : null,
        icon: const Icon(Icons.close, size: 16),
        label: const Text('Clear'),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accent,
          disabledForegroundColor: AppColors.secondaryText,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ];
    final largeText = MediaQuery.textScalerOf(context).scale(13) > 16;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 57),
      child: largeText
          ? Wrap(alignment: WrapAlignment.center, children: buttons)
          : SizedBox(
              height: 57,
              child: Align(
                alignment: Alignment.topCenter,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: buttons
                      .map((button) => Flexible(child: button))
                      .toList(),
                ),
              ),
            ),
    );
  }
}

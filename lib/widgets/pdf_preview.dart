import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

class PdfPreview extends StatelessWidget {
  const PdfPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: 'PDF preview with a selected SAMPLE watermark',
      child: ExcludeSemantics(
        child: AspectRatio(
          aspectRatio: 342 / 340,
          child: FittedBox(
            child: Container(
              width: 342,
              height: 340,
              decoration: BoxDecoration(
                color: AppColors.preview,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.previewBorder),
              ),
              child: const Stack(
                children: [
                  Positioned(left: 87, top: 29, child: _PdfDocument()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PdfDocument extends StatelessWidget {
  const _PdfDocument();

  @override
  Widget build(BuildContext context) {
    // Illustration lettering scales with the paper, independently of UI text.
    return MediaQuery.withNoTextScaling(
      child: Container(
        width: 166,
        height: 245,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Stack(
          children: [
            const Positioned(
              top: 20,
              left: 20,
              width: 126,
              child: Text(
                'PDF',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.navy,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
            ),
            const _DocumentLine(top: 75, width: 126, opacity: 0.1),
            const _DocumentLine(top: 92, width: 100, opacity: 0.32),
            const _DocumentLine(top: 109, width: 115),
            const _DocumentLine(top: 120, width: 115, opacity: 0.32),
            Positioned(
              top: 149,
              left: 13,
              width: 140,
              height: 48,
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.accent, width: 2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'SAMPLE',
                  style: TextStyle(
                    color: Color(0xFFAAAAAA),
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocumentLine extends StatelessWidget {
  const _DocumentLine({
    required this.top,
    required this.width,
    this.opacity = 1,
  });

  final double top;
  final double width;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top,
      left: 20,
      width: width,
      height: 5,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFE5E5E5).withValues(alpha: opacity),
          borderRadius: BorderRadius.circular(5),
        ),
      ),
    );
  }
}

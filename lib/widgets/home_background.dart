import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

class HomeBackground extends StatelessWidget {
  const HomeBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: IgnorePointer(
        child: ColoredBox(
          color: AppColors.background,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final horizontalScale = constraints.maxWidth / 390;
              final verticalScale = math.min(horizontalScale, 1.5);

              // Preserve the original Figma shapes and clip at the screen edge.
              return Stack(
                children: [
                  Positioned(
                    top: 0,
                    left: 0,
                    width: constraints.maxWidth,
                    height: 195 * verticalScale,
                    child: Image.asset(
                      'assets/images/navy_ellipse.png',
                      fit: BoxFit.fill,
                    ),
                  ),
                  Positioned(
                    top: 135 * verticalScale,
                    left: 0,
                    width: 125 * verticalScale,
                    height: 250 * verticalScale,
                    child: Image.asset('assets/images/teal_ellipse.png'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

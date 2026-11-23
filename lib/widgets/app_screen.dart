import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';
import 'home_background.dart';
import 'home_header.dart';

/// The frame every screen of the design shares: the navy/teal background, the
/// header bar at the top, scrollable content, and the primary action pinned
/// above the system navigation area.
class AppScreen extends StatelessWidget {
  const AppScreen({
    super.key,
    required this.children,
    this.headerActions = const [],
    this.primaryAction,
    this.secondaryAction,
    this.headerGap = 48,
  });

  final List<Widget> children;
  final List<HeaderAction> headerActions;

  /// Usually a [FilledButton]; stays visible while the content scrolls.
  final Widget? primaryAction;

  /// Optional lower-emphasis action shown above the primary one.
  final Widget? secondaryAction;

  /// Space between the header and the first child (48 in most frames).
  final double headerGap;

  @override
  Widget build(BuildContext context) {
    final safePadding = MediaQuery.paddingOf(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: AppColors.background,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            const HomeBackground(),
            SafeArea(
              bottom: false,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 488),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      24,
                      math.max(16, 40 - safePadding.top),
                      24,
                      24,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 2),
                          child: HomeHeader(actions: headerActions),
                        ),
                        SizedBox(height: headerGap),
                        ...children,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: primaryAction == null && secondaryAction == null
            ? null
            : SafeArea(
                top: false,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  heightFactor: 1,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 488),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        24,
                        16,
                        24,
                        math.max(18, 42 - safePadding.bottom),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (secondaryAction != null) ...[
                            secondaryAction!,
                            const SizedBox(height: 12),
                          ],
                          ?primaryAction,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

/// The 76 px status circle of the Completed and Error frames.
class StatusBadge extends StatelessWidget {
  const StatusBadge.success({super.key})
    : icon = Icons.check_rounded,
      fill = AppColors.successContainer,
      border = AppColors.success;

  const StatusBadge.error({super.key})
    : icon = Icons.priority_high_rounded,
      fill = AppColors.errorContainer,
      border = AppColors.accent;

  final IconData icon;
  final Color fill;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Center(
        child: Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            border: Border.all(color: border, width: 2),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 32, color: AppColors.background),
        ),
      ),
    );
  }
}

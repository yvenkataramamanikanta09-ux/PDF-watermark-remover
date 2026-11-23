import 'package:material_ui/material_ui.dart';

import '../config.dart';
import '../theme/app_theme.dart';

/// One entry of the header's "More options" menu.
final class HeaderAction {
  const HeaderAction(this.label, this.onSelected);
  final String label;
  final VoidCallback onSelected;
}

/// The rounded header bar of the design: app icon, title and the "…" menu.
class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key, this.actions = const []});

  /// Screen-specific entries shown above "About this app".
  final List<HeaderAction> actions;

  void _showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'PDF Watermark Remover',
      applicationVersion: '1.1.0',
      applicationIcon: const _PdfAppIcon(),
      children: const [
        Text(
          'Removes watermark annotations, Acrobat-style watermark layers, and '
          'anything inside the area you select. Your original file is never '
          'changed. $privacyNote',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasRoomForReferenceSpacing =
        MediaQuery.sizeOf(context).width >= 390 &&
        MediaQuery.textScalerOf(context).scale(16) <= 16;

    return Container(
      constraints: const BoxConstraints(minHeight: 76),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(22),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 5, 14),
      child: Row(
        children: [
          const _PdfAppIcon(),
          // Leave enough width for the full title at the reference size.
          SizedBox(width: hasRoomForReferenceSpacing ? 31 : 16),
          Expanded(
            child: Text(
              'PDF Watermark Remover',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          PopupMenuButton<int>(
            tooltip: 'More options',
            padding: EdgeInsets.zero,
            icon: const Icon(
              Icons.more_horiz,
              color: AppColors.primaryText,
              size: 18,
            ),
            onSelected: (index) {
              if (index < actions.length) {
                actions[index].onSelected();
              } else {
                _showAbout(context);
              }
            },
            itemBuilder: (context) => [
              for (final (index, action) in actions.indexed)
                PopupMenuItem(value: index, child: Text(action.label)),
              PopupMenuItem(
                value: actions.length,
                child: const Text('About this app'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PdfAppIcon extends StatelessWidget {
  const _PdfAppIcon();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Image.asset(
          'assets/images/file_icon.png',
          width: 20,
          height: 20,
        ),
      ),
    );
  }
}

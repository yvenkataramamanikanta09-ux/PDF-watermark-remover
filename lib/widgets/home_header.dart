import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

enum _HomeMenuAction { back, about }

class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key, this.onBack, this.backLabel = 'Back to Home'});

  final VoidCallback? onBack;
  final String backLabel;

  void _showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'PDF Watermark Remover',
      applicationVersion: '1.0.0',
      applicationIcon: const _PdfAppIcon(),
      children: const [Text('PDF upload is coming soon.')],
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
          // Leave enough width for Inter's full title at the reference size.
          SizedBox(width: hasRoomForReferenceSpacing ? 31 : 16),
          const Expanded(
            child: Text(
              'PDF Watermark Remover',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.primaryText,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),
          ),
          PopupMenuButton<_HomeMenuAction>(
            tooltip: 'More options',
            padding: EdgeInsets.zero,
            icon: const Icon(
              Icons.more_horiz,
              color: AppColors.primaryText,
              size: 18,
            ),
            onSelected: (action) {
              switch (action) {
                case _HomeMenuAction.back:
                  onBack?.call();
                case _HomeMenuAction.about:
                  _showAbout(context);
              }
            },
            itemBuilder: (context) => [
              if (onBack != null)
                PopupMenuItem(
                  value: _HomeMenuAction.back,
                  child: Text(backLabel),
                ),
              const PopupMenuItem(
                value: _HomeMenuAction.about,
                child: Text('About this app'),
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

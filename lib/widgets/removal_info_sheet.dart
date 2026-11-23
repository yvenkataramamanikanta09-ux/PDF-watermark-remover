import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

abstract final class RemovalInfoSheet {
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: AppColors.preview,
      builder: (context) => const _RemovalInfoContent(),
    );
  }
}

class _RemovalInfoContent extends StatelessWidget {
  const _RemovalInfoContent();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 488),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('What can be removed?', style: textTheme.titleLarge),
                const SizedBox(height: 16),
                const _Row(
                  icon: Icons.auto_awesome_outlined,
                  title: 'Detected watermarks',
                  body: 'Watermark annotations and Acrobat-style watermark layers are '
                      'found automatically.',
                ),
                const _Row(
                  icon: Icons.crop_free,
                  title: 'Anything inside an area you mark',
                  body: 'Text, images and shapes that lie fully inside your rectangle are '
                      'removed, on every page or only on page 1.',
                ),
                const _Row(
                  icon: Icons.verified_outlined,
                  title: 'Checked before you download',
                  body: 'Every page is compared with the original; nothing outside the '
                      'removed area may change. Your original file is never modified.',
                ),
                const _Row(
                  icon: Icons.block_outlined,
                  title: 'Not supported',
                  body: 'Password-protected or digitally signed PDFs, and watermarks that '
                      'are part of a scanned page image.',
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Got it'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.accent),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(body, style: textTheme.bodyMedium?.copyWith(color: AppColors.secondaryText)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

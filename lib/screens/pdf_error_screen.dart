import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';
import '../widgets/app_screen.dart';
import '../widgets/home_header.dart';

/// What went wrong, in the shape of the design's error card.
final class PdfErrorDetails {
  const PdfErrorDetails({
    required this.title,
    required this.message,
    required this.code,
    this.actionLabel = 'Try Again',
  });

  /// Card heading, e.g. "Watermark Removal Failed".
  final String title;
  final String message;

  /// Shown as "Error code: …"; upper snake case.
  final String code;
  final String actionLabel;

  static String formatCode(String? code, {String fallback = 'UNKNOWN_ERROR'}) {
    final cleaned = (code ?? '').trim().replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_').toUpperCase();
    return cleaned.isEmpty ? fallback : cleaned;
  }
}

/// Figma frame "Error": pops with `true` when the user taps the action.
class PdfErrorScreen extends StatelessWidget {
  const PdfErrorScreen({super.key, required this.details});

  static const routeName = '/pdf-error';

  final PdfErrorDetails details;

  static Future<bool> show(BuildContext context, PdfErrorDetails details) async {
    final retry = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        settings: const RouteSettings(name: routeName),
        builder: (context) => PdfErrorScreen(details: details),
      ),
    );
    return retry ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return AppScreen(
      headerGap: 54,
      headerActions: [
        HeaderAction(
          'Back to Home',
          () => Navigator.of(context).popUntil((route) => route.isFirst),
        ),
      ],
      secondaryAction: OutlinedButton(
        key: const ValueKey('back-home-button'),
        onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
        child: const Text('Back to Home'),
      ),
      primaryAction: FilledButton(
        key: const ValueKey('try-again-button'),
        onPressed: () => Navigator.of(context).pop(true),
        child: Text(details.actionLabel),
      ),
      children: [
        const StatusBadge.error(),
        const SizedBox(height: 26),
        Semantics(
          header: true,
          child: Text(
            'Unable to Process PDF',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        ),
        const SizedBox(height: 22),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 326),
            child: const Text(
              "We couldn't process your file. Please review the error below and try again.",
              textAlign: TextAlign.center,
              style: AppText.bodyStrong,
            ),
          ),
        ),
        const SizedBox(height: 44),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 342),
            child: Card(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 204),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 32, 20, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        details.title,
                        key: const ValueKey('error-title'),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 22),
                      Text(
                        details.message,
                        key: const ValueKey('error-message'),
                        style: AppText.body,
                      ),
                      const SizedBox(height: 36),
                      Text(
                        'Error code: ${details.code}',
                        key: const ValueKey('error-code'),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.accent,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

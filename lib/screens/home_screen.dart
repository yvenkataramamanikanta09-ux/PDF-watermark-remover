import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../services/app_services.dart';
import '../theme/app_theme.dart';
import '../widgets/home_background.dart';
import '../widgets/home_header.dart';
import '../widgets/pdf_preview.dart';
import '../widgets/removal_info_sheet.dart';
import 'pdf_upload_screen.dart';
import '../widgets/engine_check_dialog.dart';

/// Figma frame "Home": illustration, headline and the Upload PDF action.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.services});

  final AppServices services;

  void _openPdfUpload(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: PdfUploadScreen.routeName),
        builder: (context) => PdfUploadScreen(services: services),
      ),
    );
  }

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
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 488),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Keep the reference margins while allowing larger insets.
                      final padding = EdgeInsets.fromLTRB(
                        24,
                        math.max(16, 40 - safePadding.top),
                        24,
                        math.max(18, 42 - safePadding.bottom),
                      );

                      return SingleChildScrollView(
                        padding: padding,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: math.max(
                              0,
                              constraints.maxHeight - padding.vertical,
                            ),
                          ),
                          // Fill tall screens; scroll when content needs more room.
                          child: IntrinsicHeight(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(right: 2),
                                  child: HomeHeader(
                                    actions: [
                                      HeaderAction(
                                        'Check PDF engine',
                                        () => EngineCheckDialog.show(context, services.engine),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 24),
                                const Spacer(flex: 5),
                                Center(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 342),
                                    child: const PdfPreview(),
                                  ),
                                ),
                                const SizedBox(height: 32),
                                const Spacer(),
                                Semantics(
                                  header: true,
                                  child: Center(
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(maxWidth: 342),
                                      child: Text(
                                        'Remove Watermarks from Your PDF',
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context).textTheme.headlineSmall,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Center(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 326),
                                    child: const Text(
                                      'Upload your PDF to remove supported '
                                      'watermarks quickly and securely.',
                                      textAlign: TextAlign.center,
                                      style: AppText.bodyStrong,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Center(
                                  child: ActionChip(
                                    key: const ValueKey('what-can-be-removed-chip'),
                                    avatar: const Icon(Icons.info_outline),
                                    label: const Text('What can be removed?'),
                                    onPressed: () => RemovalInfoSheet.show(context),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                const Spacer(flex: 2),
                                FilledButton(
                                  key: const ValueKey('upload-pdf-button'),
                                  onPressed: () => _openPdfUpload(context),
                                  child: const Text('Upload PDF'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
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

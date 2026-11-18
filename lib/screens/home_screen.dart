import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';
import '../services/pdf_selection_service.dart';
import '../services/pdf_preview_service.dart';
import '../services/pdf_area_selection_controller.dart';
import '../widgets/home_background.dart';
import '../widgets/home_header.dart';
import '../widgets/pdf_preview.dart';
import '../widgets/upload_pdf_button.dart';
import 'pdf_upload_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.pdfSelectionService,
    this.pdfPreviewService,
    this.areaSelectionController,
  });

  final PdfSelectionService pdfSelectionService;
  final PdfPreviewService? pdfPreviewService;
  final PdfAreaSelectionController? areaSelectionController;

  void _openPdfUpload(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: PdfUploadScreen.routeName),
        builder: (context) => PdfUploadScreen(
          pdfSelectionService: pdfSelectionService,
          pdfPreviewService: pdfPreviewService,
          areaSelectionController: areaSelectionController,
        ),
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
                                const Padding(
                                  padding: EdgeInsets.only(right: 2),
                                  child: HomeHeader(),
                                ),
                                const SizedBox(height: 24),
                                const Spacer(flex: 5),
                                Center(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 342,
                                    ),
                                    child: const PdfPreview(),
                                  ),
                                ),
                                const SizedBox(height: 32),
                                const Spacer(),
                                Semantics(
                                  header: true,
                                  child: Center(
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 342,
                                      ),
                                      child: const Text(
                                        'Remove Watermarks from Your PDF',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: AppColors.primaryText,
                                          fontSize: 24,
                                          fontWeight: FontWeight.w600,
                                          height: 1.2,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Center(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 326,
                                    ),
                                    child: const Text(
                                      'Upload your PDF to remove supported '
                                      'watermarks quickly and securely.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: AppColors.secondaryText,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        height: 1.5,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 32),
                                const Spacer(flex: 2),
                                UploadPdfButton(
                                  onPressed: () => _openPdfUpload(context),
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

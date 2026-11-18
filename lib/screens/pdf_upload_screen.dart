import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';
import '../services/pdf_selection_service.dart';
import '../services/pdf_preview_service.dart';
import '../services/local_pdf_preview_service.dart';
import '../services/pdf_area_selection_controller.dart';
import '../utils/file_size.dart';
import '../widgets/home_background.dart';
import '../widgets/home_header.dart';
import '../widgets/pdf_upload_card.dart';
import '../widgets/upload_pdf_button.dart';
import 'pdf_processing_screen.dart';

class PdfUploadScreen extends StatefulWidget {
  const PdfUploadScreen({
    super.key,
    required this.pdfSelectionService,
    this.pdfPreviewService,
    this.areaSelectionController,
  });

  static const routeName = '/pdf-upload';

  final PdfSelectionService pdfSelectionService;
  final PdfPreviewService? pdfPreviewService;
  final PdfAreaSelectionController? areaSelectionController;

  @override
  State<PdfUploadScreen> createState() => _PdfUploadScreenState();
}

class _PdfUploadScreenState extends State<PdfUploadScreen> {
  bool _selecting = false;
  late final PdfPreviewService _previewService =
      widget.pdfPreviewService ?? LocalPdfPreviewService();

  Future<void> _choosePdf() async {
    if (_selecting) return;
    _selecting = true;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    try {
      final pdf = await widget.pdfSelectionService.selectPdf();
      if (!mounted || pdf == null) return;
      widget.areaSelectionController?.bindDocument(pdf);
      final displayName = pdf.name.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ');
      _showMessage('Selected $displayName (${formatFileSize(pdf.size)}).');
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: PdfProcessingScreen.routeName),
          builder: (context) => PdfProcessingScreen(
            selectedPdf: pdf,
            previewService: _previewService,
            areaSelectionController: widget.areaSelectionController,
          ),
        ),
      );
    } on PdfSelectionException catch (error) {
      if (mounted) _showMessage(error.message);
    } finally {
      _selecting = false;
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message, maxLines: 3, overflow: TextOverflow.ellipsis),
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
                          child: HomeHeader(
                            onBack: () => Navigator.of(context).maybePop(),
                          ),
                        ),
                        const SizedBox(height: 68),
                        Semantics(
                          header: true,
                          child: const Text(
                            'Upload Your PDF',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.primaryText,
                              fontSize: 26,
                              fontWeight: FontWeight.w600,
                              height: 31 / 26,
                            ),
                          ),
                        ),
                        const SizedBox(height: 60),
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 342),
                            child: const PdfUploadCard(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        // Keep the action visible while short screens scroll the content above.
        bottomNavigationBar: SafeArea(
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
                child: UploadPdfButton(
                  label: 'Choose PDF',
                  onPressed: _choosePdf,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

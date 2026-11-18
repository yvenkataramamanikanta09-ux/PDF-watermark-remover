import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../models/pdf_page_preview.dart';
import '../models/selected_pdf.dart';
import '../services/pdf_preview_service.dart';
import '../services/pdf_area_selection_controller.dart';
import '../theme/app_theme.dart';
import '../utils/file_size.dart';
import '../widgets/home_background.dart';
import '../widgets/home_header.dart';
import '../widgets/pdf_document_preview_card.dart';
import '../widgets/pdf_selection_controls.dart';
import '../widgets/upload_pdf_button.dart';

class PdfProcessingScreen extends StatefulWidget {
  const PdfProcessingScreen({
    super.key,
    required this.selectedPdf,
    required this.previewService,
    this.areaSelectionController,
  });

  static const routeName = '/pdf-processing';
  final SelectedPdf selectedPdf;
  final PdfPreviewService previewService;
  final PdfAreaSelectionController? areaSelectionController;

  @override
  State<PdfProcessingScreen> createState() => _PdfProcessingScreenState();
}

class _PdfProcessingScreenState extends State<PdfProcessingScreen>
    with WidgetsBindingObserver {
  PdfPagePreview? _preview;
  PdfPreviewException? _error;
  PdfPreviewCancellation? _cancellation;
  Future<void>? _operation;
  int _request = 0;
  bool _loading = true;
  bool _suspended = false;
  bool _resumePreview = false;
  late PdfAreaSelectionController _selection;
  late bool _ownsSelection;

  String get _filename =>
      widget.selectedPdf.name.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ');

  @override
  void initState() {
    super.initState();
    _attachSelection();
    WidgetsBinding.instance.addObserver(this);
    _requestPreview();
  }

  void _attachSelection() {
    _ownsSelection = widget.areaSelectionController == null;
    _selection = widget.areaSelectionController ?? PdfAreaSelectionController();
    _selection.bindDocument(widget.selectedPdf);
    _selection.addListener(_selectionChanged);
  }

  void _selectionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant PdfProcessingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.areaSelectionController != widget.areaSelectionController) {
      _selection.removeListener(_selectionChanged);
      _selection.cancelInteraction();
      if (_ownsSelection) _selection.dispose();
      _attachSelection();
    }
    if (!identical(oldWidget.selectedPdf, widget.selectedPdf) ||
        oldWidget.previewService != widget.previewService ||
        oldWidget.areaSelectionController != widget.areaSelectionController) {
      _selection.bindDocument(widget.selectedPdf);
      _requestPreview();
    }
  }

  void _evictPreview() {
    final page = _preview;
    if (page != null) {
      PaintingBinding.instance.imageCache.evict(MemoryImage(page.bytes));
    }
  }

  void _requestPreview() {
    final previous = _operation;
    final request = ++_request;
    final document = widget.selectedPdf;
    final service = widget.previewService;
    _cancellation?.cancel();
    _selection.previewLoading(document);
    _evictPreview();
    setState(() {
      _preview = null;
      _error = null;
      _loading = true;
    });
    // Serialize retries/resumes so an interrupted native render closes first.
    _operation = () async {
      if (previous != null) await previous;
      if (!mounted || _suspended || request != _request) return;
      final cancellation = PdfPreviewCancellation();
      _cancellation = cancellation;
      try {
        final page = await service.renderFirstPage(
          document,
          cancellation: cancellation,
        );
        if (!mounted || cancellation.isCancelled || request != _request) return;
        setState(() {
          _preview = page;
          _loading = false;
        });
        _selection.previewAvailable(document, page);
      } on PdfPreviewCancelled {
        // Backgrounding or leaving the route is not a document error.
      } catch (error) {
        if (!mounted || cancellation.isCancelled || request != _request) return;
        setState(() {
          _error = error is PdfPreviewException
              ? error
              : const PdfPreviewException(PdfPreviewFailure.renderFailed);
          _loading = false;
        });
        _selection.previewFailed(document);
      }
    }();
    unawaited(_operation);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _suspended = true;
      _selection.cancelInteraction();
      if (_loading) {
        _resumePreview = true;
        _request++;
        _cancellation?.cancel();
      }
    } else if (state == AppLifecycleState.resumed) {
      setState(() => _suspended = false);
      if (_resumePreview) {
        _resumePreview = false;
        _requestPreview();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _request++;
    _cancellation?.cancel();
    _evictPreview();
    _selection.removeListener(_selectionChanged);
    _selection.previewLoading(widget.selectedPdf);
    if (_ownsSelection) _selection.dispose();
    super.dispose();
  }

  void _backToUpload() => Navigator.of(context).pop();

  void _decodeFailed() {
    if (!mounted || _error != null) return;
    _evictPreview();
    setState(() {
      _error = const PdfPreviewException(PdfPreviewFailure.renderFailed);
      _loading = false;
    });
    _selection.previewFailed(widget.selectedPdf);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _applySelection() async {
    if (_suspended) return;
    final selection = _selection;
    final result = await selection.apply();
    if (!mounted || selection != _selection) return;
    if (result == PdfAreaApplyResult.committed) {
      _showMessage('Watermark area selected. PDF unchanged.');
    } else if (result == PdfAreaApplyResult.documentUnavailable) {
      setState(() {
        _error = const PdfPreviewException(PdfPreviewFailure.unreadable);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final safePadding = MediaQuery.paddingOf(context);
    final request = _request;
    final count = _preview?.pageCount;
    final metadata = count == null
        ? formatFileSize(widget.selectedPdf.size)
        : '${formatFileSize(widget.selectedPdf.size)} • $count ${count == 1 ? 'page' : 'pages'}';

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
                      20,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 2),
                          child: HomeHeader(
                            onBack: _backToUpload,
                            backLabel: 'Back to Upload',
                          ),
                        ),
                        const SizedBox(height: 48),
                        Semantics(
                          header: true,
                          child: const Text(
                            'Processing Your PDF',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.primaryText,
                              fontSize: 26,
                              fontWeight: FontWeight.w600,
                              height: 31 / 26,
                            ),
                          ),
                        ),
                        const SizedBox(height: 30),
                        Tooltip(
                          message: _filename,
                          child: Text(
                            'Document: $_filename',
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.secondaryText,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              height: 1.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          metadata,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.secondaryText,
                            fontSize: 12,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 31),
                        const _PendingProcessingStatus(),
                        const SizedBox(height: 35),
                        Semantics(
                          header: true,
                          child: const Text(
                            'Manual Watermark Selection',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.primaryText,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              height: 21 / 18,
                            ),
                          ),
                        ),
                        PdfSelectionControls(controller: _selection),
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 342),
                            child: PdfDocumentPreviewCard(
                              filename: _filename,
                              preview: _preview,
                              error: _error,
                              onRetry: _requestPreview,
                              onBack: _backToUpload,
                              onDecodeError: () {
                                if (request == _request) _decodeFailed();
                              },
                              selectionController: _selection,
                              onInvalidSelection: () => _showMessage(
                                'Drag a larger rectangle inside the PDF page.',
                              ),
                            ),
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
                child: Tooltip(
                  message: _selection.canApply
                      ? 'Save this area without changing the PDF.'
                      : 'Select a valid rectangle on the PDF page first.',
                  child: UploadPdfButton(
                    label: 'Apply Selection',
                    onPressed: _selection.canApply && !_suspended
                        ? _applySelection
                        : null,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PendingProcessingStatus extends StatelessWidget {
  const _PendingProcessingStatus();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Semantics(
          label: 'Watermark processing',
          value: 'Not started',
          child: Container(
            key: const ValueKey('processing-not-started-track'),
            constraints: const BoxConstraints(maxWidth: 306),
            height: 10,
            decoration: BoxDecoration(
              color: AppColors.previewBorder,
              borderRadius: BorderRadius.circular(5),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Not started — processing unavailable',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.secondaryText,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

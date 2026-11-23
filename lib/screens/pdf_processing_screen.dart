import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../models/job.dart';
import '../models/pdf_page_preview.dart';
import '../models/selected_pdf.dart';
import '../services/app_services.dart';
import '../services/pdf_engine.dart';
import '../services/pdf_area_selection_controller.dart';
import '../theme/app_theme.dart';
import '../utils/file_size.dart';
import '../widgets/app_screen.dart';
import '../widgets/home_header.dart';
import '../widgets/pdf_page_selection_view.dart';
import 'pdf_error_screen.dart';
import 'pdf_result_screen.dart';

enum _Phase { uploading, ready, processing }

/// Figma frame "Processing": progress, the manual watermark selection on the
/// page preview, and Apply Selection.
///
/// The screen owns one working folder on the phone: it copies the PDF in, lets
/// the user select the watermark area (or use automatic removal when
/// watermarks were detected), runs the removal, and opens the Completed or
/// Error screen. Nothing is uploaded anywhere.
class PdfProcessingScreen extends StatefulWidget {
  const PdfProcessingScreen({
    super.key,
    required this.pdf,
    required this.services,
  });

  static const routeName = '/pdf-processing';

  final SelectedPdf pdf;
  final AppServices services;

  @override
  State<PdfProcessingScreen> createState() => _PdfProcessingScreenState();
}

class _PdfProcessingScreenState extends State<PdfProcessingScreen> {
  final _selection = PdfAreaSelectionController();
  _Phase _phase = _Phase.uploading;

  /// 0..1 while the PDF is copied into the app; null while the engine works.
  double? _progress = 0;
  JobInfo? _job;
  Uint8List? _preview;
  bool _allPages = true;
  RemovalMode _mode = RemovalMode.area;
  bool _disposed = false;
  int _run = 0;

  PdfEngine get _engine => widget.services.engine;

  String get _filename => widget.pdf.name.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ');

  String get _cleanedFileName {
    final name = _filename.trim();
    final stem = name.toLowerCase().endsWith('.pdf') ? name.substring(0, name.length - 4) : name;
    return '${stem}_cleaned.pdf';
  }

  @override
  void initState() {
    super.initState();
    _selection.addListener(_selectionChanged);
    _upload();
  }

  @override
  void dispose() {
    _disposed = true;
    _run++;
    _selection
      ..removeListener(_selectionChanged)
      ..dispose();
    final job = _job;
    if (job != null) {
      // Delete this document's working files from the phone.
      unawaited(_engine.deleteJob(job.id).catchError((Object _) {}));
    }
    super.dispose();
  }

  void _selectionChanged() {
    if (mounted) setState(() {});
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  EngineException _asEngineError(Object error) => error is EngineException
      ? error
      : const EngineException(EngineFailure.failed, 'Something went wrong. Try again.');

  // ---------------------------------------------------------------- upload

  Future<void> _upload() async {
    final run = ++_run;
    setState(() {
      _phase = _Phase.uploading;
      _progress = 0;
    });
    try {
      final job = await _engine.analyze(
        widget.pdf,
        onProgress: (progress) {
          if (!mounted || run != _run) return;
          // Once the PDF is copied, the engine checks it.
          setState(() => _progress = progress >= 1 ? null : progress);
        },
      );
      if (_disposed || run != _run) {
        unawaited(_engine.deleteJob(job.id).catchError((Object _) {}));
        return;
      }
      _job = job;
      final preview = await _engine.preview(job.id);
      if (!mounted || run != _run) return;
      setState(() {
        _preview = preview;
        _phase = _Phase.ready;
        _progress = 0;
        _mode = job.detection.autoAvailable ? RemovalMode.auto : RemovalMode.area;
      });
      _selection.enabled = _mode == RemovalMode.area;
    } catch (error) {
      if (!mounted || run != _run) return;
      await _analysisFailed(_asEngineError(error));
    }
  }

  Future<void> _analysisFailed(EngineException error) async {
    // A refused or vanished document can't succeed on a second try; other failures can.
    final choosePdfAgain =
        error.failure == EngineFailure.rejected || error.failure == EngineFailure.notFound;
    final retry = await PdfErrorScreen.show(
      context,
      PdfErrorDetails(
        title: switch (error.failure) {
          EngineFailure.rejected => 'PDF Not Accepted',
          EngineFailure.notFound => 'PDF Not Readable',
          EngineFailure.unavailable => 'PDF Engine Unavailable',
          EngineFailure.failed => 'Could Not Check the PDF',
        },
        message: error.message,
        code: error.code ?? PdfEngineCodes.format(error.failure.name, fallback: 'CHECK_FAILED'),
        actionLabel: choosePdfAgain ? 'Choose Another PDF' : 'Try Again',
      ),
    );
    if (!mounted) return;
    if (retry && !choosePdfAgain) {
      unawaited(_upload());
    } else {
      Navigator.of(context).pop();
    }
  }

  // ---------------------------------------------------------------- removal

  Future<void> _start(RemovalMode mode) async {
    final job = _job;
    if (job == null || _phase != _Phase.ready) return;
    final area = _selection.area;
    if (mode == RemovalMode.area && area == null) return;
    final run = ++_run;
    _selection.enabled = false;
    setState(() {
      _phase = _Phase.processing;
      _progress = null;
    });
    JobInfo? finished;
    EngineException? failure;
    try {
      // The engine works on a background thread and answers when it is done.
      finished = await _engine.removeWatermark(
        job.id,
        mode: mode,
        area: mode == RemovalMode.area ? area : null,
        allPages: _allPages,
      );
    } catch (error) {
      failure = _asEngineError(error);
    }
    if (!mounted || run != _run) return;

    if (finished != null && finished.status == JobStatus.succeeded) {
      Uint8List? resultPreview;
      try {
        resultPreview = await _engine.resultPreview(job.id);
      } catch (_) {
        resultPreview = null; // The PDF itself can still be downloaded.
      }
      if (!mounted || run != _run) return;
      _job = finished;
      await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          settings: const RouteSettings(name: PdfResultScreen.routeName),
          builder: (context) => PdfResultScreen(
            job: finished!,
            cleanedFileName: _cleanedFileName,
            preview: resultPreview,
            engine: _engine,
            saver: widget.services.saver,
          ),
        ),
      );
    } else {
      await PdfErrorScreen.show(context, _removalError(mode, finished, failure));
    }
    if (!mounted || run != _run) return;
    // Back on this screen: the same upload can be processed again.
    setState(() {
      _phase = _Phase.ready;
      _progress = 0;
    });
    _selection.enabled = _mode == RemovalMode.area;
  }

  void _setMode(RemovalMode mode) {
    if (_mode == mode) return;
    setState(() => _mode = mode);
    _selection.enabled = mode == RemovalMode.area;
  }

  /// Leaving while the engine works discards the result, so ask first.
  Future<void> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.hourglass_top_outlined),
        title: const Text('Stop processing?'),
        content: const Text(
          'The watermark is still being removed. If you leave now, the result is discarded.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep waiting'),
          ),
          TextButton(
            key: const ValueKey('leave-processing-button'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.of(context).pop();
  }

  PdfErrorDetails _removalError(RemovalMode mode, JobInfo? finished, EngineException? failure) {
    if (failure != null) {
      return PdfErrorDetails(
        title: 'Watermark Removal Failed',
        message: failure.message,
        code: PdfErrorDetails.formatCode(
          failure.code ?? failure.failure.name,
          fallback: 'WATERMARK_REMOVAL_FAILED',
        ),
      );
    }
    final result = finished!.result;
    final code = PdfErrorDetails.formatCode(result.code, fallback: 'WATERMARK_REMOVAL_FAILED');
    if (finished.status == JobStatus.nothingRemoved) {
      return PdfErrorDetails(
        title: 'Nothing Was Removed',
        message: mode == RemovalMode.area
            ? 'Nothing lies fully inside the area you selected. Draw the rectangle a '
                  'little larger so it covers the whole watermark, then try again.'
            : (result.message ?? 'No removable watermark was found.'),
        code: code,
      );
    }
    return PdfErrorDetails(
      title: 'Watermark Removal Failed',
      message: result.message ?? "We couldn't remove the watermark. Please try processing again.",
      code: code,
    );
  }

  // ---------------------------------------------------------------- view

  String get _statusText {
    switch (_phase) {
      case _Phase.uploading:
        final progress = _progress;
        return progress == null
            ? 'Checking for watermarks…'
            : '${(progress * 100).round()}% — Preparing PDF';
      case _Phase.processing:
        return 'Processing — removing watermark';
      case _Phase.ready:
        final detected = _job?.detection.autoRemovableCount ?? 0;
        return detected > 0
            ? '$detected ${detected == 1 ? 'watermark' : 'watermarks'} detected'
            : 'Ready — select the watermark area';
    }
  }

  @override
  Widget build(BuildContext context) {
    final job = _job;
    final ready = _phase == _Phase.ready;
    final areaMode = _mode == RemovalMode.area;
    final autoAvailable = job?.detection.autoAvailable ?? false;
    final detected = job?.detection.autoRemovableCount ?? 0;
    final canApply =
        ready && !_selection.isDrawing && (areaMode ? _selection.hasArea : autoAvailable);
    final textTheme = Theme.of(context).textTheme;

    return PopScope(
      canPop: _phase != _Phase.processing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: AppScreen(
        headerActions: [
          HeaderAction('Back to Upload', () => Navigator.of(context).maybePop()),
        ],
        primaryAction: Tooltip(
          message: canApply
              ? (areaMode
                    ? 'Removes everything inside the selected area'
                    : 'Removes the detected watermarks')
              : 'Select the watermark area on the page first',
          child: FilledButton(
            key: const ValueKey('apply-selection-button'),
            onPressed: canApply ? () => _start(_mode) : null,
            child: Text(areaMode ? 'Apply Selection' : 'Remove Detected Watermarks'),
          ),
        ),
        children: [
          Semantics(
            header: true,
            child: Text(
              'Processing Your PDF',
              textAlign: TextAlign.center,
              style: textTheme.headlineMedium,
            ),
          ),
          const SizedBox(height: 26),
          Tooltip(
            message: _filename,
            child: Text(
              'Document: $_filename',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppText.bodyStrong,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(
                key: const ValueKey('size-chip'),
                avatar: const Icon(Icons.data_usage_outlined),
                label: Text(formatFileSize(widget.pdf.size)),
              ),
              if (job != null)
                Chip(
                  key: const ValueKey('pages-chip'),
                  avatar: const Icon(Icons.layers_outlined),
                  label: Text('${job.pageCount} ${job.pageCount == 1 ? 'page' : 'pages'}'),
                ),
            ],
          ),
          const SizedBox(height: 22),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 306),
              child: Semantics(
                label: 'Watermark processing',
                value: _statusText,
                child: LinearProgressIndicator(
                  key: const ValueKey('processing-progress'),
                  value: _progress,
                  minHeight: 10,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _statusText,
            key: const ValueKey('processing-status'),
            textAlign: TextAlign.center,
            style: AppText.bodyStrong,
          ),
          if (autoAvailable) ...[
            const SizedBox(height: 24),
            Center(
              child: SegmentedButton<RemovalMode>(
                key: const ValueKey('mode-selector'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: RemovalMode.area,
                    icon: Icon(Icons.crop_free),
                    label: Text('Mark area'),
                  ),
                  ButtonSegment(
                    value: RemovalMode.auto,
                    icon: Icon(Icons.auto_awesome_outlined),
                    label: Text('Automatic'),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: ready ? (modes) => _setMode(modes.first) : null,
              ),
            ),
          ],
          const SizedBox(height: 30),
          Semantics(
            header: true,
            child: Text(
              areaMode ? 'Manual Watermark Selection' : 'Detected Watermarks',
              textAlign: TextAlign.center,
              style: textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            areaMode
                ? 'Select the watermark area in the PDF preview.'
                : '$detected watermark ${detected == 1 ? 'object' : 'objects'} will be removed '
                      'from every page.',
            textAlign: TextAlign.center,
            style: AppText.caption,
          ),
          const SizedBox(height: 20),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 342),
              child: _PreviewCard(
                child: _preview == null || job == null
                    ? const Center(
                        child: Text(
                          'Loading first page…',
                          textAlign: TextAlign.center,
                          style: AppText.body,
                        ),
                      )
                    : PdfPageSelectionView(
                        page: PdfPagePreview(
                          bytes: _preview!,
                          width: job.previewWidth,
                          height: job.previewHeight,
                          pageCount: job.pageCount,
                        ),
                        filename: _filename,
                        controller: _selection,
                        onDecodeError: () {},
                        onInvalidSelection: () =>
                            _showMessage('Drag a larger rectangle inside the PDF page.'),
                      ),
              ),
            ),
          ),
          if (job != null && areaMode) ...[
            const SizedBox(height: 4),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 342),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        key: const ValueKey('clear-selection-button'),
                        onPressed: ready && (_selection.hasArea || _selection.isDrawing)
                            ? _selection.clear
                            : null,
                        icon: const Icon(Icons.close, size: 16),
                        label: const Text('Clear selection'),
                      ),
                    ),
                    if (job.pageCount > 1) ...[
                      const SizedBox(height: 4),
                      SegmentedButton<bool>(
                        key: const ValueKey('page-scope-selector'),
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: true,
                            icon: Icon(Icons.layers_outlined),
                            label: Text('All pages'),
                          ),
                          ButtonSegment(
                            value: false,
                            icon: Icon(Icons.filter_1_outlined),
                            label: Text('Page 1 only'),
                          ),
                        ],
                        selected: {_allPages},
                        onSelectionChanged: ready
                            ? (values) => setState(() => _allPages = values.first)
                            : null,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _allPages
                            ? 'The same area is cleared on all ${job.pageCount} pages.'
                            : 'Only page 1 is changed.',
                        textAlign: TextAlign.center,
                        style: AppText.caption,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The preview card of the design, tall enough to select an area comfortably.
class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // About the design's card height on a 844 px screen, taller on larger ones.
    final height = (MediaQuery.sizeOf(context).height * 0.3).clamp(210.0, 420.0);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: SizedBox(height: height, child: child),
      ),
    );
  }
}

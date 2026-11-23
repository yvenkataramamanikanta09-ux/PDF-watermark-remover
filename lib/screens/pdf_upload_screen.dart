import 'package:material_ui/material_ui.dart';

import '../services/app_services.dart';
import '../services/pdf_engine.dart';
import '../services/pdf_selection_service.dart';
import '../theme/app_theme.dart';
import '../utils/file_size.dart';
import '../widgets/app_screen.dart';
import '../widgets/home_header.dart';
import '../widgets/pdf_upload_card.dart';
import 'pdf_processing_screen.dart';

/// Figma frame "Upload": the upload card and the Choose PDF action.
class PdfUploadScreen extends StatefulWidget {
  const PdfUploadScreen({super.key, required this.services});

  static const routeName = '/pdf-upload';

  final AppServices services;

  @override
  State<PdfUploadScreen> createState() => _PdfUploadScreenState();
}

class _PdfUploadScreenState extends State<PdfUploadScreen> {
  EngineStatus? _engineStatus;
  EngineException? _engineError;
  bool _choosing = false;
  int _check = 0;

  AppServices get _services => widget.services;

  @override
  void initState() {
    super.initState();
    _checkEngine();
  }

  /// Starts the engine (the first start takes a moment) and learns its limits.
  Future<void> _checkEngine() async {
    final check = ++_check;
    EngineStatus? status;
    EngineException? error;
    try {
      status = await _services.engine.status();
    } on EngineException catch (failure) {
      error = failure;
    } catch (_) {
      error = const EngineException(EngineFailure.unavailable, 'The PDF engine could not start.');
    }
    if (!mounted || check != _check) return;
    setState(() {
      _engineStatus = status;
      _engineError = error;
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message, maxLines: 3, overflow: TextOverflow.ellipsis)),
      );
  }

  Future<void> _choosePdf() async {
    if (_choosing) return;
    setState(() => _choosing = true);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    try {
      final pdf = await _services.pdfSelection.selectPdf();
      if (!mounted || pdf == null) return;
      final limit = _engineStatus?.maxFileBytes;
      if (limit != null && pdf.size > limit) {
        _showMessage(
          'This PDF is ${formatFileSize(pdf.size)}. This phone can process PDFs up to ${formatFileSize(limit)}.',
        );
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: PdfProcessingScreen.routeName),
          builder: (context) => PdfProcessingScreen(pdf: pdf, services: _services),
        ),
      );
    } on PdfSelectionException catch (error) {
      if (mounted) _showMessage(error.message);
    } finally {
      if (mounted) setState(() => _choosing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final engineError = _engineError;
    return AppScreen(
      headerGap: 68,
      headerActions: [
        HeaderAction('Back to Home', () => Navigator.of(context).maybePop()),
      ],
      primaryAction: FilledButton(
        key: const ValueKey('choose-pdf-button'),
        onPressed: _choosing ? null : _choosePdf,
        child: const Text('Choose PDF'),
      ),
      children: [
        Semantics(
          header: true,
          child: Text('Upload Your PDF', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
        ),
        const SizedBox(height: 60),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 342),
            child: PdfUploadCard(
              onTap: _choosing ? null : _choosePdf,
              formatText: _engineStatus == null
                  ? 'PDF only'
                  : 'PDF only • up to ${_engineStatus!.maxFileBytes ~/ (1024 * 1024)} MB',
            ),
          ),
        ),
        if (engineError != null) ...[
          const SizedBox(height: 16),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 342),
              child: Card(
                key: const ValueKey('engine-warning'),
                color: AppColors.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'PDF engine unavailable',
                        style: AppText.bodyStrong.copyWith(color: AppColors.primaryText),
                      ),
                      const SizedBox(height: 4),
                      Text(engineError.message, style: AppText.caption),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Wrap(
                          children: [
                            TextButton(onPressed: _checkEngine, child: const Text('Try again')),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

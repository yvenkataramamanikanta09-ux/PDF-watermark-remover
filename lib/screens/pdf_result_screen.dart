import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../config.dart';
import '../models/job.dart';
import '../services/pdf_engine.dart';
import '../services/pdf_saver.dart';
import '../theme/app_theme.dart';
import '../widgets/app_screen.dart';
import '../widgets/home_header.dart';

/// Figma frame "Completed": the cleaned first page, its file name and Download PDF.
///
/// Pops with `true` when the user wants to select another area on the same PDF.
class PdfResultScreen extends StatefulWidget {
  const PdfResultScreen({
    super.key,
    required this.job,
    required this.cleanedFileName,
    required this.preview,
    required this.engine,
    required this.saver,
  });

  static const routeName = '/pdf-result';

  final JobInfo job;
  final String cleanedFileName;

  /// Page one of the cleaned PDF; null if it couldn't be fetched.
  final Uint8List? preview;
  final PdfEngine engine;
  final PdfSaver saver;

  @override
  State<PdfResultScreen> createState() => _PdfResultScreenState();
}

class _PdfResultScreenState extends State<PdfResultScreen> {
  bool _saving = false;

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _download() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final bytes = await widget.engine.result(widget.job.id);
      final saved = await widget.saver.save(fileName: widget.cleanedFileName, bytes: bytes);
      if (mounted && saved) _showMessage('Saved ${widget.cleanedFileName}.');
    } on EngineException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage("The PDF couldn't be saved. Try again.");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    final preview = widget.preview;
    final removed = widget.job.result.removedCount;
    final pages = widget.job.result.pagesChanged.length;
    return AppScreen(
      headerGap: 44,
      headerActions: [
        HeaderAction('Select another area', () => Navigator.of(context).pop(true)),
        HeaderAction(
          'Back to Home',
          () => Navigator.of(context).popUntil((route) => route.isFirst),
        ),
      ],
      primaryAction: FilledButton(
        key: const ValueKey('download-button'),
        onPressed: _saving ? null : _download,
        child: Text(_saving ? 'Preparing…' : 'Download PDF'),
      ),
      children: [
        const StatusBadge.success(),
        const SizedBox(height: 16),
        Semantics(
          header: true,
          child: Text(
            'Processing Completed!',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        ),
        const SizedBox(height: 22),
        const Text(
          'Your PDF is ready to download.',
          textAlign: TextAlign.center,
          style: AppText.bodyStrong,
        ),
        const SizedBox(height: 32),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 342),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                child: Column(
                  children: [
                    SizedBox(
                      height: 194,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: preview == null
                            ? const _PagePlaceholder()
                            : Image.memory(
                                preview,
                                fit: BoxFit.contain,
                                semanticLabel: 'First page of the cleaned PDF',
                                errorBuilder: (context, error, stackTrace) =>
                                    const _PagePlaceholder(),
                              ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      widget.cleanedFileName,
                      key: const ValueKey('cleaned-file-name'),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 12),
                    Chip(
                      key: const ValueKey('removed-chip'),
                      avatar: const Icon(Icons.auto_fix_high_outlined),
                      label: Text(
                        '$removed ${removed == 1 ? 'object' : 'objects'} removed'
                        '${pages > 0 ? ' • $pages ${pages == 1 ? 'page' : 'pages'}' : ''}',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(privacyNote, textAlign: TextAlign.center, style: AppText.caption),
      ],
    );
  }
}

/// The plain white "PDF" page of the design, used when no preview image exists.
class _PagePlaceholder extends StatelessWidget {
  const _PagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 116,
      color: Colors.white,
      alignment: Alignment.center,
      child: const Text(
        'PDF',
        style: TextStyle(
          color: AppColors.navy,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

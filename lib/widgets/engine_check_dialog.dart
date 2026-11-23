import 'package:material_ui/material_ui.dart';

import '../services/pdf_engine.dart';
import '../theme/app_theme.dart';

/// Runs the whole engine once on a built-in sample PDF and shows each step.
///
/// This is how to confirm on a real phone that the embedded Python engine, PDFium and Pillow
/// all load and work, without needing a watermarked PDF at hand.
abstract final class EngineCheckDialog {
  static Future<void> show(BuildContext context, PdfEngine engine) {
    return showDialog<void>(
      context: context,
      builder: (context) => _EngineCheckDialog(engine: engine),
    );
  }
}

class _EngineCheckDialog extends StatefulWidget {
  const _EngineCheckDialog({required this.engine});
  final PdfEngine engine;

  @override
  State<_EngineCheckDialog> createState() => _EngineCheckDialogState();
}

class _EngineCheckDialogState extends State<_EngineCheckDialog> {
  SelfTestReport? _report;
  EngineStatus? _status;
  EngineException? _error;
  bool _running = true;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _error = null;
    });
    SelfTestReport? report;
    EngineStatus? status;
    EngineException? error;
    try {
      status = await widget.engine.status();
      report = await widget.engine.selfTest();
    } on EngineException catch (failure) {
      error = failure;
    } catch (_) {
      error = const EngineException(EngineFailure.failed, 'The engine check failed.');
    }
    if (!mounted) return;
    setState(() {
      _report = report;
      _status = status;
      _error = error;
      _running = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final report = _report;
    final status = _status;
    final ok = !_running && _error == null && (report?.ok ?? false);

    Widget body;
    if (_running) {
      body = const Row(
        children: [
          SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
          SizedBox(width: 16),
          Expanded(child: Text('Running the engine on a sample PDF…')),
        ],
      );
    } else if (_error != null) {
      body = Text(
        '${_error!.message}\nError code: ${_error!.code ?? 'UNKNOWN_ERROR'}',
        key: const ValueKey('engine-check-error'),
      );
    } else {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final step in report!.steps)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    step.ok ? Icons.check_circle_outline : Icons.error_outline,
                    size: 20,
                    color: step.ok ? AppColors.success : AppColors.accent,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      step.detail.isEmpty ? step.name : '${step.name} (${step.detail})',
                      style: textTheme.bodyMedium?.copyWith(color: AppColors.primaryText),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          Text(
            'Finished in ${report.seconds.toStringAsFixed(1)} s.\n'
            'Python ${status!.python} · pypdf ${status.pypdf} · PDFium ${status.pdfium} · '
            'Pillow ${status.pillow}',
            style: textTheme.bodySmall?.copyWith(color: AppColors.secondaryText),
          ),
        ],
      );
    }

    return AlertDialog(
      icon: Icon(
        _running
            ? Icons.build_circle_outlined
            : (ok ? Icons.verified_outlined : Icons.error_outline),
        color: _running ? null : (ok ? AppColors.success : AppColors.accent),
      ),
      title: Text(
        _running ? 'Checking the PDF engine' : (ok ? 'The PDF engine works' : 'The PDF engine check failed'),
      ),
      content: SingleChildScrollView(child: body),
      actions: [
        if (!_running && !ok) TextButton(onPressed: _run, child: const Text('Try again')),
        TextButton(
          key: const ValueKey('engine-check-close'),
          onPressed: _running ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

import 'pdf_engine.dart';
import 'pdf_saver.dart';
import 'pdf_selection_service.dart';

/// The app's long-lived services, created once in main.dart and handed to
/// every screen (tests pass fakes).
final class AppServices {
  const AppServices({
    required this.pdfSelection,
    required this.engine,
    required this.saver,
  });

  final PdfSelectionService pdfSelection;

  /// The watermark engine that runs on this phone.
  final PdfEngine engine;
  final PdfSaver saver;
}

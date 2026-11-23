import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'screens/home_screen.dart';
import 'services/app_services.dart';
import 'services/file_picker_pdf_document_picker.dart';
import 'services/on_device_pdf_engine.dart';
import 'services/pdf_saver.dart';
import 'services/pdf_selection_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    for (final (package, file) in const [
      ('Figtree', 'assets/fonts/OFL-Figtree.txt'),
      ('Newsreader', 'assets/fonts/OFL-Newsreader.txt'),
    ]) {
      yield LicenseEntryWithLineBreaks([package], await rootBundle.loadString(file));
    }
  });
  runApp(
    MyApp(
      services: AppServices(
        pdfSelection: PdfSelectionService(picker: const FilePickerPdfDocumentPicker()),
        engine: OnDevicePdfEngine(),
        saver: const FilePickerPdfSaver(),
      ),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.services});

  /// Tests pass fakes here.
  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PDF Watermark Remover',
      debugShowCheckedModeBanner: false,
      // The design is dark only; it is expressed as a Material 3 theme.
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: HomeScreen(services: services),
    );
  }
}

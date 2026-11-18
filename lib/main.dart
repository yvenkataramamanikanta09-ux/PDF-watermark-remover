import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'screens/home_screen.dart';
import 'services/file_picker_pdf_document_picker.dart';
import 'services/pdf_selection_service.dart';
import 'services/pdf_preview_service.dart';
import 'services/local_pdf_preview_service.dart';
import 'services/pdf_area_selection_controller.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString('assets/fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(const ['Inter'], license);
  });
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({
    super.key,
    this.pdfSelectionService,
    this.pdfPreviewService,
    this.areaSelectionController,
  });

  final PdfSelectionService? pdfSelectionService;
  final PdfPreviewService? pdfPreviewService;
  final PdfAreaSelectionController? areaSelectionController;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final PdfSelectionService _pdfSelectionService =
      widget.pdfSelectionService ??
      PdfSelectionService(picker: const FilePickerPdfDocumentPicker());
  late final PdfPreviewService _pdfPreviewService =
      widget.pdfPreviewService ?? LocalPdfPreviewService();
  late final PdfAreaSelectionController _areaSelectionController =
      widget.areaSelectionController ?? PdfAreaSelectionController();

  @override
  void dispose() {
    if (widget.areaSelectionController == null) {
      _areaSelectionController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PDF Watermark Remover',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: HomeScreen(
        pdfSelectionService: _pdfSelectionService,
        pdfPreviewService: _pdfPreviewService,
        areaSelectionController: _areaSelectionController,
      ),
    );
  }
}

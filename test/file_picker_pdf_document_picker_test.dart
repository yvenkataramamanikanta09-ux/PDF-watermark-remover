import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_watermark_remover/services/file_picker_pdf_document_picker.dart';
import 'package:pdf_watermark_remover/services/pdf_selection_service.dart';

class _PickerPlatform extends FilePickerPlatform {
  PlatformFile? result;
  Object? error;
  int calls = 0;
  FileType? requestedType;
  List<String>? requestedExtensions;

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    calls++;
    requestedType = type;
    requestedExtensions = allowedExtensions;
    if (error != null) throw error!;
    return result;
  }
}

final class _PickedPlatformFile extends PlatformFile {
  int streamCalls = 0;
  int fullReadCalls = 0;

  @override
  String get name => 'native.pdf';

  @override
  Uri get uri => Uri.file('/app/cache/native.pdf');

  @override
  Never get xFile => throw StateError('The adapter must use the stream API');

  @override
  int? lengthSync() => 4096;

  @override
  Future<int?> length() async => 4096;

  @override
  Future<Uint8List> readAsBytes() async {
    fullReadCalls++;
    throw StateError('Full-file reads are not allowed');
  }

  @override
  Stream<Uint8List> readAsByteStream() {
    streamCalls++;
    return Stream.value(Uint8List.fromList('%PDF-1.7\n'.codeUnits));
  }
}

void main() {
  late FilePickerPlatform original;
  late _PickerPlatform platform;

  setUp(() {
    original = FilePickerPlatform.instance;
    platform = _PickerPlatform();
    FilePickerPlatform.instance = platform;
  });
  tearDown(() => FilePickerPlatform.instance = original);

  test('Uses the installed single-file API with PDF filtering', () async {
    final file = _PickedPlatformFile();
    platform.result = file;
    const picker = FilePickerPdfDocumentPicker();
    final document = (await picker.pickPdf())!;
    expect(platform.calls, 1);
    expect(platform.requestedType, FileType.custom);
    expect(platform.requestedExtensions, ['pdf']);
    expect(document.name, 'native.pdf');
    expect(document.uri, file.uri);
    expect(await document.length(), 4096);
  });

  test('Returns null for native picker cancellation', () async {
    expect(await const FilePickerPdfDocumentPicker().pickPdf(), isNull);
  });

  test(
    'Validation uses repeatable streams without loading the entire PDF',
    () async {
      final file = _PickedPlatformFile();
      platform.result = file;
      final service = PdfSelectionService(
        picker: const FilePickerPdfDocumentPicker(),
      );
      final selected = (await service.selectPdf())!;
      expect(file.fullReadCalls, 0);
      expect(file.streamCalls, 1);
      expect(await selected.content.openRead().first, '%PDF-1.7\n'.codeUnits);
      expect(file.streamCalls, 2);
    },
  );

  test('Native platform errors become friendly selection errors', () async {
    platform.error = PlatformException(code: 'provider_unavailable');
    final service = PdfSelectionService(
      picker: const FilePickerPdfDocumentPicker(),
    );
    await expectLater(
      service.selectPdf(),
      throwsA(
        isA<PdfSelectionException>().having(
          (error) => error.failure,
          'failure',
          PdfSelectionFailure.pickerUnavailable,
        ),
      ),
    );
  });
}

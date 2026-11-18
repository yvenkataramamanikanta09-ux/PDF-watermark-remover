import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_watermark_remover/models/selected_pdf.dart';
import 'package:pdf_watermark_remover/services/pdf_selection_service.dart';

import 'fakes/pdf_selection_fakes.dart';

void main() {
  Matcher failsWith(PdfSelectionFailure failure) => throwsA(
    isA<PdfSelectionException>().having((e) => e.failure, 'failure', failure),
  );

  test(
    'Valid selection preserves metadata and a fresh readable reference',
    () async {
      final document = FakePdfDocument(name: 'Report.PDF');
      final service = PdfSelectionService(
        picker: FakePdfDocumentPicker(result: document),
      );

      final selected = (await service.selectPdf())!;
      expect(selected.name, 'Report.PDF');
      expect(selected.size, document.bytes.length);
      expect(selected.content.uri, document.uri);
      expect(selected.content, same(document));
      expect(service.selectedPdf, same(selected));
      final reread = await selected.content
          .openRead()
          .expand((chunk) => chunk)
          .toList();
      expect(reread, document.bytes);
      expect(document.openCalls, 2);
    },
  );

  for (final header in ['%PDF-1.0\n', '%PDF-1.7\r\n', '%PDF-2.0\n']) {
    test('Recognizes standard PDF header ${header.trim()}', () async {
      final document = FakePdfDocument(bytes: '$header body'.codeUnits);
      final service = PdfSelectionService(
        picker: FakePdfDocumentPicker(result: document),
      );
      expect(await service.selectPdf(), isNotNull);
    });
  }

  test('Canceled selection returns null without changing state', () async {
    final service = PdfSelectionService(picker: FakePdfDocumentPicker());
    expect(await service.selectPdf(), isNull);
    expect(service.selectedPdf, isNull);
  });

  test('Rejects other extensions before accessing file content', () async {
    for (final name in ['notes.txt', 'invoice.pdf.exe', 'README']) {
      final document = FakePdfDocument(name: name);
      final service = PdfSelectionService(
        picker: FakePdfDocumentPicker(result: document),
      );
      await expectLater(
        service.selectPdf(),
        failsWith(PdfSelectionFailure.invalidExtension),
      );
      expect(document.lengthCalls, 0);
      expect(document.openCalls, 0);
      expect(service.selectedPdf, isNull);
    }
  });

  test('Rejects a renamed non-PDF file', () async {
    final service = PdfSelectionService(
      picker: FakePdfDocumentPicker(
        result: FakePdfDocument(bytes: '<html>not a PDF</html>'.codeUnits),
      ),
    );
    await expectLater(
      service.selectPdf(),
      failsWith(PdfSelectionFailure.invalidHeader),
    );
  });

  test(
    'Rejects truncated headers, malformed versions, and leading junk',
    () async {
      for (final header in [
        '%PDF-1.7',
        '%PDF-1.x\n',
        '%PDF-1.78',
        'junk%PDF-1.7\n',
      ]) {
        final service = PdfSelectionService(
          picker: FakePdfDocumentPicker(
            result: FakePdfDocument(bytes: header.codeUnits),
          ),
        );
        await expectLater(
          service.selectPdf(),
          failsWith(PdfSelectionFailure.invalidHeader),
        );
      }
    },
  );

  test('Rejects an empty file without opening a stream', () async {
    final document = FakePdfDocument(bytes: []);
    final service = PdfSelectionService(
      picker: FakePdfDocumentPicker(result: document),
    );
    await expectLater(
      service.selectPdf(),
      failsWith(PdfSelectionFailure.emptyFile),
    );
    expect(document.openCalls, 0);
  });

  test(
    'Rejects an empty stream even if the provider reports a positive size',
    () async {
      final service = PdfSelectionService(
        picker: FakePdfDocumentPicker(
          result: FakePdfDocument(bytes: [], reportedSize: 1024),
        ),
      );
      await expectLater(
        service.selectPdf(),
        failsWith(PdfSelectionFailure.emptyFile),
      );
    },
  );

  test('Unknown or negative sizes are reported as unreadable', () async {
    for (final document in [
      FakePdfDocument(unknownSize: true),
      FakePdfDocument(reportedSize: -1),
    ]) {
      final service = PdfSelectionService(
        picker: FakePdfDocumentPicker(result: document),
      );
      await expectLater(
        service.selectPdf(),
        failsWith(PdfSelectionFailure.unreadableFile),
      );
    }
  });

  test(
    'Handles metadata access exceptions without leaking their contents',
    () async {
      final service = PdfSelectionService(
        picker: FakePdfDocumentPicker(
          result: FakePdfDocument(
            lengthError: const FileSystemException('private path and detail'),
          ),
        ),
      );
      try {
        await service.selectPdf();
        fail('Expected an access error');
      } on PdfSelectionException catch (error) {
        expect(error.failure, PdfSelectionFailure.unreadableFile);
        expect(error.message, isNot(contains('private path')));
        expect(error.toString(), isNot(contains('private path')));
      }
    },
  );

  test('Handles stream read exceptions', () async {
    final service = PdfSelectionService(
      picker: FakePdfDocumentPicker(
        result: FakePdfDocument(readError: const FileSystemException('denied')),
      ),
    );
    await expectLater(
      service.selectPdf(),
      failsWith(PdfSelectionFailure.unreadableFile),
    );
  });

  test('Handles exceptions opening the content stream', () async {
    final service = PdfSelectionService(
      picker: FakePdfDocumentPicker(
        result: FakePdfDocument(
          streamFactory: () => throw StateError('unavailable'),
        ),
      ),
    );
    await expectLater(
      service.selectPdf(),
      failsWith(PdfSelectionFailure.unreadableFile),
    );
  });

  test('Handles a read failure after a partial header', () async {
    Stream<List<int>> unreadable() async* {
      yield '%PDF-'.codeUnits;
      throw const FileSystemException('provider disconnected');
    }

    final service = PdfSelectionService(
      picker: FakePdfDocumentPicker(
        result: FakePdfDocument(streamFactory: unreadable),
      ),
    );
    await expectLater(
      service.selectPdf(),
      failsWith(PdfSelectionFailure.unreadableFile),
    );
  });

  test('Reads a header split across multiple chunks', () async {
    final service = PdfSelectionService(
      picker: FakePdfDocumentPicker(
        result: FakePdfDocument(
          streamFactory: () => Stream.fromIterable([
            [],
            '%P'.codeUnits,
            'DF-1'.codeUnits,
            '.7\n'.codeUnits,
            'body'.codeUnits,
          ]),
        ),
      ),
    );
    expect(await service.selectPdf(), isNotNull);
  });

  test(
    'A large file validates only its prefix and closes the stream',
    () async {
      var closed = false;
      var bodyRequested = false;
      Stream<List<int>> largeDocument() async* {
        try {
          yield '%PDF-1.7\n'.codeUnits;
          bodyRequested = true;
          throw StateError('The rest of this large PDF must not be loaded');
        } finally {
          closed = true;
        }
      }

      final document = FakePdfDocument(
        reportedSize: 5 * 1024 * 1024 * 1024,
        streamFactory: largeDocument,
      );
      final service = PdfSelectionService(
        picker: FakePdfDocumentPicker(result: document),
      );
      final selected = await service.selectPdf();
      expect(selected!.size, 5 * 1024 * 1024 * 1024);
      expect(bodyRequested, isFalse);
      expect(closed, isTrue);
    },
  );

  test('Picker failures are converted to a friendly selection error', () async {
    final service = PdfSelectionService(
      picker: FakePdfDocumentPicker(error: StateError('native failure')),
    );
    await expectLater(
      service.selectPdf(),
      failsWith(PdfSelectionFailure.pickerUnavailable),
    );
  });

  test(
    'Canceling or rejecting a replacement preserves the previous PDF',
    () async {
      final picker = FakePdfDocumentPicker(result: FakePdfDocument());
      final service = PdfSelectionService(picker: picker);
      final first = await service.selectPdf();
      picker.result = null;
      expect(await service.selectPdf(), isNull);
      expect(service.selectedPdf, same(first));
      picker.result = FakePdfDocument(name: 'not-a-pdf.txt');
      await expectLater(
        service.selectPdf(),
        failsWith(PdfSelectionFailure.invalidExtension),
      );
      expect(service.selectedPdf, same(first));
    },
  );

  test('Concurrent requests use a single picker operation', () async {
    final pending = Completer<PdfDocument?>();
    final picker = FakePdfDocumentPicker(onPick: () => pending.future);
    final service = PdfSelectionService(picker: picker);
    final first = service.selectPdf();
    final second = service.selectPdf();
    expect(second, same(first));
    expect(picker.calls, 1);
    pending.complete(FakePdfDocument());
    expect(await first, same(await second));
  });

  test('Selection can be retried after a picker failure', () async {
    final picker = FakePdfDocumentPicker(error: StateError('unavailable'));
    final service = PdfSelectionService(picker: picker);
    await expectLater(
      service.selectPdf(),
      failsWith(PdfSelectionFailure.pickerUnavailable),
    );
    picker.error = null;
    picker.result = FakePdfDocument();
    expect(await service.selectPdf(), isNotNull);
    expect(picker.calls, 2);
  });
}

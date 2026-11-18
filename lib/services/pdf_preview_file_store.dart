import 'dart:io';

import '../models/selected_pdf.dart';
import 'pdf_preview_service.dart';

/// Owns only files created for a stream-only reference; never the picked PDF.
final class PreparedPdfFile {
  PreparedPdfFile(this.path, {this._ownedDirectory});

  final String path;
  final Directory? _ownedDirectory;
  bool _disposed = false;

  Future<void> dispose() async {
    if (_disposed || _ownedDirectory == null) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
    if (await _ownedDirectory.exists()) await _ownedDirectory.delete();
    _disposed = true;
  }
}

final class PdfPreviewFileStore {
  PdfPreviewFileStore({
    Future<Directory> Function()? createTemporaryDirectory,
    this.maxCopyBytes = 256 * 1024 * 1024,
  }) : _createTemporaryDirectory =
           createTemporaryDirectory ??
           (() => Directory.systemTemp.createTemp('pdf_preview_'));

  final Future<Directory> Function() _createTemporaryDirectory;
  final int maxCopyBytes;

  Future<PreparedPdfFile> prepare(
    SelectedPdf pdf, {
    required PdfPreviewCancellation cancellation,
  }) async {
    cancellation.throwIfCancelled();
    try {
      final uri = pdf.content.uri;
      if (uri.scheme == 'file') {
        final file = File.fromUri(uri);
        final stat = await file.stat();
        cancellation.throwIfCancelled();
        if (stat.type != FileSystemEntityType.file ||
            stat.size <= 0 ||
            stat.size != pdf.size) {
          throw const PdfPreviewException(PdfPreviewFailure.unreadable);
        }
        // The native renderer uses this existing reference without a second copy.
        return PreparedPdfFile(file.path);
      }
      if (pdf.size > maxCopyBytes) {
        throw const PdfPreviewException(PdfPreviewFailure.copyTooLarge);
      }

      final directory = await _createTemporaryDirectory();
      // Constant basename: document-provided names never become filesystem paths.
      final prepared = PreparedPdfFile(
        '${directory.path}${Platform.pathSeparator}preview.pdf',
        ownedDirectory: directory,
      );
      try {
        cancellation.throwIfCancelled();
        final output = await File(prepared.path).open(mode: FileMode.write);
        var copied = 0;
        try {
          await for (final chunk in pdf.content.openRead()) {
            cancellation.throwIfCancelled();
            copied += chunk.length;
            if (copied > maxCopyBytes) {
              throw const PdfPreviewException(PdfPreviewFailure.copyTooLarge);
            }
            await output.writeFrom(chunk);
          }
        } finally {
          await output.close();
        }
        cancellation.throwIfCancelled();
        if (copied == 0 || copied != pdf.size) {
          throw const PdfPreviewException(PdfPreviewFailure.unreadable);
        }
        return prepared;
      } catch (_) {
        await prepared.dispose();
        rethrow;
      }
    } on PdfPreviewException {
      rethrow;
    } on PdfPreviewCancelled {
      rethrow;
    } catch (_) {
      throw const PdfPreviewException(PdfPreviewFailure.unreadable);
    }
  }
}

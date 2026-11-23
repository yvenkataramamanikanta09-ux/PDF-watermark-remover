import 'package:flutter/foundation.dart';

import '../models/job.dart';
import '../models/pdf_area_selection.dart';
import '../models/selected_pdf.dart';

enum EngineFailure {
  /// The embedded Python engine could not start (should not happen on a supported phone).
  unavailable,

  /// The document was refused: not a readable PDF, password protected, too large.
  rejected,

  /// The job's files are gone (cache cleared). Choose the document again.
  notFound,

  /// Processing stopped unexpectedly; trying again can work.
  failed,
}

final class EngineException implements Exception {
  const EngineException(this.failure, this.message, {this.code});

  final EngineFailure failure;

  /// Plain-language text for the user.
  final String message;

  /// The engine's machine-readable code, when it produced one (upper-cased for display).
  final String? code;

  @override
  String toString() => 'EngineException(${failure.name}, $code)';
}

/// What the engine reports about itself, and the limits the app enforces up front.
final class EngineStatus {
  const EngineStatus({
    required this.maxFileBytes,
    required this.maxPages,
    required this.python,
    required this.pypdf,
    required this.pdfium,
    required this.pillow,
  });

  factory EngineStatus.fromJson(Map<String, dynamic> json) => EngineStatus(
    maxFileBytes: json['max_file_bytes'] as int,
    maxPages: json['max_pages'] as int,
    python: json['python'] as String,
    pypdf: json['pypdf'] as String,
    pdfium: json['pypdfium2'] as String,
    pillow: json['pillow'] as String,
  );

  final int maxFileBytes;
  final int maxPages;
  final String python;
  final String pypdf;
  final String pdfium;
  final String pillow;
}

final class SelfTestStep {
  const SelfTestStep({required this.name, required this.ok, required this.detail});

  final String name;
  final bool ok;
  final String detail;
}

/// Result of running the whole engine once on a built-in sample PDF.
final class SelfTestReport {
  const SelfTestReport({required this.ok, required this.steps, required this.seconds});

  factory SelfTestReport.fromJson(Map<String, dynamic> json) => SelfTestReport(
    ok: json['ok'] as bool,
    steps: [
      for (final step in json['steps'] as List<dynamic>)
        SelfTestStep(
          name: (step as Map<String, dynamic>)['name'] as String,
          ok: step['ok'] as bool,
          detail: step['detail'] as String? ?? '',
        ),
    ],
    seconds: (json['seconds'] as num).toDouble(),
  );

  final bool ok;
  final List<SelfTestStep> steps;
  final double seconds;
}

/// The watermark engine that runs on the phone. The Android implementation is
/// [OnDevicePdfEngine]; tests use fakes.
abstract interface class PdfEngine {
  /// Starts the engine if needed and returns its limits; throws [EngineException]
  /// (unavailable) if it cannot run.
  Future<EngineStatus> status();

  /// Copies the PDF into a private working folder, detects watermarks and renders page one.
  /// [onProgress] reports 0..1 while the file is copied.
  Future<JobInfo> analyze(SelectedPdf pdf, {void Function(double progress)? onProgress});

  /// Page one as a PNG; the selection rectangle is relative to this image.
  Future<Uint8List> preview(String jobId);

  /// Removes watermarks (auto) or everything inside [area]; returns when finished.
  Future<JobInfo> removeWatermark(
    String jobId, {
    required RemovalMode mode,
    PdfNormalizedRect? area,
    bool allPages = true,
  });

  Future<Uint8List> result(String jobId);
  Future<Uint8List> resultPreview(String jobId);

  /// Deletes the job's files.
  Future<void> deleteJob(String jobId);

  Future<SelfTestReport> selfTest();
}

/// Formats engine and platform codes for the "Error code:" line.
abstract final class PdfEngineCodes {
  static String format(String? code, {String fallback = 'UNKNOWN_ERROR'}) {
    final cleaned = (code ?? '').trim().replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_').toUpperCase();
    return cleaned.isEmpty ? fallback : cleaned;
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf_watermark_remover/models/job.dart';
import 'package:pdf_watermark_remover/models/pdf_area_selection.dart';
import 'package:pdf_watermark_remover/models/selected_pdf.dart';
import 'package:pdf_watermark_remover/services/pdf_engine.dart';
import 'package:pdf_watermark_remover/services/pdf_saver.dart';

/// A valid 1x1 PNG, so Image.memory decodes in widget tests.
final Uint8List tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

Map<String, dynamic> jobJson({
  String status = 'ready',
  bool auto = false,
  int pages = 3,
  String? mode,
  String? outcome,
  String? message,
  int removed = 0,
  List<int> pagesChanged = const [],
}) => {
  'job_id': 'job-1',
  'filename': 'sample.pdf',
  'size': 1234,
  'sha256': 'a' * 64,
  'page_count': pages,
  'status': status,
  'detection': {
    'outcome': auto ? 'supported_watermark_detected' : 'no_supported_watermark_detected',
    'code': 'annotation_scan_complete',
    'supported_count': 0,
    'unsupported_count': 0,
    'artifact_count': auto ? 3 : 0,
    'auto_available': auto,
  },
  'preview': {'width': 791, 'height': 1024, 'coordinate_space': 'renderedPageTopLeft'},
  'result': {
    'mode': mode,
    'outcome': outcome,
    'code': outcome == null ? null : 'code',
    'message': message,
    'removed_count': removed,
    'removed_by_kind': <String, int>{},
    'pages_changed': pagesChanged,
  },
  'expires_at': '2026-11-18T12:00:00',
};

JobInfo job({
  String status = 'ready',
  bool auto = false,
  int pages = 3,
  String? mode,
  String? outcome,
  String? message,
  int removed = 0,
  List<int> pagesChanged = const [],
}) => JobInfo.fromJson(
  jobJson(
    status: status,
    auto: auto,
    pages: pages,
    mode: mode,
    outcome: outcome,
    message: message,
    removed: removed,
    pagesChanged: pagesChanged,
  ),
);

class FakeEngine implements PdfEngine {
  FakeEngine({JobInfo? analyzed, JobInfo? removal})
    : analyzed = analyzed ?? job(),
      removal = removal ?? job(status: 'succeeded', mode: 'area', outcome: 'watermark_removed_successfully', removed: 3, pagesChanged: [1, 2, 3]);

  /// Returned by analyze().
  JobInfo analyzed;

  /// Returned by removeWatermark().
  JobInfo removal;

  EngineException? statusError;
  EngineException? analyzeError;
  EngineException? removeError;
  Completer<void>? analyzeGate;
  Completer<void>? removeGate;
  int maxFileBytes = 40 * 1024 * 1024;

  /// Page-one image returned by preview(); defaults to a 1x1 PNG.
  Uint8List? previewBytes;
  SelfTestReport selfTestReport = const SelfTestReport(
    ok: true,
    steps: [SelfTestStep(name: 'remove watermark', ok: true, detail: '')],
    seconds: 1.5,
  );

  int statusCalls = 0;
  int analyzeCalls = 0;
  final deleted = <String>[];
  RemovalMode? removedMode;
  PdfNormalizedRect? removedArea;
  bool? removedAllPages;

  @override
  Future<EngineStatus> status() async {
    statusCalls++;
    if (statusError != null) throw statusError!;
    return EngineStatus(
      maxFileBytes: maxFileBytes,
      maxPages: 100,
      python: '3.13.0',
      pypdf: '7.1.0',
      pdfium: '5.15.2',
      pillow: '11.0.0',
    );
  }

  @override
  Future<JobInfo> analyze(SelectedPdf pdf, {void Function(double progress)? onProgress}) async {
    analyzeCalls++;
    onProgress?.call(0.5);
    await analyzeGate?.future;
    if (analyzeError != null) throw analyzeError!;
    onProgress?.call(1);
    return analyzed;
  }

  @override
  Future<Uint8List> preview(String jobId) async => previewBytes ?? tinyPng;

  @override
  Future<JobInfo> removeWatermark(
    String jobId, {
    required RemovalMode mode,
    PdfNormalizedRect? area,
    bool allPages = true,
  }) async {
    removedMode = mode;
    removedArea = area;
    removedAllPages = allPages;
    await removeGate?.future;
    if (removeError != null) throw removeError!;
    return removal;
  }

  @override
  Future<Uint8List> result(String jobId) async => Uint8List.fromList('%PDF-1.7\nclean'.codeUnits);

  @override
  Future<Uint8List> resultPreview(String jobId) async => tinyPng;

  @override
  Future<void> deleteJob(String jobId) async => deleted.add(jobId);

  @override
  Future<SelfTestReport> selfTest() async => selfTestReport;
}

class FakeSaver implements PdfSaver {
  bool accept = true;
  String? fileName;
  Uint8List? bytes;

  @override
  Future<bool> save({required String fileName, required Uint8List bytes}) async {
    this.fileName = fileName;
    this.bytes = bytes;
    return accept;
  }
}

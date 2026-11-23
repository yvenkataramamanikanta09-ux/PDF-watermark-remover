import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../models/job.dart';
import '../models/pdf_area_selection.dart';
import '../models/selected_pdf.dart';
import 'pdf_engine.dart';

/// Runs the Python watermark engine that is embedded in the app (see MainActivity.kt and
/// android/app/src/main/python/pdfwm_mobile.py). Nothing leaves the phone.
///
/// Files are exchanged on disk in a private cache folder per job; only small JSON strings
/// cross the platform channel.
final class OnDevicePdfEngine implements PdfEngine {
  OnDevicePdfEngine({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('pdfwm/engine');

  final MethodChannel _channel;
  String? _jobsRoot;
  EngineStatus? _status;

  static const _unavailable =
      'The PDF engine on this phone could not start. Restart the app; if it keeps '
      'happening, this phone may not be supported.';

  Future<String> _call(String method, [Map<String, Object?>? arguments]) async {
    try {
      final reply = await _channel.invokeMethod<String>(method, arguments);
      return reply ?? '';
    } on MissingPluginException {
      throw const EngineException(EngineFailure.unavailable, _unavailable, code: 'ENGINE_MISSING');
    } on PlatformException catch (error) {
      // Starting the engine is the "info" call; a failure there means it cannot run at all.
      // Later failures are unexpected stops of one job, and trying again can work.
      final starting = method == 'info' || method == 'selfTest';
      throw EngineException(
        starting ? EngineFailure.unavailable : EngineFailure.failed,
        starting ? _unavailable : 'Processing stopped unexpectedly. Try again.',
        code: PdfEngineCodes.format(error.code),
      );
    }
  }

  /// Decodes a reply from the Python adapter; `{"error": ...}` becomes an [EngineException].
  Map<String, dynamic> _decode(String reply) {
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(reply) as Map<String, dynamic>;
    } catch (_) {
      throw const EngineException(EngineFailure.failed, 'The engine sent an unexpected reply.');
    }
    final error = json['error'];
    if (error is Map<String, dynamic>) {
      final failure = switch (error['kind']) {
        'rejected' => EngineFailure.rejected,
        'not_found' => EngineFailure.notFound,
        _ => EngineFailure.failed,
      };
      throw EngineException(
        failure,
        error['message'] as String? ?? 'Processing failed.',
        code: PdfEngineCodes.format(error['code'] as String?),
      );
    }
    return json;
  }

  JobInfo _job(Map<String, dynamic> json) {
    try {
      return JobInfo.fromJson(json);
    } catch (_) {
      throw const EngineException(EngineFailure.failed, 'The engine sent an unexpected reply.');
    }
  }

  Future<String> _root() async {
    final cached = _jobsRoot;
    if (cached != null) return cached;
    final reply = await _channel.invokeMapMethod<String, String>('paths').catchError(
      (Object _) => null,
    );
    final root = reply?['jobsRoot'];
    if (root == null) {
      throw const EngineException(EngineFailure.unavailable, _unavailable, code: 'ENGINE_MISSING');
    }
    return _jobsRoot = root;
  }

  Future<File> _file(String jobId, String name) async {
    if (!RegExp(r'^[0-9a-f-]{36}$').hasMatch(jobId)) {
      throw const EngineException(EngineFailure.notFound, 'This document is no longer available.');
    }
    return File('${await _root()}${Platform.pathSeparator}$jobId${Platform.pathSeparator}$name');
  }

  @override
  Future<EngineStatus> status() async {
    final cached = _status;
    if (cached != null) return cached;
    final json = _decode(await _call('info'));
    try {
      return _status = EngineStatus.fromJson(json);
    } catch (_) {
      throw const EngineException(EngineFailure.unavailable, _unavailable, code: 'ENGINE_REPLY');
    }
  }

  @override
  Future<JobInfo> analyze(SelectedPdf pdf, {void Function(double progress)? onProgress}) async {
    final limits = await status();
    if (pdf.size > limits.maxFileBytes) {
      throw EngineException(
        EngineFailure.rejected,
        'This PDF is larger than the ${limits.maxFileBytes ~/ (1024 * 1024)} MB this phone can process.',
        code: 'FILE_TOO_LARGE',
      );
    }
    final created = _decode(await _call('newJob'));
    final jobId = created['job_id'] as String;
    final directory = created['dir'] as String;
    try {
      await _copyInto(pdf, File('$directory${Platform.pathSeparator}original.pdf'), onProgress);
      final reply = _decode(await _call('analyze', {'jobId': jobId, 'filename': pdf.name}));
      return _job(reply);
    } catch (_) {
      unawaited(deleteJob(jobId).catchError((Object _) {}));
      rethrow;
    }
  }

  /// Streams the picked document into the job folder, never holding it all in memory.
  Future<void> _copyInto(
    SelectedPdf pdf,
    File target,
    void Function(double progress)? onProgress,
  ) async {
    var copied = 0;
    final sink = target.openWrite();
    try {
      await for (final chunk in pdf.content.openRead()) {
        copied += chunk.length;
        sink.add(chunk);
        if (pdf.size > 0) onProgress?.call((copied / pdf.size).clamp(0.0, 1.0));
      }
      await sink.flush();
    } on FileSystemException {
      throw const EngineException(
        EngineFailure.failed,
        "The phone doesn't have enough free space to work on this PDF.",
        code: 'DISK_ERROR',
      );
    } catch (_) {
      throw const EngineException(
        EngineFailure.notFound,
        'This PDF is no longer readable. Go back and choose it again.',
        code: 'SOURCE_UNREADABLE',
      );
    } finally {
      await sink.close();
    }
    if (copied != pdf.size) {
      throw const EngineException(
        EngineFailure.notFound,
        'This PDF changed while it was being read. Choose it again.',
        code: 'SOURCE_CHANGED',
      );
    }
  }

  @override
  Future<Uint8List> preview(String jobId) async => _read(await _file(jobId, 'preview.png'));

  @override
  Future<JobInfo> removeWatermark(
    String jobId, {
    required RemovalMode mode,
    PdfNormalizedRect? area,
    bool allPages = true,
  }) async {
    if (mode == RemovalMode.area && area == null) {
      throw ArgumentError('Area mode needs an area');
    }
    final reply = await _call('remove', {
      'jobId': jobId,
      'mode': mode.wireName,
      'area': jsonEncode(mode == RemovalMode.area ? area!.toJson() : const <String, double>{}),
      'applyTo': allPages ? 'all_pages' : 'first_page',
    });
    return _job(_decode(reply));
  }

  @override
  Future<Uint8List> result(String jobId) async => _read(await _file(jobId, 'processed.pdf'));

  @override
  Future<Uint8List> resultPreview(String jobId) async => _read(await _file(jobId, 'result.png'));

  Future<Uint8List> _read(File file) async {
    try {
      return await file.readAsBytes();
    } on FileSystemException {
      throw const EngineException(
        EngineFailure.notFound,
        'This document is no longer available. Choose it again.',
        code: 'JOB_MISSING',
      );
    }
  }

  @override
  Future<void> deleteJob(String jobId) async {
    await _call('delete', {'jobId': jobId});
  }

  @override
  Future<SelfTestReport> selfTest() async {
    try {
      return SelfTestReport.fromJson(_decode(await _call('selfTest')));
    } on EngineException {
      rethrow;
    } catch (_) {
      throw const EngineException(EngineFailure.failed, 'The engine check returned an unexpected reply.');
    }
  }
}

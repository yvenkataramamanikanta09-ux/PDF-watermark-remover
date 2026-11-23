import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_watermark_remover/models/job.dart';
import 'package:pdf_watermark_remover/models/pdf_area_selection.dart';
import 'package:pdf_watermark_remover/models/selected_pdf.dart';
import 'package:pdf_watermark_remover/services/on_device_pdf_engine.dart';
import 'package:pdf_watermark_remover/services/pdf_engine.dart';

import 'fakes/engine_fakes.dart';
import 'fakes/pdf_selection_fakes.dart';

/// Plays the role of MainActivity + the Python adapter on the other side of the channel.
class _FakePlatform {
  _FakePlatform(this.root);

  final String root;
  final calls = <MethodCall>[];
  Object? Function(MethodCall call)? override;
  String jobId = '11111111-2222-4333-8444-555555555555';
  Map<String, dynamic> analyzeReply = jobJson(auto: true);

  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    final custom = override?.call(call);
    if (custom != null) return custom;
    switch (call.method) {
      case 'paths':
        return {'jobsRoot': root};
      case 'info':
        return jsonEncode({
          'python': '3.13.0',
          'pypdf': '7.1.0',
          'pypdfium2': '5.15.2',
          'pillow': '11.0.0',
          'max_file_bytes': 1000,
          'max_pages': 100,
        });
      case 'newJob':
        final dir = Directory('$root${Platform.pathSeparator}$jobId')..createSync(recursive: true);
        return jsonEncode({'job_id': jobId, 'dir': dir.path});
      case 'analyze':
        return jsonEncode(analyzeReply);
      case 'remove':
        return jsonEncode(jobJson(status: 'succeeded', mode: 'area', outcome: 'watermark_removed_successfully', removed: 2, pagesChanged: [1]));
      case 'delete':
        Directory('$root${Platform.pathSeparator}${call.arguments['jobId']}').deleteSync(recursive: true);
        return null;
      case 'selfTest':
        return jsonEncode({
          'ok': true,
          'steps': [
            {'name': 'remove watermark', 'ok': true, 'detail': ''},
          ],
          'seconds': 2.0,
        });
    }
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('pdfwm/engine');
  late Directory temp;
  late _FakePlatform platform;
  late OnDevicePdfEngine engine;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('engine_test_');
    platform = _FakePlatform(temp.path);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      platform.handle,
    );
    engine = OnDevicePdfEngine(channel: channel);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    temp.deleteSync(recursive: true);
  });

  SelectedPdf pdf({List<int>? bytes, int? size, String name = 'report.pdf'}) {
    final data = bytes ?? '%PDF-1.7\nhello'.codeUnits;
    return SelectedPdf(
      name: name,
      size: size ?? data.length,
      content: FakePdfDocument(name: name, bytes: data),
    );
  }

  test('status asks the engine once and caches the limits', () async {
    final status = await engine.status();
    expect((status.maxFileBytes, status.maxPages, status.pdfium), (1000, 100, '5.15.2'));
    await engine.status();
    expect(platform.calls.where((call) => call.method == 'info').length, 1);
  });

  test('analyze copies the PDF into the job folder, then runs the engine', () async {
    final progress = <double>[];
    final info = await engine.analyze(pdf(), onProgress: progress.add);
    final copy = File('${temp.path}/${platform.jobId}/original.pdf');
    expect(copy.readAsStringSync(), '%PDF-1.7\nhello');
    expect(progress.last, 1.0);
    expect(info.detection.autoAvailable, isTrue);
    expect(info.previewWidth, 791);
    final analyze = platform.calls.singleWhere((call) => call.method == 'analyze');
    expect(analyze.arguments, {'jobId': platform.jobId, 'filename': 'report.pdf'});
    // The order matters: newJob, then the copy, then analyze.
    expect(platform.calls.map((call) => call.method).toList(), ['info', 'newJob', 'analyze']);
  });

  test('a PDF over the phone limit is refused before anything is copied', () async {
    await expectLater(
      engine.analyze(pdf(size: 5000, bytes: List.filled(5000, 65))),
      throwsA(
        isA<EngineException>()
            .having((e) => e.failure, 'failure', EngineFailure.rejected)
            .having((e) => e.code, 'code', 'FILE_TOO_LARGE'),
      ),
    );
    expect(platform.calls.any((call) => call.method == 'newJob'), isFalse);
  });

  test('a rejected document becomes a rejected exception and the job folder is deleted', () async {
    platform.analyzeReply = {
      'error': {'kind': 'rejected', 'code': 'password_required', 'message': 'Password protected.'},
    };
    await expectLater(
      engine.analyze(pdf()),
      throwsA(
        isA<EngineException>()
            .having((e) => e.failure, 'failure', EngineFailure.rejected)
            .having((e) => e.message, 'message', 'Password protected.')
            .having((e) => e.code, 'code', 'PASSWORD_REQUIRED'),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(platform.calls.last.method, 'delete');
    expect(Directory('${temp.path}/${platform.jobId}').existsSync(), isFalse);
  });

  test('a source that is shorter than announced is reported as changed', () async {
    await expectLater(
      engine.analyze(pdf(bytes: '%PDF-1.7\n'.codeUnits, size: 500)),
      throwsA(isA<EngineException>().having((e) => e.code, 'code', 'SOURCE_CHANGED')),
    );
  });

  test('removeWatermark sends mode, area and page scope, and parses the reply', () async {
    final area = PdfNormalizedRect.tryCreate(const Rect.fromLTRB(0.1, 0.2, 0.6, 0.5))!;
    final info = await engine.removeWatermark(platform.jobId, mode: RemovalMode.area, area: area, allPages: false);
    final call = platform.calls.singleWhere((c) => c.method == 'remove');
    expect(call.arguments['mode'], 'area');
    expect(call.arguments['applyTo'], 'first_page');
    expect(jsonDecode(call.arguments['area'] as String), {'left': 0.1, 'top': 0.2, 'right': 0.6, 'bottom': 0.5});
    expect(info.status, JobStatus.succeeded);
    expect(info.result.removedCount, 2);
    await engine.removeWatermark(platform.jobId, mode: RemovalMode.auto);
    final auto = platform.calls.where((c) => c.method == 'remove').last;
    expect((auto.arguments['mode'], auto.arguments['applyTo']), ('auto', 'all_pages'));
    expect(jsonDecode(auto.arguments['area'] as String), isEmpty);
    expect(() => engine.removeWatermark(platform.jobId, mode: RemovalMode.area), throwsArgumentError);
  });

  test('previews and the result are read from the job folder', () async {
    await engine.analyze(pdf());
    File('${temp.path}/${platform.jobId}/preview.png').writeAsBytesSync(tinyPng);
    File('${temp.path}/${platform.jobId}/processed.pdf').writeAsStringSync('%PDF-1.7 clean');
    File('${temp.path}/${platform.jobId}/result.png').writeAsBytesSync(tinyPng);
    expect(await engine.preview(platform.jobId), tinyPng);
    expect(String.fromCharCodes(await engine.result(platform.jobId)), '%PDF-1.7 clean');
    expect(await engine.resultPreview(platform.jobId), tinyPng);
    await engine.deleteJob(platform.jobId);
    await expectLater(
      engine.result(platform.jobId),
      throwsA(isA<EngineException>().having((e) => e.failure, 'failure', EngineFailure.notFound)),
    );
  });

  test('job ids that are not UUIDs never touch the file system', () async {
    for (final bad in ['../secret', 'a/b', '']) {
      await expectLater(
        engine.preview(bad),
        throwsA(isA<EngineException>().having((e) => e.failure, 'failure', EngineFailure.notFound)),
      );
    }
  });

  test('platform failures mean the engine is unavailable', () async {
    platform.override = (call) =>
        call.method == 'info' ? throw PlatformException(code: 'engine_error', message: 'PyException: x') : null;
    await expectLater(
      engine.status(),
      throwsA(
        isA<EngineException>()
            .having((e) => e.failure, 'failure', EngineFailure.unavailable)
            .having((e) => e.code, 'code', 'ENGINE_ERROR'),
      ),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    await expectLater(
      OnDevicePdfEngine(channel: channel).status(),
      throwsA(isA<EngineException>().having((e) => e.code, 'code', 'ENGINE_MISSING')),
    );
  });

  test('a crash while processing one job is a retryable failure, not an unavailable engine', () async {
    platform.override = (call) =>
        call.method == 'remove' ? throw PlatformException(code: 'engine_error', message: 'PyException') : null;
    await expectLater(
      engine.removeWatermark(platform.jobId, mode: RemovalMode.auto),
      throwsA(
        isA<EngineException>()
            .having((e) => e.failure, 'failure', EngineFailure.failed)
            .having((e) => e.code, 'code', 'ENGINE_ERROR')
            .having((e) => e.message, 'message', contains('Try again')),
      ),
    );
  });

  test('garbage replies are handled', () async {
    platform.override = (call) => call.method == 'info' ? 'not json' : null;
    await expectLater(
      engine.status(),
      throwsA(isA<EngineException>().having((e) => e.failure, 'failure', EngineFailure.failed)),
    );
  });

  test('the self test report is parsed', () async {
    final report = await engine.selfTest();
    expect(report.ok, isTrue);
    expect(report.steps.single.name, 'remove watermark');
    expect(report.seconds, 2.0);
  });

  test('error codes are formatted for display', () {
    expect(PdfEngineCodes.format('password_required'), 'PASSWORD_REQUIRED');
    expect(PdfEngineCodes.format('a b-c'), 'A_B_C');
    expect(PdfEngineCodes.format(null), 'UNKNOWN_ERROR');
    expect(PdfEngineCodes.format(' ', fallback: 'X'), 'X');
  });
}

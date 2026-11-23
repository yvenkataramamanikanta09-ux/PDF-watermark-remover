/// The description of one document the engine is working on (the engine adapter's JSON).
library;

enum JobStatus {
  ready,
  processing,
  succeeded,
  nothingRemoved,
  failed,
  unknown;

  static JobStatus parse(String value) => switch (value) {
    'ready' => ready,
    'processing' => processing,
    'succeeded' => succeeded,
    'nothing_removed' => nothingRemoved,
    'failed' => failed,
    _ => unknown,
  };
}

enum RemovalMode {
  auto('auto'),
  area('area');

  const RemovalMode(this.wireName);
  final String wireName;
}

final class Detection {
  const Detection({
    required this.outcome,
    required this.code,
    required this.supportedCount,
    required this.unsupportedCount,
    required this.artifactCount,
    required this.autoAvailable,
  });

  factory Detection.fromJson(Map<String, dynamic> json) => Detection(
    outcome: json['outcome'] as String,
    code: json['code'] as String,
    supportedCount: json['supported_count'] as int,
    unsupportedCount: json['unsupported_count'] as int,
    artifactCount: json['artifact_count'] as int,
    autoAvailable: json['auto_available'] as bool,
  );

  final String outcome;
  final String code;
  final int supportedCount;
  final int unsupportedCount;
  final int artifactCount;
  final bool autoAvailable;

  int get autoRemovableCount => supportedCount + artifactCount;
}

final class JobResult {
  const JobResult({
    required this.mode,
    required this.outcome,
    required this.code,
    required this.message,
    required this.removedCount,
    required this.removedByKind,
    required this.pagesChanged,
  });

  factory JobResult.fromJson(Map<String, dynamic> json) => JobResult(
    mode: json['mode'] as String?,
    outcome: json['outcome'] as String?,
    code: json['code'] as String?,
    message: json['message'] as String?,
    removedCount: json['removed_count'] as int,
    removedByKind: (json['removed_by_kind'] as Map<String, dynamic>).map(
      (key, value) => MapEntry(key, value as int),
    ),
    pagesChanged: (json['pages_changed'] as List<dynamic>).cast<int>(),
  );

  final String? mode;
  final String? outcome;
  final String? code;
  final String? message;
  final int removedCount;
  final Map<String, int> removedByKind;
  final List<int> pagesChanged;
}

final class JobInfo {
  const JobInfo({
    required this.id,
    required this.filename,
    required this.size,
    required this.sha256,
    required this.pageCount,
    required this.status,
    required this.detection,
    required this.previewWidth,
    required this.previewHeight,
    required this.result,
  });

  factory JobInfo.fromJson(Map<String, dynamic> json) {
    final preview = json['preview'] as Map<String, dynamic>;
    if (preview['coordinate_space'] != 'renderedPageTopLeft') {
      throw const FormatException('Unexpected preview coordinate space');
    }
    return JobInfo(
      id: json['job_id'] as String,
      filename: json['filename'] as String,
      size: json['size'] as int,
      sha256: json['sha256'] as String,
      pageCount: json['page_count'] as int,
      status: JobStatus.parse(json['status'] as String),
      detection: Detection.fromJson(json['detection'] as Map<String, dynamic>),
      previewWidth: preview['width'] as int,
      previewHeight: preview['height'] as int,
      result: JobResult.fromJson(json['result'] as Map<String, dynamic>),
    );
  }

  final String id;
  final String filename;
  final int size;
  final String sha256;
  final int pageCount;
  final JobStatus status;
  final Detection detection;
  final int previewWidth;
  final int previewHeight;
  final JobResult result;
}

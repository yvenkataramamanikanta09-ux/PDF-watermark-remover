// Configuration constants for the PDF Watermark Remover app

/// Base URL for the FastAPI backend.
///
/// Android emulator accesses the host machine via `10.0.2.2`. For running the
/// app on a physical device or during development on the host, override this
/// value with the `BACKEND_BASE_URL` environment variable (e.g. using `flutter
/// run --dart-define=BACKEND_BASE_URL=https://my.server.com`).
const String backendBaseUrl = String.fromEnvironment(
  'BACKEND_BASE_URL',
  defaultValue: 'http://10.0.2.2:8000',
);

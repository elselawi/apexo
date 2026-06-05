import 'audio_platform_stub.dart'
    if (dart.library.html) 'audio_platform_web.dart';

abstract class AudioPlatform {
  /// Generates a temp file path for recording.
  /// On native: a real file path in the system temp directory.
  /// On web: a placeholder (the browser's MediaRecorder ignores it).
  static String getTempAudioPath() => AudioPlatformImpl.getTempAudioPath();

  /// Reads all bytes from the recorded output.
  /// On native: reads from a file path.
  /// On web: fetches from a blob URL.
  static Future<List<int>> readFileBytes(String path) =>
      AudioPlatformImpl.readFileBytes(path);
}

import 'audio_platform_stub.dart'
    if (dart.library.html) 'audio_platform_web.dart';

abstract class AudioPlatform {
  /// Temp path for a recording: a real file on native, a placeholder on web (the
  /// browser's MediaRecorder ignores it).
  static String getTempAudioPath() => AudioPlatformImpl.getTempAudioPath();

  /// Bytes of the recording: read from disk on native, fetched from the blob URL
  /// on web.
  static Future<List<int>> readFileBytes(String path) =>
      AudioPlatformImpl.readFileBytes(path);
}

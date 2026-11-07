import 'package:http/http.dart' as http;

class AudioPlatformImpl {
  /// On web the `path` given to `AudioRecorder.start()` is ignored; MediaRecorder
  /// keeps its own buffer.
  static String getTempAudioPath() => 'audio_recording.m4a';

  /// Fetches the recorded blob from its object URL.
  static Future<List<int>> readFileBytes(String path) async =>
      (await http.get(Uri.parse(path))).bodyBytes;
}

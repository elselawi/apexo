import 'dart:io';

class AudioPlatformImpl {
  static String getTempAudioPath() =>
      '${Directory.systemTemp.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';

  static Future<List<int>> readFileBytes(String path) async =>
      await File(path).readAsBytes();
}

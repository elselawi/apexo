import 'save_file_stub.dart' if (dart.library.html) 'save_file_web.dart';

abstract class SaveFilePlatform {
  static void saveFileWeb(List<int> bytes, String fileName) {
    return SaveFileImpl.saveFileWeb(bytes, fileName);
  }
}

// TODO: test saving file on the 3 supported platforms

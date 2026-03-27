// sound_service.dart
import 'dart:io';
import 'package:flutter/foundation.dart';

import 'sound_stub.dart' if (dart.library.io) 'sound_windows.dart';

void triggerSound() {
  if (kIsWeb == false && Platform.isWindows) {
    playDing();
  }
}

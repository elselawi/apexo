import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

// --- FFI Function Signatures ---
typedef PlaySoundNative = Int32 Function(
    Pointer<Utf16> pszSound, Handle hmod, Uint32 fdwSound);
typedef PlaySoundDart = int Function(
    Pointer<Utf16> pszSound, Object? hmod, int fdwSound);

// Global cache to prevent re-writing the file every time
String? _cachedDingPath;

/// Extracts the asset to a temp file if not already done, then plays it.
Future<void> playDing() async {
  try {
    // 1. Prepare the file (only happens once per app session)
    if (_cachedDingPath == null) {
      final data = await rootBundle.load('assets/ding.wav');
      final bytes = data.buffer.asUint8List();

      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}\\app_ding.wav');

      await tempFile.writeAsBytes(bytes);
      _cachedDingPath = tempFile.path;
    }

    // 2. Open the Windows Multimedia library
    final DynamicLibrary winmm = DynamicLibrary.open('winmm.dll');

    // 3. Look up the PlaySoundW function (Unicode version)
    final playSound =
        winmm.lookupFunction<PlaySoundNative, PlaySoundDart>('PlaySoundW');

    // 4. Convert path to Windows-friendly format
    final pathPointer = _cachedDingPath!.toNativeUtf16();

    // Flags: 0x0002 (SND_FILENAME) | 0x0001 (SND_ASYNC)
    const int flags = 0x0002 | 0x0001;

    // 5. Play!
    playSound(pathPointer, null, flags);

    // 6. Free the string memory (The sound continues playing ASYNC)
    malloc.free(pathPointer);
  } catch (e) {
    // ignore: avoid_print
    print("Windows Audio Error: $e");
  }
}

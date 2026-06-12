---
description: Cross-platform patterns for Apexo — conditional imports for web vs native, platform checks, JS bridge, image handling across platforms, file system access, and audio recording platform abstractions.
applyTo: "lib/utils/**"
---

# Apexo Cross-Platform Patterns

## Platform Targets

Apexo runs on **Android, iOS, Web, macOS, and Windows** from a single codebase. Platform differences are handled through three mechanisms:

| Mechanism | When to Use | Example |
|-----------|-------------|---------|
| **Conditional imports** | Entire implementation differs per platform | `import 'stub.dart' if (dart.library.js_interop) 'web.dart'` |
| **`kIsWeb` checks** | Minor branching in shared code | `if (kIsWeb) { ... } else { ... }` |
| **`Platform.isAndroid`/`isIOS`/etc.** | OS-specific branching (native only) | `if (Platform.isAndroid || Platform.isIOS) { ... }` |

## Conditional Import Pattern

Apexo uses Dart's **conditional imports** to swap implementations at compile time. The pattern always uses three files:

```
lib/utils/<feature>/
├── <feature>_service.dart   ← Public API (abstract class or facade)
├── <feature>_stub.dart      ← Default/native implementation
└── <feature>_web.dart       ← Web-specific implementation
```

### Example: Audio Platform

**`audio_platform.dart`** (facade):
```dart
import 'audio_platform_stub.dart'
    if (dart.library.html) 'audio_platform_web.dart';

abstract class AudioPlatform {
  static String getTempAudioPath() => AudioPlatformImpl.getTempAudioPath();
  static Future<List<int>> readFileBytes(String path) =>
      AudioPlatformImpl.readFileBytes(path);
}
```

**`audio_platform_stub.dart`** (native — Android, iOS, macOS, Windows):
```dart
class AudioPlatformImpl {
  static String getTempAudioPath() =>
      '${Directory.systemTemp.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
  static Future<List<int>> readFileBytes(String path) async =>
      await File(path).readAsBytes();
}
```

**`audio_platform_web.dart`** (web):
```dart
class AudioPlatformImpl {
  static String getTempAudioPath() => 'audio_recording.m4a';
  static Future<List<int>> readFileBytes(String path) async =>
      (await http.get(Uri.parse(path))).bodyBytes;
}
```

### Available Conditional Import Facades

| Facade | Files | Purpose |
|--------|-------|---------|
| `lib/utils/js/js_bridge.dart` | `js_stub.dart` / `js_web.dart` | Set `window` globals, interact with `sessionStorage` |
| `lib/utils/audio_platform/audio_platform.dart` | `audio_platform_stub.dart` / `audio_platform_web.dart` | Recording paths and file reading |
| `lib/utils/href/href_service.dart` | `href_stub.dart` / `href_web.dart` | Get current URL (for patient-side deep links) |

### Key Conditional Import Libraries

| Dart library constant | Means the platform is... |
|----------------------|--------------------------|
| `dart.library.js_interop` | Web (has JS interop available) |
| `dart.library.html` | Web (has HTML DOM available) |
| `dart.library.io` | Native (has file I/O) |
| `dart.library.js_util` | Web |

## Image Handling (`lib/utils/imgs.dart`)

### Upload Flow

```
handleNewImage(rowID, sourcePath, sourceFile, targetStore)
  ├── Determine extension (.jpg, .png, etc.)
  ├── Hash the path to generate a unique filename
  ├── Native: Save to local filesDir → generate 100px thumbnail → upload to PocketBase
  └── Web: Upload directly to PocketBase (no local filesystem)
```

### Retrieval Flow

```
getImage(rowID, name, thumb?)
  ├── Check in-memory cache (30-item LRU)
  ├── Web: Fetch from PocketBase file URL → NetworkImage
  └── Native: Check local filesDir → if missing, download from PocketBase → FileImage
```

### Key Differences: Native vs Web

| Operation | Native | Web |
|-----------|--------|-----|
| **File storage** | `filesDir()` from `safe_dir.dart` (app documents directory) | No local filesystem — PocketBase is the source of truth |
| **Thumbnails** | Generated locally with `image` package | Requested from PocketBase with `?thumb=100x100` query param |
| **Upload source** | File path on disk | Blob URL or proxied through `https://imgs.apexo.app/` |
| **Cache** | Both memory + disk | Memory only |

### Image Upload via Store

`Store.uploadImg()` in `lib/core/store.dart`:
- **Online**: Uploads as `MultipartFile` to PocketBase's file field (`imgs+`)
- **Offline**: Defers upload as a Hive entry with format `FILE||{rowID}||path:{0/1}`
- **Web special case**: Blob URLs are fetched via `http.get()` and sent as bytes; external URLs are proxied through `https://imgs.apexo.app/`

## JS Bridge (`lib/utils/js/js_bridge.dart`)

Used to communicate with JavaScript on the web platform:

```dart
JSBridge.setGlobalVariable("clinicKey", relayKey);         // Sets window.clinicKey
JSBridge.removeItemFromSessionStorage("canvaskit_reload_count");  // Clears sessionStorage
```

On native platforms, these are **no-ops** (the stub prints a log and returns).

Currently used for:
- **Notifications** (`fcm/fcm.js`): Passing clinic key, server URL, account ID, language to the service worker
- **Canvaskit**: Clearing Flutter web's Canvaskit reload counter

## Platform Checks in Shared Code

### Common Patterns

```dart
// Check if running on web vs native
if (kIsWeb) {
  // web-only path
} else {
  // native path
}

// Check specific native platforms (only after confirming !kIsWeb)
if (Platform.isAndroid || Platform.isIOS) {
  // mobile-specific (Firebase, notifications)
} else if (Platform.isWindows) {
  // Windows-specific (ding sound)
}
```

### Where Platform Checks Appear

| Area | Check | Reason |
|------|-------|--------|
| `main.dart` | `kIsWeb == false` → init notifications | Web uses service worker, not Flutter FCM plugin |
| `main.dart` | `kIsWeb` → clear Canvaskit | Web-specific Flutter rendering workaround |
| `core_notifications_initializer.dart` | `Platform.isAndroid \|\| Platform.isIOS` | Only mobile has Firebase+FCM native plugins |
| `static_notifications.dart` | `kIsWeb \|\| Platform.isWindows == false` | Sound + toast only on Windows desktop |
| `imgs.dart` | `!kIsWeb` → local file operations | Web has no filesystem access |
| `app.dart` | `!kIsWeb && Platform.isAndroid` → bottom padding | Android system nav bar insets |

## File System Access (`lib/utils/safe_dir.dart`)

All file I/O goes through `filesDir()` which returns the appropriate app documents directory per platform. Never use hardcoded paths.

```dart
import 'package:apexo/utils/safe_dir.dart';

final dir = await filesDir();  // Cross-platform app documents directory
```

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Using `dart:io` directly without platform guard | Wrap in `if (!kIsWeb)` or use conditional imports |
| Assuming `Platform.isX` works on web | Always check `kIsWeb` first — `Platform` from `dart:io` is unavailable on web |
| Creating a conditional import but forgetting the stub | Every facade needs a stub for compilation on all platforms |
| Using `File(path)` on web | Use conditional imports or `kIsWeb` guard — web has no `dart:io` |
| Not testing image upload on both web and native | The flow is completely different — test both paths |
| Hardcoding file paths | Always use `filesDir()` from `safe_dir.dart` |

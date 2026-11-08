---
description: Apexo cross-platform patterns — conditional imports, platform checks, image storage/retrieval across web and native, the JS bridge, and file system access.
applyTo: "lib/utils/**"
---

# Apexo Cross-Platform

One codebase, five targets: Android, iOS, Web, macOS, Windows.

| Mechanism | When |
|---|---|
| Conditional import | The whole implementation differs by platform |
| `kIsWeb` | Minor branching in shared code |
| `Platform.isAndroid`/`isIOS`/… | OS branching — native only, never on web |

## Conditional imports

The facade declares the API and picks the implementation at compile time; the stub is the fallback:

```dart
import 'audio_platform_stub.dart'
    if (dart.library.html) 'audio_platform_web.dart';
```

The condition names the platform that is *not* the stub, so folder conventions vary — follow the existing file's choice:

| Facade | Files | Condition | Purpose |
|---|---|---|---|
| `js/js_bridge.dart` | `js_stub` / `js_web` | `js_interop` | `window` globals, `sessionStorage` |
| `audio_platform/audio_platform.dart` | `_stub` (native) / `_web` | `html` | recording paths, reading bytes |
| `href/href_service.dart` | `_stub` / `_web` | `js_util` | current URL for patient deep links |
| `ws_platform/ws_platform.dart` | `_stub` / `_web` | `html` | `connectWebSocket` |
| `windows_ding/sound_service.dart` | `_stub` / `_windows` | `io` | Windows toast sound |
| `services/dicom/dicom_io_service.dart` | `_stub` / `_native` | `io` | DICOM file I/O |

`dart.library.io` = native, `dart.library.html` / `js_interop` / `js_util` = web.

## Platform checks

```dart
if (kIsWeb) { /* web */ } else { /* native */ }
if (Platform.isAndroid || Platform.isIOS) { /* Firebase / FCM */ }
```

Check `kIsWeb` **first**: `dart:io` is unavailable on web, so a bare `Platform.isX` does not compile there. When several files need the same distinction, expose one named value instead of repeating checks — e.g. `PushPlatform.current` (`wns`/`ios`/`macos`/`android`/`web`/`null`) and `DicomController.isSupported` (`!kIsWeb && Platform.isWindows`).

## Files

All file I/O uses `filesDir()` (`lib/utils/safe_dir.dart`) — never a hardcoded path. Hive uses the same directory.

Images (`lib/utils/imgs.dart`):

- `handleNewImage(rowID:, sourcePath:, sourceFile:, targetStore:)`: hash the path to a name → native: save under `filesDir()`, generate a 100px thumb, upload; web: upload straight to PocketBase.
- `getImage(rowID, name, [thumb, resolve, thumbSize])`: memory/disk cache first; native serves the local file when present, else downloads; web always fetches from PocketBase. A raw `.dcm` name resolves to its small PNG preview unless the viewer asks for the file.
- A grid asks for the 100px thumb (`kThumbSize`), a gallery's large preview for 640px (`kPreviewSize`); only the photo viewer asks for the original.
- Local thumbs are `<name>.thumb<ext>` (100px) and `<name>.thumb<size><ext>` — a preview never overwrites a grid thumb. Web asks PocketBase for `?thumb=WxH`.
- `Store.uploadImg`/`deleteImg` own the transfer: online as a `MultipartFile` into `imgs+`; offline deferred as Hive `FILE||rowId||…` keys; web blob URLs are read as bytes and external URLs proxied through `https://imgs.apexo.app/?url=…`.
- `resolveFileLink(rowId, name)` returns a remote URL when a resolver is bound, null otherwise (hide the file; not an error).

## JS bridge

`JSBridge.setGlobalVariable(key, value)` and `removeItemFromSessionStorage(key)` are no-ops on native. Used for the FCM service worker (`web/fcm/fcm.js`) and to clear Flutter web's Canvaskit reload counter.

## Common mistakes

| Mistake | Fix |
|---|---|
| `dart:io` / `File` without a guard | Wrap in `if (!kIsWeb)` or use a conditional import |
| `Platform.isX` on web | Check `kIsWeb` first |
| Adding a facade without its stub | The build breaks on the other platforms |
| Hardcoded paths | `filesDir()` |
| Assuming image upload is one flow | Native and web differ — test both |

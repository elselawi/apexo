import 'dart:async';
import 'dart:io';
import 'package:apexo/core/reactive/observable.dart';
import 'package:apexo/core/store.dart';
import 'package:apexo/services/dicom/dicom_io_service.dart';
import 'package:apexo/services/dicom/dicom_parser.dart';
import 'package:apexo/services/dicom/dicom_renderer.dart';
import 'package:apexo/services/dicom/dicom_skipped.dart';
import 'package:apexo/utils/constants.dart';
import 'package:apexo/utils/hash.dart';
import 'package:apexo/utils/logger.dart';
import 'package:apexo/utils/que.dart';
import 'package:apexo/utils/safe_dir.dart';
import 'package:apexo/utils/save_file_multiplatform.dart';
import 'package:apexo/utils/strip_id_from_file.dart';
import 'package:apexo/services/file_links.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/adapters.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

bool _directoryExists(String path) => Directory(path).existsSync();
bool _fileExists(String path) => File(path).existsSync();
int _fileModified(String path) =>
    File(path).lastModifiedSync().millisecondsSinceEpoch;

Future<void> createDirectory(String path) async {
  final Directory dir = Directory(path);
  if (await compute(_directoryExists, path)) {
    return;
  } else {
    await dir.create(recursive: true);
  }
}

Future<bool> checkIfFileExists(String name) async {
  final File file = File(path.join(await filesDir(), name));
  return await compute(_fileExists, file.path);
}

Future<File> getOrCreateFile(String name) async {
  await createDirectory(await filesDir());
  return File(path.join(await filesDir(), name));
}

/// Thumb width. Must stay 100: the legacy local thumb names (see [_thumbName])
/// and the PocketBase `?thumb=100x100` requests depend on it.
const int kThumbSize = 100;

/// Large-preview width for the one picture a gallery shows bigger; fetching the
/// original would decode tens of MB for a box a few hundred pixels wide.
const int kPreviewSize = 640;

/// The local file a thumb of [name] at [size] is kept in. The 100px thumb keeps
/// its old bare name, already cached on devices; larger sizes embed the size.
String _thumbName(String name, [int size = kThumbSize]) {
  final stem = path.withoutExtension(name);
  final extension = path.extension(name);
  return size == kThumbSize
      ? "$stem.thumb$extension"
      : "$stem.thumb$size$extension";
}

String _thumbUrl(String url, [int size = kThumbSize]) {
  return "$url?thumb=${size}x$size";
}

// copies a given image to local folder and upload it to the server
Future<String> handleNewImage({
  required String rowID,
  required String sourcePath,
  XFile? sourceFile,
  required Store targetStore,
}) async {
  final bool fromLink = sourcePath.startsWith("http");
  String extension;

  // this if for web importing on web
  sourceFile ??= XFile(sourcePath);

  // getting extension
  if (fromLink) {
    extension = await getImageExtensionFromURL(sourcePath) ?? ".jpg";
  } else if (sourcePath.startsWith("blob:")) {
    if (sourceFile.mimeType != null &&
        sourceFile.mimeType!.split("/").length > 1) {
      extension = ".${sourceFile.mimeType!.split("/").last}";
    } else {
      extension = ".${sourceFile.name.split(".").last}";
    }
  } else {
    extension = path.extension(sourcePath);
  }

  final raw = path.basenameWithoutExtension(sourcePath);
  final safe = raw.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_').toLowerCase();

  String hashInput;
  if (fromLink || sourcePath.startsWith("blob:") || kIsWeb) {
    hashInput = sourcePath; // fallback: path hash
  } else {
    // Async stat: on a network share a sync stat would freeze the UI isolate.
    final mtime = await compute(_fileModified, sourcePath);
    hashInput = '${path.basename(sourcePath)}_$mtime'; // name + mtime
  }
  final imgName = '${safe}_${simpleHash(hashInput)}$extension';

  File? savedFile;
  if (!kIsWeb) {
    // saving the image to desk (saving to a specific folder)
    if (fromLink) {
      savedFile = await saveImageFromUrl(sourcePath, imgName);
    } else {
      savedFile = await savePickedImage(File(sourcePath), imgName);
    }

    // resizing it to a thumb
    if (isAnImageName(imgName)) {
      try {
        final cmd = img.Command()
          ..decodeImageFile(savedFile.path)
          ..copyResize(width: 100)
          ..writeToFile(_thumbName(savedFile.path));
        await cmd.executeThread();
      } catch (_) {
        // Non-decodable file — skip local thumbnail (PB will handle server-side)
      }
    }
  }

  // uploading
  final store = targetStore;
  final finalFileName = await store.uploadImg(
    rowID: rowID,
    filename: imgName,
    path: savedFile?.path,
    file: sourceFile,
  );

  // Rename to the PB-assigned name so the first view reuses the local file and
  // its thumb instead of re-downloading.
  if (!kIsWeb && savedFile != null && finalFileName != imgName) {
    try {
      final newPath = path.join(path.dirname(savedFile.path), finalFileName);
      await savedFile.rename(newPath);
      final oldThumb = File(_thumbName(savedFile.path));
      if (await compute(_fileExists, oldThumb.path)) {
        await oldThumb.rename(_thumbName(newPath));
      }
    } catch (_) {}
  }

  // returns the final file name
  return finalFileName;
}

/// Bumped when a DCM PNG preview finishes; galleries listen to rebuild tiles.
final ObservableState<int> dicomPngReady = ObservableState<int>(0);

/// Serialised so a bulk DCM import doesn't fire dozens of concurrent Rust
/// parse+render calls.
final _dcmPngQue =
    TaskQueue(delayBetweenTasks: const Duration(milliseconds: 50));

/// Saves and uploads a `.dcm` immediately, then queues PNG preview generation.
/// Returns the PB filename without waiting for the PNG.
Future<String> handleNewDcm({
  required String rowID,
  required String sourcePath,
  required Store targetStore,
}) async {
  // Web has no filesystem — DCM import is Windows-only.
  if (kIsWeb) return '';

  // Read source bytes.
  final bytes = await DicomIO.readBytes(sourcePath);
  if (bytes == null || bytes.isEmpty) {
    await dicomSkippedLog.add(
      path: sourcePath,
      reason: 'handleNewDcm: failed to read bytes',
    );
    return '';
  }

  // Async stat: watch folders can sit on a network share, where a sync stat
  // blocks the UI isolate.
  final mtime = await compute(_fileModified, sourcePath);
  final hashInput = '${path.basename(sourcePath)}_$mtime';
  final dcmName = 'dcm_${simpleHash(hashInput)}.dcm';

  // Save the .dcm to filesDir().
  final savedFile = await getOrCreateFile(dcmName);
  if (!await compute(_fileExists, savedFile.path)) {
    await savedFile.writeAsBytes(bytes);
  }

  // Upload the .dcm immediately — do not block on PNG generation.
  final store = targetStore;
  final finalDcmName = await store.uploadImg(
    rowID: rowID,
    filename: dcmName,
    path: savedFile.path,
  );

  // Rename the local file if PB assigned a different name.
  if (finalDcmName != dcmName) {
    try {
      final newPath = path.join(path.dirname(savedFile.path), finalDcmName);
      await savedFile.rename(newPath);
    } catch (_) {}
  }

  // Queue PNG preview generation in the background.
  unawaited(_dcmPngQue.add(() => _generateDcmPreview(
        rowID: rowID,
        dcmName: finalDcmName,
        bytes: bytes,
        sourcePath: sourcePath,
        store: store,
      )));

  return finalDcmName;
}

Future<void> _generateDcmPreview({
  required String rowID,
  required String dcmName,
  required Uint8List bytes,
  required String sourcePath,
  required Store store,
}) async {
  try {
    // Full parse (metadata + pixels) — needed for rendering.
    final result = await dicomParser.parse(bytes, sourcePath: sourcePath);
    if (result == null) {
      await dicomSkippedLog.add(
        path: sourcePath,
        reason: 'png_generation_failed: full parse returned null',
      );
      return;
    }

    // Render PNG preview bytes.
    final pngBytes = await dicomRenderer.renderPreviewPng(result);
    if (pngBytes == null || pngBytes.isEmpty) {
      await dicomSkippedLog.add(
        path: sourcePath,
        reason: 'png_generation_failed: renderPreviewPng returned null',
      );
      return;
    }

    // Derive PNG + thumb filenames from the DCM filename.
    final pngName = '$dcmName.png';
    final thumbName = _thumbName(pngName);

    // Save PNG locally.
    final pngFile = await getOrCreateFile(pngName);
    await pngFile.writeAsBytes(pngBytes);

    // Generate a 100px thumbnail from the PNG.
    try {
      final cmd = img.Command()
        ..decodeImageFile(pngFile.path)
        ..copyResize(width: 100)
        ..writeToFile(path.join(await filesDir(), thumbName));
      await cmd.executeThread();
    } catch (_) {
      // Thumbnail is best-effort — PB handles server-side resizing too.
    }

    // Upload PNG to PB.
    await store.uploadImg(
      rowID: rowID,
      filename: pngName,
      path: pngFile.path,
    );

    // Notify the gallery to rebuild placeholder cells.
    dicomPngReady(dicomPngReady() + 1);
  } catch (e, s) {
    logger('_generateDcmPreview error: $e', s, 2);
    try {
      await dicomSkippedLog.add(
        path: sourcePath,
        reason: 'png_generation_failed: $e',
      );
    } catch (_) {
      // best-effort logging
    }
  }
}

/// Resolved providers by [_cacheKey]: saves the disk lookup and, when the file is
/// not on this device yet, the download. Pixels live in Flutter's own image cache.
final imgMemoryCache = <String, ImageProvider>{};

/// [imgMemoryCache] size limit; an eviction costs a disk lookup, not a download.
const int _imgCacheLimit = 120;

final _imageHttpReqQue =
    TaskQueue(delayBetweenTasks: const Duration(milliseconds: 100));

String _stripLastHashFromFileName(String name) {
  return name.replaceFirstMapped(
    RegExp(r'^(.+)_[A-Za-z0-9]{6,}(\.[^.]+)$'),
    (m) => '${m[1]}${m[2]}',
  );
}

/// The size a cached entry stands for when the file itself was asked for.
const int _kOriginalSize = 0;

/// What one file's entries are told apart by. The 100px thumb keeps the bare file
/// name so existing device caches still hit; previews and originals get a prefix.
String _cacheKey(String name, int size) {
  if (size == kThumbSize) return name;
  return size == _kOriginalSize ? 'original:$name' : '$size:$name';
}

Future<ImageProvider?> getImage(
  String rowID,
  String name, [
  bool thumb = true,
  FileLinkResolver? resolve,
  int thumbSize = kThumbSize,
]) async {
  if (isUrl(name)) {
    // A file URL's last segment is the stored file name; a URL naming no file is
    // left whole and handled below (the avatar link).
    final segments = Uri.parse(name).pathSegments;
    if (segments.isNotEmpty && segments.last.isNotEmpty) {
      name = segments.last;
    }
  }

  // Never auto-fetch a raw .dcm (5–20 MB): return its small PNG preview instead.
  // The raw file is fetched only on demand by the viewer.
  if (isADcmName(name)) {
    return getImage(rowID, '$name.png', thumb, resolve, thumbSize);
  }

  if (name == "https://person.alisaleem.workers.dev/") {
    final link = "$name?no-cache=$rowID";
    final cached = imgMemoryCache[link];
    if (cached != null) return cached;
    final img = Image.network(link).image;
    return imgMemoryCache[link] = img;
  }

  final size = thumb ? thumbSize : _kOriginalSize;
  final key = _cacheKey(name, size);
  final cached = imgMemoryCache.remove(key);
  if (cached != null) {
    // Re-inserted so it is the newest entry and the oldest are evicted first.
    imgMemoryCache[key] = cached;
    return cached;
  }

  final img = await _getImage(rowID, name, thumb, resolve, thumbSize);
  // A miss is not cached: an X-ray whose PNG preview has not been generated yet
  // becomes available later.
  if (img != null) {
    imgMemoryCache[key] = img;
    while (imgMemoryCache.length > _imgCacheLimit) {
      imgMemoryCache.remove(imgMemoryCache.keys.first);
    }
  }
  return img;
}

/// In-flight thumb jobs by produced file: concurrent tiles ask for one picture at
/// once and it need only be drawn once.
final _thumbJobs = <String, Future<File?>>{};

/// Local thumb drawing, one picture at a time: each draw decodes a whole photo
/// (tens of MB), so a gallery must not decode a dozen at once.
final _thumbDrawQue = TaskQueue(delayBetweenTasks: Duration.zero);

/// Draws the thumb of [name] at [size] from the local original, avoiding a server
/// round trip and working offline. Null if no original or it can't be drawn.
Future<File?> _thumbFromLocal(String name, int size) {
  final thumbName = _thumbName(name, size);
  final inFlight = _thumbJobs[thumbName];
  if (inFlight != null) return inFlight;
  final job = _thumbDrawQue.add(() => _drawThumb(name, size)).whenComplete(() {
    // Dropped by key: the stored future is this very job, so returning it would
    // make it wait on itself.
    _thumbJobs.removeWhere((other, _) => other == thumbName);
  });
  _thumbJobs[thumbName] = job;
  return job;
}

Future<File?> _drawThumb(String name, int size) async {
  if (!isAnImageName(name) || !await checkIfFileExists(name)) return null;
  try {
    final original = await getOrCreateFile(name);
    final thumb = await getOrCreateFile(_thumbName(name, size));
    final cmd = img.Command()
      ..decodeImageFile(original.path)
      ..copyResize(width: size)
      ..writeToFile(thumb.path);
    await cmd.executeThread();
    return await compute(_fileExists, thumb.path) ? thumb : null;
  } catch (_) {
    // Not drawable here (SVG, unreadable): fall back to the server's thumb.
    return null;
  }
}

Future<ImageProvider?> _getImage(
  String rowID,
  String name,
  bool thumb,
  FileLinkResolver? resolve,
  int thumbSize,
) async {
  // Web platform doesn't support local files
  if (kIsWeb) {
    final imgUrl = await (resolve ?? resolveFileLink)(rowID, name);
    return imgUrl == null
        ? null
        : NetworkImage(thumb ? _thumbUrl(imgUrl, thumbSize) : imgUrl);
  }

  // if the file exists locally, return it
  final localName = thumb ? _thumbName(name, thumbSize) : name;
  if (await checkIfFileExists(localName)) {
    return Image.file(await getOrCreateFile(localName)).image;
  }

  // Thumb missing but the original may be local: draw it instead of re-downloading.
  if (thumb) {
    final drawn = await _thumbFromLocal(name, thumbSize);
    if (drawn != null) return Image.file(drawn).image;
  }

  // if the file doesn't exist locally, download it from the server
  final imgUrl = await _imageHttpReqQue
      .add(() => (resolve ?? resolveFileLink)(rowID, name));
  if (imgUrl == null) return null;
  final download = await _imageHttpReqQue.add(() => saveImageFromUrl(
      thumb ? _thumbUrl(imgUrl, thumbSize) : imgUrl, localName));
  return Image.file(download).image;
}

Future<File> savePickedImage(File image, String newName) async {
  final File newImage = await getOrCreateFile(newName);
  if (await compute(_fileExists, newImage.path)) return newImage;
  return await image.copy(newImage.path);
}

Future<File> saveImageFromUrl(String imageUrl, [String? givenName]) async {
  final imageName = givenName ?? stripIDFromFileName(imageUrl.split('/').last);

  // in case of web, we store the image link in the hive store
  if (kIsWeb) {
    await Hive.openBox<String>(webImagesStore);
    await Hive.box<String>(webImagesStore).put(imageName, imageUrl);
    return File(imageUrl);
  }

  final File newImage = await getOrCreateFile(imageName);
  if (await compute(_fileExists, newImage.path)) return newImage;

  final response = await http.get(Uri.parse(imageUrl));
  if (response.statusCode == 200) {
    return await newImage.writeAsBytes(response.bodyBytes);
  } else {
    throw Exception('Failed to download image');
  }
}

Future<String?> getImageExtensionFromURL(String imageUrl) async {
  try {
    // Make HEAD request to get headers without downloading the whole file
    final response = await http.head(Uri.parse(imageUrl));

    if (response.statusCode == 200) {
      final contentType = response.headers['content-type'];
      if (contentType != null) {
        // Map MIME types to extensions
        switch (contentType.toLowerCase()) {
          case 'image/jpeg':
          case 'image/jpg':
            return '.jpg';
          case 'image/png':
            return '.png';
          case 'image/gif':
            return '.gif';
          case 'image/webp':
            return '.webp';
          case 'image/bmp':
            return '.bmp';
          case 'image/heic':
            return '.heic';
          default:
            return '.${contentType.split('/').last}';
        }
      }
    }
    return null;
  } catch (e) {
    return null;
  }
}

bool isAnImageName(String name) {
  const imageExtensions = {
    'jpg',
    'jpeg',
    'png',
    'gif',
    'bmp',
    'webp',
    'svg',
    'tiff',
    'tif',
    'ico',
    'heic',
    'heif',
    'avif',
    'jfif',
  };

  final extension = name.split('.').last.toLowerCase();
  return imageExtensions.contains(extension);
}

/// True for `.dcm` / `.dicom`. Case-insensitive because sensor software often
/// emits uppercase `.DCM`.
bool isADcmName(String name) {
  const dcmExtensions = {'dcm', 'dicom'};
  final extension = name.split('.').last.toLowerCase();
  return dcmExtensions.contains(extension);
}

/// Saves [name] to the user's machine under its display name, not its stored name.
Future<void> downloadFile(String? rowId, String name,
    {FileLinkResolver? resolve}) async {
  final saveAs = displayNameForFile(name);
  Uint8List bytes;

  if (isUrl(name)) {
    final response = await http.get(Uri.parse(name));
    if (response.statusCode != 200) throw Exception('Download failed');
    bytes = response.bodyBytes;
  } else if (!kIsWeb && await checkIfFileExists(name)) {
    final file = await getOrCreateFile(name);
    bytes = await file.readAsBytes();
  } else if (rowId != null) {
    final url = await (resolve ?? resolveFileLink)(rowId, name);
    if (url == null) throw Exception('File not found');
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) throw Exception('Download failed');
    bytes = response.bodyBytes;
  } else {
    throw Exception('File not found');
  }
  await saveFileUtility(fileName: saveAs, bytes: bytes);
}

bool isUrl(String s) => s.startsWith('http://') || s.startsWith('https://');

/// Strips the URL path and the leading `<hash>_` from a stored name; a bare
/// legacy hash name is returned unchanged.
String displayNameForFile(String name) {
  // Strip URL to last path segment
  final base = name.contains('/') ? name.split('/').last : name;
  return _stripLastHashFromFileName(_stripLastHashFromFileName(base));
}

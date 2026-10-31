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

/// The width of the thumb every gallery grid shows: the size PocketBase keeps a
/// ready-made thumb for, and the size uploads generate for themselves.
const int kThumbSize = 100;

/// The width a gallery's large preview shows its picture at.
///
/// Four times the grid's own tiles: enough for the one picture a gallery shows
/// bigger, without fetching the original — a phone photo is several megabytes
/// and decodes to tens of megabytes for a box a few hundred pixels wide.
const int kPreviewSize = 640;

/// The local file a thumb of [name] at [size] is kept in.
///
/// The 100px thumb keeps the name it has always had — every device's cache
/// already holds one under it — while a larger preview says its size, so the
/// two never overwrite each other.
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
    // Async stat: this can run against a network share where a synchronous
    // stat would freeze the UI isolate.
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

  // Rename local files to match the PB-assigned name — avoids a redundant
  // re-download on first view and keeps the locally-generated thumbnail.
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

/// Bumped (incremented) each time a DCM PNG preview finishes generating.
/// The gallery subscribes to this via `MStreamBuilder` so placeholder cells
/// rebuild into real previews once the PNG lands.
final ObservableState<int> dicomPngReady = ObservableState<int>(0);

/// Background queue for DCM PNG preview generation. Serialised so we don't
/// fire off dozens of concurrent Rust parse+render calls during a bulk import.
final _dcmPngQue =
    TaskQueue(delayBetweenTasks: const Duration(milliseconds: 50));

/// Imports a `.dcm` file: saves the original to `filesDir()`, uploads it to
/// PocketBase immediately, and queues PNG preview generation in the background.
///
/// Returns the PB-assigned `.dcm` filename **without waiting** for the PNG —
/// the gallery shows a placeholder until [dicomPngReady] bumps.
///
/// On native: the `.dcm` is copied to `filesDir()` then uploaded. On web this
/// is a no-op (DCM import is Windows-only); returns an empty string.
///
/// PNG generation failure is logged to [dicomSkippedLog] with the reason
/// `"png_generation_failed"` — the `.dcm` is still preserved and viewable.
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

  // Generate a unique filename.
  // Async stat: watch folders can live on network shares where a synchronous
  // stat blocks the UI isolate for the duration of the round-trip.
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

/// Background task: parse the full DicomParseResult, render a PNG preview,
/// save it + a thumbnail locally, upload to PB, and bump [dicomPngReady].
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

/// The providers already resolved, by file name and by what was asked of it —
/// see [_cacheKey].
///
/// A provider is a small object: the pixels it decodes live in Flutter's own
/// bounded image cache. What this map saves is the work *around* a picture —
/// the disk lookup (and, on web, the file-name request), and on a device that
/// does not hold the file yet, the download itself. Without it a gallery would
/// ask the server for every file each time a window is opened.
///
/// Both thumbs and originals are kept: a tile shows a thumb, but the viewer
/// asks for the original of every picture it shows, and a photo reopened must
/// not be read off the disk again.
final imgMemoryCache = <String, ImageProvider>{};

/// How many pictures [imgMemoryCache] remembers. A visit's gallery, the cards
/// around it and its photos' own window fit several times over; past this the
/// oldest entry goes, which costs a disk lookup, never a download.
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

/// What one file's entries are told apart by.
///
/// Its 100px thumb keeps the file's own name — that is the entry a gallery
/// reads on every tile, and the one the tests plant — while a larger preview
/// and the original say which they are.
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
    // A file URL ends in the name it is stored under. A URL that names no file
    // at all is not one this helper can place, so it is left whole — and
    // answered below, where the app's own avatar is.
    final segments = Uri.parse(name).pathSegments;
    if (segments.isNotEmpty && segments.last.isNotEmpty) {
      name = segments.last;
    }
  }

  // DCM X-rays: never auto-fetch the raw .dcm (5–20 MB). Return the small
  // PNG preview instead. The raw .dcm is only fetched on-demand inside the
  // viewer panel (Phase 6).
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
    // Asked for again: it is the newest entry now, so the entries around it
    // are the ones that go when the cache is full.
    imgMemoryCache[key] = cached;
    return cached;
  }

  final img = await _getImage(rowID, name, thumb, resolve, thumbSize);
  // A lookup that found nothing is not remembered: an X-ray whose PNG preview
  // has not been generated yet becomes available later.
  if (img != null) {
    imgMemoryCache[key] = img;
    while (imgMemoryCache.length > _imgCacheLimit) {
      imgMemoryCache.remove(imgMemoryCache.keys.first);
    }
  }
  return img;
}

/// Thumb drawing in flight, by the file it will produce: several tiles ask for
/// one picture at once, and it only needs drawing once.
final _thumbJobs = <String, Future<File?>>{};

/// Local thumb drawing, one picture at a time.
///
/// Drawing decodes the whole picture — tens of megabytes for a phone photo —
/// and a gallery that opened on a dozen originals must not decode a dozen at
/// once just to make their previews.
final _thumbDrawQue = TaskQueue(delayBetweenTasks: Duration.zero);

/// Makes the thumb of [name] at [size] from the original on this device.
///
/// The file itself being here — a photo this device imported, or one it has
/// already shown at full size — is enough: the server's thumb is not worth a
/// round trip when the pixels are already on the disk, and a gallery that
/// opened offline still shows its pictures. Returns null when there is no
/// original to work from, or when it cannot be drawn.
Future<File?> _thumbFromLocal(String name, int size) {
  final thumbName = _thumbName(name, size);
  final inFlight = _thumbJobs[thumbName];
  if (inFlight != null) return inFlight;
  final job = _thumbDrawQue.add(() => _drawThumb(name, size)).whenComplete(() {
    // The stored value is this very job, so it is dropped by key: returning it
    // from here would make the completed future wait on itself.
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
    // Not ours to draw (an SVG, a file the image package cannot read): the
    // server's thumb is still worth asking for.
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

  // The thumb is not here, but the picture may be: draw it here rather than
  // ask the server for a copy of what this device already holds.
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

/// Returns `true` if [name] looks like a DICOM X-ray file
/// (`.dcm` / `.dicom`). Case-insensitive — sensor software often emits
/// uppercase `.DCM`. Used to distinguish X-rays from regular photos.
bool isADcmName(String name) {
  const dcmExtensions = {'dcm', 'dicom'};
  final extension = name.split('.').last.toLowerCase();
  return dcmExtensions.contains(extension);
}

/// Downloads a file from the local cache or remote server and saves it
/// via [saveFileUtility].
///
/// If [name] is already a URL (starts with `http`), it is downloaded directly.
/// Otherwise the local cache is checked first on native platforms, then
/// [rowId] + [name] are used to resolve a remote URL via [getImageLink].
/// Web downloads always use the remote file, without accessing the filesystem.
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

/// Returns a human-readable display name from a stored filename or URL.
///
/// - URLs: extracts last path segment
/// - Hash-prefixed names (`a3f8e2dc_invoice_2024.pdf`): strips the hash
/// - Legacy plain hashes (`a3f8e2dc.pdf`): returns as-is
String displayNameForFile(String name) {
  // Strip URL to last path segment
  final base = name.contains('/') ? name.split('/').last : name;
  return _stripLastHashFromFileName(_stripLastHashFromFileName(base));
}

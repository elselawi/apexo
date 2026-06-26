import 'dart:io';
import 'package:apexo/core/store.dart';
import 'package:apexo/utils/constants.dart';
import 'package:apexo/utils/hash.dart';
import 'package:apexo/utils/que.dart';
import 'package:apexo/utils/safe_dir.dart';
import 'package:apexo/utils/save_file_multiplatform.dart';
import 'package:apexo/utils/strip_id_from_file.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/adapters.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

Future<void> createDirectory(String path) async {
  final Directory dir = Directory(path);
  if (await dir.exists()) {
    return;
  } else {
    await dir.create(recursive: true);
  }
}

Future<bool> checkIfFileExists(String name) async {
  final File file = File(path.join(await filesDir(), name));
  return await file.exists();
}

Future<File> getOrCreateFile(String name) async {
  await createDirectory(await filesDir());
  return File(path.join(await filesDir(), name));
}

String _nameToThumbName(String name) {
  return "${path.withoutExtension(name)}.thumb${path.extension(name)}";
}

String _urlToThumbUrl(String url) {
  return "$url?thumb=100x100";
}

// copies a given image to local folder and upload it to the server
Future<String> handleNewImage({
  required String rowID,
  required String sourcePath,
  XFile? sourceFile,
  Store? targetStore,
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
    final mtime = File(sourcePath).lastModifiedSync().millisecondsSinceEpoch;
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
          ..writeToFile(_nameToThumbName(savedFile.path));
        await cmd.executeThread();
      } catch (_) {
        // Non-decodable file — skip local thumbnail (PB will handle server-side)
      }
    }
  }

  // uploading
  final store = targetStore ?? appointments;
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
      final oldThumb = File(_nameToThumbName(savedFile.path));
      if (await oldThumb.exists()) {
        await oldThumb.rename(_nameToThumbName(newPath));
      }
    } catch (_) {}
  }

  // returns the final file name
  return finalFileName;
}

final imgMemoryCache = <String, ImageProvider?>{};
final _imageHttpReqQue =
    TaskQueue(delayBetweenTasks: const Duration(milliseconds: 100));

String _stripLastHashFromFileName(String name) {
  return name.replaceFirstMapped(
    RegExp(r'^(.+)_[A-Za-z0-9]{6,}(\.[^.]+)$'),
    (m) => '${m[1]}${m[2]}',
  );
}

Future<ImageProvider?> getImage(String rowID, String name,
    [bool thumb = true]) async {
  if (isUrl(name)) {
    name = Uri.parse(name).pathSegments.last;
  }

  if (thumb &&
      imgMemoryCache.containsKey(name) &&
      imgMemoryCache[name] != null) {
    return imgMemoryCache[name];
  } else if (name == "https://person.alisaleem.workers.dev/") {
    final link = "$name?no-cache=$rowID";
    if (imgMemoryCache.containsKey(link)) {
      return imgMemoryCache[link];
    }
    final img = Image.network(link).image;
    return imgMemoryCache[link] = img;
  } else {
    final img = await _getImage(rowID, name, thumb);
    if (thumb) imgMemoryCache[name] = img;
    if (imgMemoryCache.length > 30) {
      imgMemoryCache.remove(imgMemoryCache.keys.first);
    }
    return img;
  }
}

Future<ImageProvider?> _getImage(String rowID, String name, bool thumb) async {
  // Web platform doesn't support local files
  if (kIsWeb) {
    final imgUrl = await appointments.remote!.getImageLink(rowID, name);
    return imgUrl == null
        ? null
        : NetworkImage(thumb ? _urlToThumbUrl(imgUrl) : imgUrl);
  }

  // if the file exists locally, return it
  final localName = thumb ? _nameToThumbName(name) : name;
  if (await checkIfFileExists(localName)) {
    return Image.file(await getOrCreateFile(localName)).image;
  }

  // if the file doesn't exist locally, download it from the server
  final imgUrl = await _imageHttpReqQue
      .add(() => appointments.remote!.getImageLink(rowID, name));
  if (imgUrl == null) return null;
  final download = await _imageHttpReqQue.add(() => saveImageFromUrl(
      thumb ? _urlToThumbUrl(imgUrl) : imgUrl,
      thumb ? _nameToThumbName(name) : name));
  return Image.file(download).image;
}

Future<File> savePickedImage(File image, String newName) async {
  final File newImage = await getOrCreateFile(newName);
  if (await newImage.exists()) return newImage;
  return await image.copy(newImage.path);
}

Future<File> saveImageFromUrl(String imageUrl, [String? givenName]) async {
  final imageName = givenName ?? stripIDFromFileName(imageUrl.split('/').last);

  // in case of web, we store the image link in the hive store
  if (kIsWeb) {
    await Hive.openBox(webImagesStore);
    await Hive.box(webImagesStore).put(imageName, imageUrl);
    return File(imageUrl);
  }

  final File newImage = await getOrCreateFile(imageName);
  if (await newImage.exists()) return newImage;

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

isAnImageName(String name) {
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

/// Downloads a file from the local cache or remote server and saves it
/// via [saveFileUtility].
///
/// If [name] is already a URL (starts with `http`), it is downloaded directly.
/// Otherwise the local cache is checked first, then [rowId] + [name] are used
/// to resolve a remote URL via [getImageLink].
Future<void> downloadFile(String? rowId, String name) async {
  final saveAs = displayNameForFile(name);
  Uint8List bytes;

  if (isUrl(name)) {
    final response = await http.get(Uri.parse(name));
    if (response.statusCode != 200) throw Exception('Download failed');
    bytes = response.bodyBytes;
  } else if (await checkIfFileExists(name)) {
    final file = await getOrCreateFile(name);
    bytes = await file.readAsBytes();
  } else if (rowId != null) {
    final url = await appointments.remote!.getImageLink(rowId, name);
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

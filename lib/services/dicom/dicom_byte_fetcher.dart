import 'package:apexo/core/persistence/save_remote.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/services/dicom/dicom_lru.dart';
import 'package:apexo/utils/hash.dart';
import 'package:apexo/utils/imgs.dart';
import 'package:apexo/utils/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Downloads the raw `.dcm` (5–20 MB) — the only place it is fetched; the gallery
/// uses the PNG preview. Native caches bytes in [DicomLruCache] (500 MB LRU), web
/// keeps them in memory. Returns null on failure and logs instead of throwing.
Future<Uint8List?> fetchDcmBytes({
  required String rowId,
  required String dcmName,
  SaveRemote? remote,
  DicomLruCache? lruCache,
}) async {
  final saveRemote = remote ?? appointments.remote!;
  final lru = lruCache ?? dicomLruCache;
  // A PB filename is unique only within its record/server, so the on-disk cache
  // is namespaced to prevent stale cross-clinic bytes.
  final cacheName =
      'dcm_${simpleHash('${saveRemote.pbInstance.baseURL}|$rowId|$dcmName')}_$dcmName';

  // Native: try the local LRU cache first.
  if (!kIsWeb) {
    try {
      if (await checkIfFileExists(cacheName)) {
        final file = await getOrCreateFile(cacheName);
        final bytes = await file.readAsBytes();
        // Refresh the LRU access timestamp so this entry survives eviction.
        await lru.markAccessed(cacheName);
        return bytes;
      }
    } catch (e, s) {
      logger('fetchDcmBytes: local cache read failed for $dcmName: $e', s);
      // fall through to remote fetch
    }
  }

  // Resolve the PocketBase file URL.
  final String? url;
  try {
    url = await saveRemote.getImageLink(rowId, dcmName);
  } catch (e, s) {
    logger('fetchDcmBytes: getImageLink failed for $rowId/$dcmName: $e', s);
    return null;
  }
  if (url == null) {
    logger('fetchDcmBytes: no PB file URL for $rowId/$dcmName', null, 3);
    return null;
  }

  // Download.
  final http.Response response;
  try {
    response = await http.get(Uri.parse(url));
  } catch (e, s) {
    logger('fetchDcmBytes: download failed for $url: $e', s);
    return null;
  }
  if (response.statusCode != 200) {
    logger('fetchDcmBytes: HTTP ${response.statusCode} for $url', null, 2);
    return null;
  }
  final bytes = response.bodyBytes;

  // Native: persist to filesDir() + record in the LRU cache for next time.
  if (!kIsWeb) {
    try {
      final file = await getOrCreateFile(cacheName);
      if (!await checkIfFileExists(cacheName)) {
        await file.writeAsBytes(bytes);
      }
      await lru.touch(cacheName, bytes.length);
    } catch (e, s) {
      logger('fetchDcmBytes: local cache write failed for $dcmName: $e', s);
      // Non-fatal — bytes are already in memory for this session.
    }
  }

  return bytes;
}

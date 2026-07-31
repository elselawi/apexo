// Barrel file for the DICOM service layer.
//
// Re-export everything that the rest of the app needs to consume:
//   - Parser + renderer wrappers (all platforms)
//   - IO facade (conditional import — Windows scans, web no-ops)
//   - Dedup registry + dedupKey (Hive-backed)
//   - File cache (Hive-backed — stat-based skip on re-scan)
//   - Name normalization + similarity
//   - Skipped-files log (Hive-backed)
//   - LRU cache for downloaded .dcm originals (Hive-backed)
//   - Viewer prefs (per-user windowing/color/invert/rotation persistence)

export 'dicom_parser.dart';
export 'dicom_renderer.dart';
export 'dicom_io_service.dart';
export 'persistence/dicom_linked_store.dart';
export 'persistence/dicom_matched_store.dart';
export 'persistence/dicom_unmatched_store.dart';
export 'dicom_file_cache.dart';
export 'dicom_normalize.dart';
export 'dicom_skipped.dart';
export 'dicom_lru.dart';
export 'dicom_viewer_prefs.dart';
export 'dicom_byte_fetcher.dart';
export 'dicom_importer.dart';

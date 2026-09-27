import 'package:apexo/utils/hash.dart';
import 'package:path/path.dart';

bool isDcmFileName(String name) {
  final lower = name.toLowerCase();
  return lower.endsWith('.dcm') || lower.endsWith('.dicom');
}

bool isDcmPreviewName(String name) {
  final lower = name.toLowerCase();
  return lower.endsWith('.dcm.png') || lower.endsWith('.dicom.png');
}

/// Returns the normalized logical DICOM upload identity, ignoring a PocketBase
/// collision suffix and the generated PNG preview extension.
String? dcmUploadIdentity(String filename) {
  var base = filename.split(RegExp(r'[/\\\\]')).last.toLowerCase();
  final isPreview = isDcmPreviewName(base);
  final isOriginal = isDcmFileName(base);
  if (!isPreview && !isOriginal) return null;
  if (isPreview) base = base.substring(0, base.length - '.png'.length);
  final extensionIndex = base.lastIndexOf('.');
  if (extensionIndex <= 0) return null;
  base = base.substring(0, extensionIndex);
  final match = RegExp(r'^dcm_([^_]+)(?:_.+)?$').firstMatch(base);
  return match == null ? null : 'dcm_${match.group(1)}';
}

/// Returns whether two filenames represent the same logical DICOM upload.
///
/// The original and its `.png` preview *are* the same logical upload: this
/// deliberately does not distinguish them, so a re-import replaces whichever
/// of the two names a column happens to carry (`dcmImgs` may hold either, an
/// older app version wrote previews into it).
bool sameDcmUploadIdentity(String a, String b) {
  final aIdentity = dcmUploadIdentity(a);
  final bIdentity = dcmUploadIdentity(b);
  return aIdentity != null && aIdentity == bIdentity;
}

/// The string an upload's stored name is hashed from: the source file's
/// basename and its mtime.
///
/// **One definition**, because the uploader and the scan have to agree: the
/// scan uses this to recognise a file the records already carry. Note what it is
/// *not*: the file's DICOM identity. The dedup registry, keyed by SOP UID, is
/// the precise answer to "was this imported"; this is the fallback for when
/// that registry has no entry — a lost registry, or a fresh install pointed at
/// a populated watch folder — and an edited mtime defeats it.
String dcmNameHashInput(String sourcePath, DateTime mtime) =>
    '${basename(sourcePath)}_${mtime.millisecondsSinceEpoch}';

/// The stored name a source `.dcm` is uploaded under: `dcm_<hash>.dcm`.
String dcmStoredNameFor(String sourcePath, DateTime mtime) =>
    'dcm_${simpleHash(dcmNameHashInput(sourcePath, mtime))}.dcm';

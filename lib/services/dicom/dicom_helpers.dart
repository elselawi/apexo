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

/// Logical upload identity: no PB collision suffix and no `.png` preview extension.
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

/// Whether two names are the same logical upload. The `.dcm` and its `.png` preview
/// deliberately count as one, because a column may hold either name.
bool sameDcmUploadIdentity(String a, String b) {
  final aIdentity = dcmUploadIdentity(a);
  final bIdentity = dcmUploadIdentity(b);
  return aIdentity != null && aIdentity == bIdentity;
}

/// Hash input for an upload's stored name: the source basename and mtime. Shared
/// by the uploader and the scan so they agree. This is not the DICOM identity —
/// the SOP-UID registry is — so it is only a fallback, and an edited mtime breaks it.
String dcmNameHashInput(String sourcePath, DateTime mtime) =>
    '${basename(sourcePath)}_${mtime.millisecondsSinceEpoch}';

/// The stored name a source `.dcm` is uploaded under: `dcm_<hash>.dcm`.
String dcmStoredNameFor(String sourcePath, DateTime mtime) =>
    'dcm_${simpleHash(dcmNameHashInput(sourcePath, mtime))}.dcm';

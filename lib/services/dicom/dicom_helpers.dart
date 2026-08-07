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

/// Returns whether two filenames represent the same logical DICOM upload and
/// the same original/preview physical type.
bool sameDcmUploadIdentity(String a, String b) {
  final aIdentity = dcmUploadIdentity(a);
  final bIdentity = dcmUploadIdentity(b);
  return aIdentity != null && aIdentity == bIdentity;
}

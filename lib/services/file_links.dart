/// Resolves a stored file's remote URL. The util that loads the image only has
/// the row id and name, so the composition root binds the store-aware resolver.
typedef FileLinkResolver = Future<String?> Function(String rowID, String name);

/// The resolver the running app bound, or null before it is bound.
FileLinkResolver? fileLinkResolver;

/// Null when no resolver is bound; an unresolved file is hidden, not an error.
Future<String?> resolveFileLink(String rowID, String name) async {
  final resolver = fileLinkResolver;
  if (resolver == null) return null;
  return resolver(rowID, name);
}

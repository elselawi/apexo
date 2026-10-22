/// Resolves the remote URL of a record's stored file.
///
/// The util that loads an image has the row id and the file name, not the store
/// the file lives in — and a util must not import a feature to guess. The
/// composition root binds the resolver at startup; a caller that knows its own
/// record passes its own.
typedef FileLinkResolver = Future<String?> Function(String rowID, String name);

/// The resolver the running app bound, or null before it is bound.
FileLinkResolver? fileLinkResolver;

/// Resolves [name] on [rowID], or null when no resolver is bound — a file that
/// cannot be resolved remotely is a file that is not shown, not a crash.
Future<String?> resolveFileLink(String rowID, String name) async {
  final resolver = fileLinkResolver;
  if (resolver == null) return null;
  return resolver(rowID, name);
}

/// Converts a JSON list into a fully escaped CSV string.
/// Preserves structural null values and optimizes memory allocation.
///
/// [includeColumns] is an optional list of column indices (0-indexed)
/// to include in the final output (e.g., [0, 2, 5]). Invalid indices are safely ignored.
String jsonListToCsv(List<dynamic> data,
    {List<int>? includeColumns, bool withHeader = true}) {
  if (data.isEmpty) return '';

  final headers = <String>{};
  final rows = <Map<String, dynamic>>[];

  // 1. Single pass: collect ordered unique headers and store flattened rows
  for (final item in data) {
    final flattened = <String, dynamic>{};
    _flatten('', item, flattened);

    headers
        .addAll(flattened.keys); // O(1) insertion, preserves structural order
    rows.add(flattened);
  }

  // Convert set to a indexable list representing the full schema
  List<String> headerList = headers.toList();

  // 2. Filter headers by the provided column indices if specified
  if (includeColumns != null) {
    headerList = includeColumns
        // Safety check: ensure the requested index exists in our discovered headers
        .where((index) => index >= 0 && index < headerList.length)
        .map((index) => headerList[index])
        .toList();
  }

  // If the filtering results in no columns, exit early
  if (headerList.isEmpty) return '';

  final buffer = StringBuffer();

  // 3. Write the safely escaped header row
  if (withHeader) {
    buffer.writeln(_escapeCsvRow(headerList));
  }

  // 4. Write data rows using only the filtered headers
  for (final row in rows) {
    final rowCells = headerList.map((header) {
      final value = row[header];
      return value == null ? '' : value.toString();
    }).toList();

    buffer.writeln(_escapeCsvRow(rowCells));
  }

  return buffer.toString();
}

/// Recursively flattens JSON trees into a single-level map using reference passing.
void _flatten(String path, dynamic value, Map<String, dynamic> out) {
  if (value is Map) {
    for (final entry in value.entries) {
      final newPath =
          path.isEmpty ? entry.key.toString() : '$path/${entry.key}';
      _flatten(newPath, entry.value, out);
    }
  } else if (value is List) {
    for (int i = 0; i < value.length; i++) {
      final newPath = path.isEmpty ? '$i' : '$path/$i';
      _flatten(newPath, value[i], out);
    }
  } else {
    out[path.isEmpty ? 'value' : path] = value;
  }
}

/// Escapes cells containing commas, quotes, or newlines per RFC 4180 rules.
String _escapeCsvRow(List<String> cells) {
  final escaped = cells.map((cell) {
    if (cell.contains(',') ||
        cell.contains('"') ||
        cell.contains('\n') ||
        cell.contains('\r')) {
      return '"${cell.replaceAll('"', '""')}"';
    }
    return cell;
  });
  return escaped.join(',');
}

/// Converts a CSV string (with header row) back into a JSON list.
/// If the CSV is malformed or any error occurs, returns an empty list.
List<dynamic> csvToJsonList(String csv) {
  if (csv.isEmpty) return [];

  try {
    // 1. Parse CSV into rows (list of list of strings)
    final rows = _parseCsv(csv);
    if (rows.length < 2) return []; // Need at least header + one data row

    final headers = rows[0];
    final List<dynamic> result = [];

    // 2. Process each data row
    for (int i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.length != headers.length) continue; // Column count mismatch

      // Build flat map: header -> value (empty string becomes null)
      final flatMap = <String, dynamic>{};
      for (int j = 0; j < headers.length; j++) {
        final value = row[j];
        flatMap[headers[j]] = (value.isEmpty) ? null : value;
      }

      // 3. Unflatten the map back to nested structure
      final unflattened = _unflatten(flatMap);
      result.add(unflattened);
    }

    return result;
  } catch (_) {
    return [];
  }
}

/// Simple RFC 4180 CSV parser that handles quotes, escaped quotes,
/// and newlines inside quoted fields.
List<List<String>> _parseCsv(String csv) {
  final rows = <List<String>>[];
  final currentRow = <String>[];
  final currentField = StringBuffer();
  bool inQuotes = false;
  int i = 0;
  final n = csv.length;

  while (i < n) {
    final c = csv[i];
    if (!inQuotes) {
      if (c == '"') {
        inQuotes = true;
        i++;
      } else if (c == ',') {
        currentRow.add(currentField.toString());
        currentField.clear();
        i++;
      } else if (c == '\n') {
        currentRow.add(currentField.toString());
        currentField.clear();
        rows.add(currentRow.toList());
        currentRow.clear();
        i++;
      } else if (c == '\r') {
        // Handle CRLF
        if (i + 1 < n && csv[i + 1] == '\n') i++;
        currentRow.add(currentField.toString());
        currentField.clear();
        rows.add(currentRow.toList());
        currentRow.clear();
        i++;
      } else {
        currentField.write(c);
        i++;
      }
    } else {
      // Inside quotes
      if (c == '"') {
        // Check for escaped quote ""
        if (i + 1 < n && csv[i + 1] == '"') {
          currentField.write('"');
          i += 2;
        } else {
          inQuotes = false;
          i++;
        }
      } else {
        currentField.write(c);
        i++;
      }
    }
  }

  // Add last field and row if any
  if (currentField.isNotEmpty ||
      (csv.isNotEmpty && csv[csv.length - 1] == ',')) {
    currentRow.add(currentField.toString());
  }
  if (currentRow.isNotEmpty) rows.add(currentRow);
  return rows;
}

dynamic _unflatten(Map<String, dynamic> flatMap) {
  // Primitive root case
  if (flatMap.length == 1 && flatMap.containsKey('value')) {
    return flatMap['value'];
  }

  // Build a tree using a mutable map where values can be placeholders
  final Map<String, dynamic> root = {};
  for (final entry in flatMap.entries) {
    final path = entry.key.split('/');
    _insert(root, path, entry.value);
  }

  // Convert map to appropriate type (list if all keys are integers)
  return _convert(root);
}

void _insert(Map<String, dynamic> current, List<String> path, dynamic value) {
  final key = path.first;
  if (path.length == 1) {
    current[key] = value;
  } else {
    current.putIfAbsent(key, () => <String, dynamic>{});
    final next = current[key];
    if (next is Map<String, dynamic>) {
      _insert(next, path.sublist(1), value);
    } else {
      // Should not happen if paths are consistent
      throw StateError('Path conflict');
    }
  }
}

dynamic _convert(dynamic node) {
  if (node is Map<String, dynamic>) {
    // Check if all keys can be parsed as integers and form a contiguous range?
    // For simplicity, if all keys are integer strings, convert to List.
    final keys = node.keys.toList();
    final allIntegers = keys.every((k) => int.tryParse(k) != null);
    if (allIntegers) {
      // Determine max index
      int maxIndex = -1;
      for (var k in keys) {
        int idx = int.parse(k);
        if (idx > maxIndex) maxIndex = idx;
      }
      final list = List<dynamic>.filled(maxIndex + 1, null);
      for (var entry in node.entries) {
        final idx = int.parse(entry.key);
        list[idx] = _convert(entry.value);
      }
      return list;
    } else {
      final map = <String, dynamic>{};
      for (var entry in node.entries) {
        map[entry.key] = _convert(entry.value);
      }
      return map;
    }
  }
  return node;
}

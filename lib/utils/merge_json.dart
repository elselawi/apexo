import 'dart:convert';

String mergeJsonStrings(String oldJson, String newJson) {
  final Map<String, dynamic> oldMap = jsonDecode(oldJson);
  final Map<String, dynamic> newMap = jsonDecode(newJson);

  final Map<String, dynamic> merged = _recursiveMerge(oldMap, newMap);

  return jsonEncode(merged);
}

Map<String, dynamic> _recursiveMerge(Map<String, dynamic> oldMap, Map<String, dynamic> newMap) {
  // Start with a copy of the old data
  final Map<String, dynamic> result = Map<String, dynamic>.from(oldMap);

  newMap.forEach((key, newValue) {
    final oldValue = result[key];

    if (_isEmpty(oldValue) && !_isEmpty(newValue)) {
      // Old was empty, new has value: update
      result[key] = newValue;
    } else if (!_isEmpty(oldValue) && !_isEmpty(newValue)) {
      // Both have values
      if (oldValue is Map<String, dynamic> && newValue is Map<String, dynamic>) {
        // If both are maps, merge them recursively
        result[key] = _recursiveMerge(oldValue, newValue);
      } else {
        // Otherwise, recent object takes precedence
        result[key] = newValue;
      }
    } else if (!_isEmpty(newValue)) {
      // Result didn't have the key at all, but newMap does
      result[key] = newValue;
    }
  });

  return result;
}

/// Helper to define what "empty" means in our context
/// a null value
/// an empty string
/// an empty list
bool _isEmpty(dynamic value) {
  if (value == null) return true;
  if (value is String && value.trim().isEmpty) return true;
  if (value is Iterable && value.isEmpty) return true; // Optional: handles empty lists
  return false;
}
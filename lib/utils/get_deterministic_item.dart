import 'dart:convert';

T getDeterministicItem<T>(List<T> items, String input) {
  // Convert the input string to a hash code
  final int hash =
      utf8.encode(input).fold(0, (prev, element) => prev + element);

  // Use the hash code to determine the index
  final int index = hash % items.length;

  return items[index];
}

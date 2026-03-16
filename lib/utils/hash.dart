import 'dart:convert';

import 'package:apexo/utils/constants.dart';

String simpleHash(String input, {int length = 17}) {
  const int prime = 31; // A prime multiplier for hashing
  int hash1 = 0;
  int hash2 = 0;

  // Generate two hash values to increase entropy
  for (int i = 0; i < input.length; i++) {
    hash1 = (hash1 * prime + input.codeUnitAt(i)) & 0xFFFFFFFF;
    hash2 = (hash2 + input.codeUnitAt(i) * prime) & 0xFFFFFFFF;
  }

  // Combine the two hashes to extend the output
  StringBuffer result = StringBuffer();
  for (int i = 0; i < length - 1; i++) {
    // Extend to a fixed-length output
    int combinedHash = (hash1 ^ hash2) & 0xFFFFFFFF;
    int index = combinedHash % alphabet.length;
    result.write(alphabet[index]);
    hash1 = (hash1 >> 2) | (hash2 << 2); // Mix hash1 and hash2
    hash2 = (hash2 >> 2) ^ (hash1 << 2); // Further mix
  }

  return "h${result.toString().isEmpty ? alphabet[0] : result.toString()}";
}


String secureHash(String input, {int length = 100}) {
  // 1. Generate an initial 64-bit seed from the input string
  // This ensures the "starting point" is unique to your input.
  int seed1 = 0x811c9dc5;
  int seed2 = 0x9e3779b1;
  
  for (int char in utf8.encode(input)) {
    seed1 = ((seed1 ^ char) * 0x01000193) & 0xFFFFFFFF;
    seed2 = ((seed2 ^ seed1) * 0x1b873593) & 0xFFFFFFFF;
  }

  // 2. Use the seeds to generate a non-repeating sequence
  // We use a simple Xorshift RNG which is fast and has no visible patterns.
  StringBuffer result = StringBuffer();
  const String chars = 'abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  
  int x = seed1;
  int y = seed2;

  while (result.length < length) {
    // Xorshift logic to scramble bits
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= (x >>> 17);
    x ^= (x << 5) & 0xFFFFFFFF;
    
    // Mix x and y to prevent cycles
    int combined = (x + y) & 0xFFFFFFFF;
    y = (y + 0x9e3779b9) & 0xFFFFFFFF; // Increment y with a golden ratio constant
    
    // Map the scrambled number to our character set
    int index = combined % chars.length;
    result.write(chars[index]);
  }

  return result.toString();
}
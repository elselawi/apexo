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

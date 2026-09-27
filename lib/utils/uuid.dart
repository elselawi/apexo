import 'dart:math';

import 'package:apexo/utils/constants.dart';

String uuid() {
  final Random rand = Random();
  final StringBuffer buffer = StringBuffer();

  for (int i = 0; i < 15; i++) {
    final int index = rand.nextInt(alphabet.length);
    buffer.write(alphabet[index]);
  }

  return buffer.toString();
}

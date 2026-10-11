import 'package:apexo/common_widgets/live_transcribing_textfield.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

void main() {
  testWidgets('a field keeps the platform box unless given a decoration',
      (tester) async {
    await pumpApexoApp(
        tester,
        const SizedBox(
            width: 200, height: 80, child: LiveTranscribingTextField()));
    final field =
        tester.widget<CupertinoTextField>(find.byType(CupertinoTextField));
    // CupertinoTextField paints its own box only when the decoration argument
    // is left off entirely, so passing null here would strip the background
    // from every field that does not ask for a decoration of its own.
    expect(field.decoration, isNotNull, reason: 'the default field box');
  });

  testWidgets('a decoration from the caller replaces the field box',
      (tester) async {
    await pumpApexoApp(
        tester,
        const SizedBox(
            width: 200,
            height: 80,
            child: LiveTranscribingTextField(decoration: BoxDecoration())));
    final field =
        tester.widget<CupertinoTextField>(find.byType(CupertinoTextField));
    expect(field.decoration, isNotNull,
        reason: 'the caller asked for this decoration');
    expect(field.decoration!.color, isNull, reason: 'and it paints nothing');
  });
}

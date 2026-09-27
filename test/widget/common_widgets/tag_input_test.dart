import 'package:apexo/common_widgets/tag_input.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

/// A non-strict tag box: the typed text may become a new tag.
Future<List<List<TagInputItem>>> pumpTagInput(
  WidgetTester tester, {
  bool strict = false,
  List<TagInputItem> suggestions = const [],
  List<TagInputItem> initial = const [],
  int limit = 5,
}) async {
  final changes = <List<TagInputItem>>[];
  await pumpApexoApp(
    tester,
    SizedBox(
      width: 400,
      child: TagInputWidget(
        suggestions: suggestions,
        initialValue: initial,
        strict: strict,
        limit: limit,
        placeholder: 'tag',
        onChanged: changes.add,
      ),
    ),
  );
  return changes;
}

void main() {
  testWidgets('Enter commits the typed text as a tag', (tester) async {
    final changes = await pumpTagInput(tester);

    await tester.enterText(find.byType(EditableText), 'pwtag');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    // The manual says "type and press Enter to add" — before the fix, Enter
    // only dropped focus and closed the dropdown, so nothing was added.
    expect(changes, isNotEmpty);
    expect(changes.last.map((t) => t.value), ['pwtag']);
  });

  testWidgets('Enter does not duplicate the text that is already a tag',
      (tester) async {
    final changes = await pumpTagInput(
      tester,
      initial: [TagInputItem(value: 'ortho', label: 'ortho')],
    );

    await tester.enterText(find.byType(EditableText), 'ortho');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(changes, isEmpty, reason: 'the tag was already there');
  });

  testWidgets('a strict box refuses text that matches no suggestion',
      (tester) async {
    final changes = await pumpTagInput(
      tester,
      strict: true,
      suggestions: [TagInputItem(value: 'ortho', label: 'Ortho')],
    );

    await tester.enterText(find.byType(EditableText), 'not-a-doctor');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(changes, isEmpty);
  });

  testWidgets('a strict box accepts a matching label, case-insensitively',
      (tester) async {
    final changes = await pumpTagInput(
      tester,
      strict: true,
      suggestions: [TagInputItem(value: 'doctor_7', label: 'Dr. Smith')],
    );

    await tester.enterText(find.byType(EditableText), 'dr. smith');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(
      changes.last.map((t) => t.value),
      ['doctor_7'],
      reason: 'the suggestion\'s own value is what a picker stores',
    );
    expect(changes.last.map((t) => t.label), ['Dr. Smith']);
  });

  testWidgets('an empty box ignores Enter', (tester) async {
    final changes = await pumpTagInput(tester);

    await tester.enterText(find.byType(EditableText), '   ');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(changes, isEmpty);
  });
}

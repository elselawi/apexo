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

    // Enter used to only drop focus and close the dropdown, adding nothing.
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

  testWidgets('a full field keeps its one chip instead of folding it away',
      (tester) async {
    // At `limit: 1` a focused box used to fold the just-picked chip to "+1"; a
    // full field has no input to make room for.
    final changes = await pumpTagInput(
      tester,
      strict: true,
      suggestions: [
        TagInputItem(value: 'p1', label: 'Ada Lovelace'),
        TagInputItem(value: 'p2', label: 'Grace Hopper'),
      ],
      limit: 1,
    );

    await tester.tap(find.byType(EditableText));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), 'Ada Lovelace');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(changes.last.map((t) => t.value), ['p1']);
    expect(find.text('+1'), findsNothing);
    expect(find.text('Ada Lovelace'), findsWidgets);
  });

  testWidgets('a focused field that can still take tags folds its chips',
      (tester) async {
    await pumpTagInput(
      tester,
      suggestions: [TagInputItem(value: 'a', label: 'alpha')],
      initial: [TagInputItem(value: 'a', label: 'alpha')],
      limit: 5,
    );

    await tester.tap(find.byType(EditableText));
    await tester.pumpAndSettle();

    expect(find.text('+1'), findsOneWidget,
        reason: 'the input needs the room the chips would take');
  });

  testWidgets('an empty box ignores Enter', (tester) async {
    final changes = await pumpTagInput(tester);

    await tester.enterText(find.byType(EditableText), '   ');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(changes, isEmpty);
  });

  testWidgets('closing the dialog that holds it disposes without a rebuild',
      (tester) async {
    // `AutoSuggestBoxState.dispose()` fires each item's `onFocusChange(false)`
    // while the framework is locked, so rebuilding there asserts.
    await pumpApexoApp(
      tester,
      Builder(
        builder: (context) => FilledButton(
          key: const Key('openTagDialog'),
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => ContentDialog(
              title: const Text('tags'),
              content: SizedBox(
                width: 320,
                child: TagInputWidget(
                  suggestions: [
                    TagInputItem(value: 'a', label: 'alpha'),
                    TagInputItem(value: 'b', label: 'bravo'),
                  ],
                  initialValue: const [],
                  strict: true,
                  limit: 5,
                  placeholder: 'tag',
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('openTagDialog')));
    await tester.pumpAndSettle();

    // A highlighted suggestion is the state whose blur the dispose path fires.
    await tester.enterText(find.byType(EditableText), 'a');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    // Popped directly: the open dropdown covers the dialog's own button.
    Navigator.of(tester.element(find.byType(ContentDialog))).pop();
    await tester.pumpAndSettle();

    expect(find.byType(TagInputWidget), findsNothing,
        reason: 'the box has to be gone for its dispose to be under test');
    expect(tester.takeException(), isNull);
  });
}

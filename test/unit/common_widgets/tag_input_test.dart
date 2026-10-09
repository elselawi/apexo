import 'package:apexo/common_widgets/tag_input.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> mount(
    WidgetTester tester, {
    bool strict = false,
    List<TagInputItem> suggestions = const [],
    required void Function(List<TagInputItem>) onChanged,
  }) async {
    await tester.pumpWidget(FluentApp(
      home: ScaffoldPage(
          content: Center(
              child: SizedBox(
        width: 400,
        child: TagInputWidget(
          suggestions: suggestions,
          initialValue: const [],
          strict: strict,
          limit: 5,
          onChanged: onChanged,
        ),
      ))),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('Enter commits a new tag and clears the input', (tester) async {
    var tags = <TagInputItem>[];
    await mount(tester, onChanged: (value) => tags = List.of(value));
    final input = find.byType(AutoSuggestBox<String>);
    await tester.tap(input);
    await tester.enterText(input, 'new tag');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(tags.map((tag) => tag.label), ['new tag']);
    expect(
        tester.widget<AutoSuggestBox<String>>(input).controller!.text, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('strict input rejects unknown text and commits a known value',
      (tester) async {
    var tags = <TagInputItem>[];
    await mount(tester,
        strict: true,
        suggestions: [
          TagInputItem(value: 'patient-id', label: 'Known Patient')
        ],
        onChanged: (value) => tags = List.of(value));
    final input = find.byType(AutoSuggestBox<String>);
    await tester.tap(input);
    await tester.enterText(input, 'unknown');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(tags, isEmpty);
    await tester.tap(input);
    await tester.enterText(input, 'Known Patient');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(tags.map((tag) => tag.value), ['patient-id']);
  });

  testWidgets('Enter does not add a case-insensitive duplicate',
      (tester) async {
    var tags = <TagInputItem>[];
    await mount(tester, onChanged: (value) => tags = List.of(value));
    final input = find.byType(AutoSuggestBox<String>);
    await tester.tap(input);
    await tester.enterText(input, 'new tag');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.tap(input);
    await tester.enterText(input, 'NEW TAG');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(tags.map((tag) => tag.label), ['new tag']);
  });
}

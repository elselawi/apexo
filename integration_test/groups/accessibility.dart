// What an assistive-technology user can reach, and what the keyboard can do. §4.2.
//
// The app is Flutter, so its accessibility tree is the `Semantics` tree and
// `tester.getSemantics` reads exactly what a screen reader is handed. Three
// properties are asserted, each of them a real problem here before:
//
//  * every screen's **primary action** is a labelled button, so it can be
//    announced and activated rather than being an icon nobody can name;
//  * the command bar's **search field** keeps its own semantics boundary — the
//    comment in `screen_command_bar.dart` records the field once merging into the
//    whole content area (~780x620), which made it unreachable for assistive
//    technology *and* for automation; `02` is that regression;
//  * a **dialog** holds focus while it is up and hands it back when it closes,
//    and the command bar can be reached and operated with the keyboard alone.
import 'package:apexo/common_widgets/screen_command_bar.dart' show TopSearch;
import 'package:apexo/services/localization/locale.dart' show txt;
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import '../support/e2e.dart';
import '../support/fixtures.dart';

/// Whether the currently focused widget is inside a dialog.
bool _focusIsInDialog() {
  final focus = FocusManager.instance.primaryFocus;
  final context = focus?.context;
  if (context == null) return false;
  return context.findAncestorWidgetOfExactType<ContentDialog>() != null;
}

/// What is holding focus, as a widget type — the trail `04` prints on failure.
String _focusedWidget() =>
    FocusManager.instance.primaryFocus?.context?.widget.runtimeType
        .toString() ??
    'nothing';

void registerAccessibilityTests() {
  group('accessibility', () {
    testWidgets('01: every screen\'s primary action is an announced button',
        (tester) async {
      await E2E.signIn(tester);

      // Each entry is a screen's primary action: the button a user most needs to
      // find, and the one a screen reader has to be able to name and press.
      final actions = <String, Finder>{
        'patients': find.byKey(WK.btnNewPatient),
        'calendar': find.byKey(WK.btnNewAppointment),
        'notes': find.byKey(WK.btnNewNote),
        'accounts': find.byKey(WK.btnNewAccount),
      };
      final routes = <String, String>{
        'patients': 'patients',
        'calendar': 'calendar',
        'notes': 'notes',
        'accounts': 'accounts',
      };

      for (final entry in actions.entries) {
        await Fixtures.openRoute(tester, routes[entry.key]!, entry.value,
            description: 'the ${entry.key} screen');
        final data = tester.getSemantics(entry.value).getSemanticsData();
        expect(data.flagsCollection.isButton, isTrue,
            reason:
                '${entry.key}\'s primary action is not exposed as a button');
        expect(data.label.trim(), isNotEmpty,
            reason: '${entry.key}\'s primary action has no label to announce');
      }
    });

    testWidgets('02: the search field keeps its own semantics boundary',
        (tester) async {
      await E2E.signIn(tester);
      await Fixtures.openPatients(tester);

      final field = tester.getSemantics(find.byKey(WK.listSearch));
      final data = field.getSemanticsData();
      expect(data.flagsCollection.isTextField, isTrue,
          reason: 'the search box is not exposed as a text field');
      // The boundary is the property, and **size** is what proves it. Two traps:
      // the field is `Expanded`, so its width is legitimately the content width
      // (1264 here) and says nothing; and `SemanticsNode.rect` is expressed in
      // its *parent's* space (the transform is carried separately), so it cannot
      // be compared with `tester.getRect`, which is global — the two differ by
      // the nav pane's offset even when they describe the same box. What the
      // regression looked like was a node that had merged into the content area
      // (~780x620 in the web build): the field's node must be no larger than the
      // `TopSearch` bar that owns the boundary, and must stay a bar.
      final bar = tester.getSize(find.byType(TopSearch));
      final fieldRect = field.rect;
      expect(fieldRect.height, lessThan(200),
          reason: 'the search field\'s node is ${fieldRect.height}px tall — it '
              'merged into the content area instead of being its own bar');
      expect(
        fieldRect.width <= bar.width + 1 && fieldRect.height <= bar.height + 1,
        isTrue,
        reason: 'the search field\'s node ${fieldRect.size} is larger than the '
            'search bar $bar',
      );
      expect(
        find.ancestor(
          of: find.byKey(WK.listSearch),
          matching: find.byType(TopSearch),
        ),
        findsOneWidget,
      );
    });

    testWidgets('03: a dialog keeps focus and hands it back', (tester) async {
      await E2E.signIn(tester);
      await Fixtures.openNotes(tester);

      // The board's add-column dialog is a `ContentDialog` whose field is
      // autofocused: the modal a user meets first here, and the one whose
      // keyboard has to stay inside it while it is up.
      await Fixtures.revealInBoard(tester, find.byKey(WK.btnAddColumn));
      await E2E.tap(tester, find.byKey(WK.btnAddColumn),
          description: 'the add-column button');
      await E2E.waitFor(tester, find.byKey(WK.fieldColumnTitle),
          description: 'the add-column dialog');

      expect(_focusIsInDialog(), isTrue,
          reason: 'the dialog did not take focus (${_focusedWidget()} has it), '
              'so the keyboard still acts on the board behind it');

      await E2E.tap(
        tester,
        // `find.text` matches the `Txt` **and** the `Text` it renders, so a bare
        // `find.text('cancel')` is ambiguous ("Found 2 widgets"); asking for the
        // button that *has* the text pins it down.
        find.descendant(
          of: find.byType(ContentDialog),
          matching: find.widgetWithText(FilledButton, txt('cancel')),
        ),
        description: 'the dialog\'s cancel button',
      );
      await E2E.waitForGone(tester, find.byType(ContentDialog),
          description: 'the add-column dialog to close');
      expect(_focusIsInDialog(), isFalse,
          reason: 'focus stayed inside the dialog after it closed');
    });

    testWidgets('04: the command bar answers the keyboard', (tester) async {
      await E2E.signIn(tester);
      await Fixtures.openPatients(tester);

      final search = find.byKey(WK.listSearch);
      final editable =
          find.descendant(of: search, matching: find.byType(EditableText));
      expect(editable, findsOneWidget, reason: 'the search box has no field');
      // The widget's own focus node, not the element's: comparing
      // `primaryFocus.context` to the `EditableText` element is never true — the
      // attached context belongs to a `Focus` widget *below* it, which is how an
      // earlier version of this test reported a reachable field as unreachable.
      final node = tester.widget<EditableText>(editable).focusNode;

      // Tab until the field itself holds focus. A sidebar, the command bar's
      // buttons and the filter chips all come first, so the bound is generous;
      // the trail is what makes a failure here diagnosable — "which stop did it
      // reach" is the whole finding, whether that is the far end of the screen
      // or nothing at all.
      var reached = false;
      final trail = <String>[];
      for (var i = 0; i < 80 && !reached; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await E2E.settle(tester, frames: 2);
        reached = FocusManager.instance.primaryFocus == node;
        if (!reached && i % 4 == 0) trail.add('$i:${_focusedWidget()}');
      }
      expect(reached, isTrue,
          reason: 'the keyboard never reached the search box in 80 tabs — the '
              'command bar is not keyboard-reachable. Trail: ${trail.join(' ')}');

      // Reaching it is half the property; the field taking the text is the
      // other half, because a node can hold focus and still not be the editable
      // the keyboard types into.
      await tester.enterText(editable, 'e2e keyboard');
      await E2E.settle(tester, frames: 5);
      expect(
          tester.widget<EditableText>(editable).controller.text, 'e2e keyboard',
          reason: 'the search box had focus but the text did not reach it');
      await tester.enterText(editable, '');
      await E2E.settle(tester, frames: 3);
    });
  });
}

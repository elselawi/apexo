// The shell's navigation mechanics, off the e2e harness.
//
// `integration_test`'s groups keep failing with "Timed out after 60s waiting
// for the patients screen" after a nav-pane tap that *did* land, so the subject
// here is the one thing between those two facts: a `NavigationView` whose
// `NavigationPane.selected` is owned by the caller (that is what
// `lib/app/app.dart` does — `selected: routes.currentIndex`), and whether the
// body it draws follows that index.
//
// These are the cheapest possible reproductions: no app, no database, no
// server, ~1s per run instead of ~8 minutes.
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// The app's own shape: the pane's selection is a prop the caller changes.
  Widget shell(int selected) {
    return NavigationView(
      appBar: const NavigationAppBar(height: 40),
      pane: NavigationPane(
        selected: selected,
        displayMode: PaneDisplayMode.auto,
        toggleable: false,
        items: [
          for (final id in const ['dashboard', 'patients', 'calendar'])
            PaneItem(
              key: Key('${id}_screen_button'),
              icon: const Icon(FluentIcons.home),
              title: Text(id),
              body: KeyedSubtree(
                key: GlobalObjectKey(id),
                child: Center(child: Text('body $id')),
              ),
            ),
        ],
      ),
    );
  }

  testWidgets('the pane body follows the selected index', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1600, 1000);
    addTearDown(tester.view.reset);

    var selected = 0;
    late StateSetter rebuild;

    await tester.pumpWidget(FluentApp(
      home: StatefulBuilder(builder: (context, setState) {
        rebuild = setState;
        return shell(selected);
      }),
    ));
    await tester.pumpAndSettle();

    expect(find.text('body dashboard'), findsOneWidget);

    rebuild(() => selected = 1);
    await tester.pumpAndSettle();

    expect(find.text('body patients'), findsOneWidget,
        reason: 'the pane body did not follow the selected index');
  });

  testWidgets('a stale body is not left on screen', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1600, 1000);
    addTearDown(tester.view.reset);

    var selected = 0;
    late StateSetter rebuild;

    await tester.pumpWidget(FluentApp(
      home: StatefulBuilder(builder: (context, setState) {
        rebuild = setState;
        return shell(selected);
      }),
    ));
    await tester.pumpAndSettle();

    for (var i = 1; i < 3; i++) {
      rebuild(() => selected = i);
      await tester.pumpAndSettle();
      if (find
          .text('body ${const ['dashboard', 'patients', 'calendar'][i]}')
          .evaluate()
          .isEmpty) {
        break;
      }
    }

    expect(find.text('body calendar'), findsOneWidget,
        reason: 'the pane body did not keep up with a second selection change');
  });
}

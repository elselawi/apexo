import 'package:apexo/app/title_bar_safe_area.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// `TitleBar` pads itself with a `SafeArea` and adds `MediaQuery.padding.top`
/// to its height as well, so a phone's status bar used to be counted twice:
/// the bar hung a status bar down over the body. These pin the inset to one.
void main() {
  const inset = 44.0;

  Widget shellWithInset(double topInset) => MediaQuery(
        data: MediaQueryData(
          size: const Size(390, 844),
          padding: EdgeInsets.only(top: topInset),
          viewPadding: EdgeInsets.only(top: topInset),
        ),
        child: const _Shell(),
      );

  testWidgets('the title bar sits right under the status bar', (tester) async {
    await tester.pumpWidget(FluentApp(home: shellWithInset(inset)));
    await tester.pumpAndSettle();

    final bar = tester.getRect(find.byType(TitleBar));
    expect(bar.top, inset, reason: 'the status bar is left uncovered');
    expect(bar.height, 40, reason: 'the status bar was counted twice');

    final body = tester.getRect(find.byKey(const Key('body')));
    expect(body.top, inset + 40, reason: 'the bar hangs over the body');
  });

  testWidgets('without a status bar the bar keeps the top edge',
      (tester) async {
    await tester.pumpWidget(FluentApp(home: shellWithInset(0)));
    await tester.pumpAndSettle();

    final bar = tester.getRect(find.byType(TitleBar));
    expect(bar.top, 0);
    expect(bar.height, 40);

    final body = tester.getRect(find.byKey(const Key('body')));
    expect(body.top, 40);
  });
}

class _Shell extends StatelessWidget {
  const _Shell();

  @override
  Widget build(BuildContext context) {
    return TitleBarSafeArea(
      child: NavigationView(
        titleBar: const TitleBar(height: 40, title: Text('Appointments')),
        // A phone is the pane's minimal mode, the shape the shell runs in.
        pane: NavigationPane(
          selected: 0,
          displayMode: PaneDisplayMode.auto,
          toggleable: false,
          items: [
            PaneItem(
              icon: const Icon(FluentIcons.home),
              body: const SizedBox.expand(
                key: Key('body'),
                child: ColoredBox(color: Color(0xFF00FF00)),
              ),
              title: const Text('Appointments'),
            ),
          ],
        ),
      ),
    );
  }
}

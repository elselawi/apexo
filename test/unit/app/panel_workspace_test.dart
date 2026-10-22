/// The panel's window bookkeeping, pinned on its own: which windows the shell
/// opens for a screen, and what a click on the panel's dock does to them.
library;

import 'dart:async';

import 'package:apexo/ui/workspace/panel_workspace.dart';
import 'package:apexo/ui/workspace/windows_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const wide = WindowsLayout(compact: false, capacity: 2);
  const single = WindowsLayout(compact: false, capacity: 1);
  const phone = WindowsLayout(compact: true, capacity: 1);

  test('a wide screen opens a screenful, in the panel\'s order', () {
    final workspace = PanelWorkspace()
      ..arrange(layout: wide, candidates: ['a', 'b', 'c']);

    expect(workspace.open, ['a', 'b']);
  });

  test('a phone opens nothing until asked', () {
    final workspace = PanelWorkspace()
      ..arrange(layout: phone, candidates: ['a', 'b']);

    expect(workspace.open, isEmpty);
  });

  test('the window the opener asked for takes the first slot', () {
    final workspace = PanelWorkspace()
      ..arrange(layout: single, candidates: ['a', 'b'], focus: 'b');

    expect(workspace.open, ['b']);
  });

  test('the opener\'s window also wins on a phone', () {
    final workspace = PanelWorkspace()
      ..arrange(layout: phone, candidates: ['a', 'b'], focus: 'b');

    expect(workspace.open, ['b']);
  });

  test('asking for a window already on screen puts nothing away', () {
    // Re-asking for a window is how a caller brings it forward: it must not
    // cost a neighbour its place, which is what a full screen would otherwise
    // make room for.
    final workspace = PanelWorkspace()
      ..arrange(layout: wide, candidates: ['a', 'b'], focus: 'a');

    expect(workspace.open, ['a', 'b']);
  });

  test('a screen with no capacity ignores the request instead of throwing', () {
    final workspace = PanelWorkspace()
      ..arrange(
        layout: const WindowsLayout(compact: false, capacity: 0),
        candidates: const [],
        focus: 'b',
      );

    expect(workspace.open, isEmpty);
  });

  test('toggling opens and closes the same window', () {
    final workspace = PanelWorkspace()
      ..arrange(layout: wide, candidates: const []);

    workspace.toggle('a');
    expect(workspace.isOpen('a'), isTrue);
    workspace.toggle('a');
    expect(workspace.isOpen('a'), isFalse);
  });

  test('opening a window never puts another one away while there is room', () {
    final workspace = PanelWorkspace()
      ..arrange(layout: wide, candidates: const []);

    workspace.toggle('a');
    workspace.toggle('b');
    expect(workspace.open, ['a', 'b']);
  });

  test('with the row full, the window asked for is the one shown', () {
    // The screen shows two windows: asking for a third gives up the one that has
    // been up longest, because a window nobody can see is not a window.
    final workspace = PanelWorkspace()
      ..arrange(layout: wide, candidates: ['a', 'b']);

    workspace.toggle('c');
    expect(workspace.open, ['b', 'c']);

    workspace.show('d');
    expect(workspace.open, ['c', 'd'], reason: 'the newest request wins');
  });

  test('asking again for a window that is up keeps the row as it is', () {
    final workspace = PanelWorkspace()
      ..arrange(layout: wide, candidates: ['a', 'b']);

    workspace.show('a');
    expect(workspace.open, ['a', 'b']);
  });
  test('on a phone a second window replaces the first', () {
    final workspace = PanelWorkspace()
      ..arrange(layout: phone, candidates: const []);
    workspace.toggle('a');
    workspace.toggle('b');
    expect(workspace.open, ['b']);
  });

  test('showing on a phone replaces the screenful', () {
    final workspace = PanelWorkspace()
      ..arrange(layout: phone, candidates: const []);
    workspace.toggle('a');
    workspace.show('b');

    expect(workspace.open, ['b']);
  });

  test('minimizing leaves the other windows alone', () {
    final workspace = PanelWorkspace()
      ..arrange(layout: wide, candidates: ['a', 'b']);
    workspace.minimize('a');

    expect(workspace.open, ['b']);
  });

  test('every change is announced, and a no-op is not', () async {
    final workspace = PanelWorkspace();
    var revisions = 0;
    final announced = Completer<void>();
    workspace.revision.stream.listen((_) {
      revisions++;
      if (revisions == 2 && !announced.isCompleted) announced.complete();
    });

    workspace.arrange(layout: wide, candidates: ['a', 'b']);
    workspace.minimize('b');
    // The two changes are waited for, not assumed: the stream is
    // asynchronous, and a test that reads it too early sees nothing.
    await announced.future;

    // The second minimize changed nothing, so nothing is announced.
    workspace.minimize('b');
    await Future<void>.delayed(Duration.zero);

    expect(revisions, 2);
  });

  group('remembered windows', () {
    test('the windows the user left open are the ones restored', () {
      final workspace = PanelWorkspace()
        ..arrange(
          layout: wide,
          candidates: ['a', 'b', 'c'],
          preferred: ['c'],
        );

      expect(workspace.open, ['c']);
    });

    test('restored windows keep the panel\'s order, not the stored one', () {
      // The panel decides which window comes first on screen; the memory only
      // says which ones to show.
      final workspace = PanelWorkspace()
        ..arrange(
          layout: wide,
          candidates: ['a', 'b', 'c'],
          preferred: ['c', 'a'],
        );

      expect(workspace.open, ['a', 'c']);
    });

    test('never remembered opens the panel\'s own first picks', () {
      final workspace = PanelWorkspace()
        ..arrange(layout: wide, candidates: ['a', 'b', 'c']);

      expect(workspace.open, ['a', 'b']);
    });

    test('leaving none open is a choice: nothing comes back', () {
      final workspace = PanelWorkspace()
        ..arrange(layout: wide, candidates: ['a', 'b'], preferred: const []);

      expect(workspace.open, isEmpty);
    });

    test('a remembered window the panel no longer offers is dropped', () {
      final workspace = PanelWorkspace()
        ..arrange(
          layout: wide,
          candidates: ['a', 'b'],
          preferred: ['gone', 'b'],
        );

      expect(workspace.open, ['b']);
    });

    test('the window the opener asked for is shown even when not remembered',
        () {
      final workspace = PanelWorkspace()
        ..arrange(
          layout: wide,
          candidates: ['a', 'b'],
          preferred: ['a'],
          focus: 'b',
        );

      expect(workspace.open, ['a', 'b']);
    });

    test('the memory is reported when the user is the one who changes it', () {
      final reported = <List<String>>[];
      final workspace = PanelWorkspace(onUserChange: reported.add)
        ..arrange(layout: wide, candidates: ['a', 'b']);

      // The screen deciding is not the user: nothing is reported for it.
      expect(reported, isEmpty);

      workspace.toggle('c');
      workspace.minimize('b');
      expect(reported, [
        ['b', 'c'],
        ['c'],
      ]);
    });

    test('a no-op toggle reports nothing', () {
      final reported = <List<String>>[];
      final workspace = PanelWorkspace(onUserChange: reported.add);
      workspace.minimize('a');

      expect(reported, isEmpty);
    });

    test('measuring the screen changes nothing on it', () {
      // A panel that opens with no windows of its own still has to know how many
      // its row holds, or the windows the user opens later would overlap.
      final workspace = PanelWorkspace()..measure(single);
      workspace.show('a');
      workspace.toggle('b');

      expect(workspace.open, ['b']);
    });

    test('a phone holds one window, measured before any is opened', () {
      final workspace = PanelWorkspace()..measure(phone);
      workspace.toggle('a');
      workspace.toggle('b');

      expect(workspace.open, ['b']);
    });
  });
}

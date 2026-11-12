/// The windows the shell opens for a panel, and what its dock click does.
library;

import 'dart:async';

import 'package:apexo/ui/workspace/panel_workspace.dart';
import 'package:apexo/ui/workspace/window_group.dart';
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
    // re-asking brings the window forward, so it must not evict a neighbour
    // even when the row is full.
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
    // a third window evicts the one up longest, not the one just asked for.
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
    // the stream is async: wait for both changes instead of assuming them.
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
      // restored windows keep the panel's order; the memory only selects which.
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
      final workspace = PanelWorkspace(onUserChange: (_, open) => reported.add(open))
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
      final workspace = PanelWorkspace(onUserChange: (_, open) => reported.add(open));
      workspace.minimize('a');

      expect(reported, isEmpty);
    });

    test('measuring the screen changes nothing on it', () {
      // capacity must be measured before opening: toggle needs it to evict,
      // otherwise the windows opened later overlap.
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

  group('two records in one row', () {
    /// A plan whose row shows exactly [keys], in that order.
    WindowsPlan planOf(
      List<String> keys, {
      bool compact = false,
      Map<String, double>? widths,
      double available = 1550,
    }) {
      final measured = widths ??
          <String, double>{
            for (final key in keys) key: 350,
          };
      var used = 0.0;
      for (final key in keys) {
        used += (used == 0 ? 0 : 12) + (measured[key] ?? 350);
      }
      return WindowsPlan(
        compact: compact,
        selected: keys,
        widths: measured,
        used: used,
        available: available,
        room: 984,
      );
    }

    test('the plan puts both records\' windows on screen, per slot', () {
      final workspace = PanelWorkspace()
        ..applyPlan(planOf(['attached/operative', 'host/appointments']));

      expect(workspace.isOpen('operative', slot: kAttachedSlot), isTrue);
      expect(workspace.isOpen('appointments', slot: kHostSlot), isTrue);
      expect(workspace.isOpen('operative', slot: kHostSlot), isFalse,
          reason: 'the same window id in the other slot is a different window');
      expect(workspace.openIn(kAttachedSlot), ['operative']);
      expect(workspace.openIn(kHostSlot), ['appointments']);
    });

    test('row order is the visit nearest the panel, then the panel\'s record',
        () {
      final workspace = PanelWorkspace()
        ..applyPlan(planOf(['host/appointments', 'attached/operative']));

      expect(workspace.open, ['operative', 'appointments']);
    });

    test('what the user changes is reported with the slot it happened in', () {
      final reported = <String>[];
      final workspace = PanelWorkspace(
        onUserChange: (slot, open) => reported.add('$slot:${open.join(",")}'),
      )..applyPlan(planOf(
          ['attached/operative', 'host/appointments'],
          widths: const {
            'attached/operative': 350,
            'attached/labwork': 350,
            'host/appointments': 350,
          },
        ));

      workspace.toggle('labwork', slot: kAttachedSlot);
      workspace.minimize('appointments');

      expect(reported, [
        'attached:operative,labwork',
        'host:',
      ]);
    });

    test('detaching a record takes its windows away and keeps the rest', () {
      final workspace = PanelWorkspace()
        ..applyPlan(planOf(['attached/operative', 'host/appointments']));

      workspace.clearSlot(kAttachedSlot);

      expect(workspace.open, ['appointments']);
      expect(workspace.openIn(kAttachedSlot), isEmpty);
    });

    test('a phone shows one window of either record', () {
      final workspace = PanelWorkspace()
        ..applyPlan(planOf(const [], compact: true));

      workspace.toggle('appointments');
      workspace.toggle('operative', slot: kAttachedSlot);

      expect(workspace.open, ['operative']);
    });

    test('a phone keeps the sheet the user opened when the screen re-plans',
        () {
      final workspace = PanelWorkspace()
        ..applyPlan(planOf(const [], compact: true));
      workspace.toggle('operative', slot: kAttachedSlot);

      // A rotation or the keyboard: the screen changed, not the user's choice.
      workspace.applyPlan(planOf(const [], compact: true));

      expect(workspace.open, ['operative'],
          reason: 'a plan that names no window has no window to take away');
    });

    test('opening from the dock moves the row over to make room by width', () {
      // 350 + 12 + 960 = 1322 of 1550; a third 350 doesn't fit, so the
      // window at the row's far end gives way.
      final workspace = PanelWorkspace()
        ..applyPlan(planOf(
          ['host/appointments', 'host/dentalChart'],
          widths: const {
            'host/appointments': 350,
            'host/dentalChart': 960,
            'host/gallery': 350,
          },
        ));

      workspace.toggle('gallery');

      expect(workspace.isOpen('gallery'), isTrue);
      expect(workspace.isOpen('dentalChart'), isFalse,
          reason: 'the row gave up the window at its far end');
      expect(workspace.isOpen('appointments'), isTrue,
          reason: 'the window nearer the panel kept its place');
    });
  });
}

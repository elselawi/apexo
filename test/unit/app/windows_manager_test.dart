import 'package:apexo/ui/workspace/floating_window.dart';
import 'package:apexo/ui/workspace/panel_window.dart';
import 'package:apexo/ui/workspace/window_origin.dart';
import 'package:apexo/ui/workspace/windows_manager.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

PanelWindow window(String id) => PanelWindow(
      id: id,
      title: 'patientDetails',
      icon: const IconData(0xe000),
      body: const SizedBox.shrink(),
    );

FloatingWindow floating(String id,
        {String scope = '', bool Function()? hasChanges}) =>
    FloatingWindow(
      window: window(id),
      scope: scope,
      hasChanges: hasChanges,
      onClose: () {},
    );

void main() {
  setUp(() {
    WindowsManager.closeAll();
    // The pointer is the app's own: a test that leaves one behind places the
    // next window where an earlier tap was.
    WindowOrigin.clear();
  });
  tearDown(() {
    WindowsManager.closeAll();
    WindowOrigin.clear();
  });

  test('one window per editor per record, and asking again brings it forward',
      () {
    final first = floating('labwork', scope: 'appointment:a');
    final second = floating('gallery', scope: 'appointment:a');
    WindowsManager.show(first);
    WindowsManager.show(second);
    expect(WindowsManager.open(), [first, second]);

    // The same editor for the same record is one window, not a second copy,
    // and asking for it again moves it to the front.
    final again = floating('labwork', scope: 'appointment:a');
    WindowsManager.show(again);
    expect(WindowsManager.open(), [second, again]);
    expect(
      WindowsManager.open().last,
      same(again),
      reason: 'a window with nothing typed into it is rebuilt from the record '
          'as it is now',
    );
  });

  test('asking again for a window with unsaved work keeps the draft', () {
    final dirty = floating('labwork',
        scope: 'appointment:a', hasChanges: () => true);
    WindowsManager.show(dirty);

    WindowsManager.show(floating('labwork', scope: 'appointment:a'));
    expect(WindowsManager.open().single, same(dirty));
  });

  test('the same editor for another record is a window of its own', () {
    WindowsManager.show(floating('labwork', scope: 'appointment:a'));
    WindowsManager.show(floating('labwork', scope: 'appointment:b'));
    expect(WindowsManager.open(), hasLength(2));
  });

  test('closing a record closes its windows and nobody else\'s', () {
    WindowsManager.show(floating('labwork', scope: 'appointment:a'));
    WindowsManager.show(floating('gallery', scope: 'appointment:a'));
    final other = floating('chart', scope: 'patient:b');
    WindowsManager.show(other);

    WindowsManager.closeScope('appointment:a');

    expect(WindowsManager.open(), [other]);
    // An empty scope is "belongs to nothing", not "close everything".
    WindowsManager.closeScope('');
    expect(WindowsManager.open(), [other]);
  });

  test('closing a record leaves a window that still has work to lose', () {
    // Opening the record's panel must not be what throws away what was typed
    // into its window: the panel can live with both, a draft cannot.
    final draft = FloatingWindow(
      window: window('chart'),
      scope: 'patient:a',
      onSave: () async {},
      hasChanges: () => true,
      onClose: () {},
    );
    final settled = floating('gallery', scope: 'patient:a');
    WindowsManager.show(draft);
    WindowsManager.show(settled);

    WindowsManager.closeScope('patient:a');

    expect(WindowsManager.open(), [draft]);
  });

  test('a standalone window closes exactly itself', () {
    final first = WindowsManager.showStandalone(window('photo'));
    final second = WindowsManager.showStandalone(window('scan'));

    WindowsManager.close(first);

    expect(WindowsManager.open(), [second]);
    expect(first.standalone, isTrue);
    expect(first.canSave, isFalse, reason: 'a window that only reads');
  });

  test('a standalone window reports the save it was given', () {
    final floating = WindowsManager.showStandalone(
      window('labwork'),
      onSave: () async {},
      hasChanges: () => true,
    );
    expect(floating.canSave, isTrue);
  });
}

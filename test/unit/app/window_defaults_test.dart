/// The device's memory of which of a panel's windows the user left open: one
/// note per kind of record, read back when the next panel of that kind opens.
///
/// Storage is a string here, which is all the class asks for: the settings store
/// is one caller's answer, not a dependency of the class.
library;

import 'dart:convert';

import 'package:apexo/ui/workspace/window_defaults.dart';
import 'package:apexo/ui/workspace/window_group.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late String stored;
  late WindowDefaults defaults;

  setUp(() {
    stored = '';
    defaults = WindowDefaults(
      read: () => stored,
      write: (value) => stored = value,
    );
  });

  test('a kind never left is not remembered at all', () {
    expect(defaults.of('patient'), isNull);
  });

  test('the windows left open are read back in the order they were on screen',
      () {
    defaults.remember('patient', ['dentalChart', 'appointments']);

    expect(defaults.of('patient'), ['dentalChart', 'appointments']);
  });

  test('each kind of panel is remembered on its own', () {
    defaults.remember('patient', ['appointments']);
    defaults.remember('appointment', ['labwork']);

    expect(defaults.of('patient'), ['appointments']);
    expect(defaults.of('appointment'), ['labwork']);
    expect(defaults.of('orders'), isNull);
  });

  test('leaving none open is remembered as none, not as never', () {
    defaults.remember('patient', ['appointments']);
    defaults.remember('patient', const []);

    expect(defaults.of('patient'), isEmpty);
  });

  test('remembering the same windows twice writes nothing new', () {
    defaults.remember('patient', ['appointments']);
    final first = stored;
    defaults.remember('patient', ['appointments']);

    expect(stored, first);
  });

  test('what is remembered is keyed by kind and slot, never by record', () {
    defaults.remember('patient', ['appointments']);
    defaults.remember('appointment', ['operative'], slot: kAttachedSlot);

    expect(
      jsonDecode(stored),
      {
        'patient/host': ['appointments'],
        'appointment/attached': ['operative'],
      },
      reason: 'the visit\'s own id never reaches the memory: every visit of '
          'every patient opens the same way',
    );
  });

  test('a memory written before slots existed is the host slot\'s', () {
    // An upgrade must not rearrange anybody's screen: the entries written by an
    // older build are read as the panel's own slot, and moved on the next write.
    stored = jsonEncode({
      'patient': ['appointments'],
    });

    expect(defaults.of('patient'), ['appointments']);
    expect(defaults.of('patient', kAttachedSlot), isNull);

    defaults.remember('appointment', ['labwork'], slot: kAttachedSlot);
    expect(defaults.of('patient'), ['appointments'],
        reason: 'writing one slot does not drop the legacy one');
  });

  test('the two slots of one kind are remembered apart', () {
    defaults.remember('appointment', ['operative']);
    defaults.remember('appointment', const [], slot: kAttachedSlot);

    expect(defaults.of('appointment'), ['operative']);
    expect(defaults.of('appointment', kAttachedSlot), isEmpty);
  });

  test('remembering one kind keeps the others', () {
    defaults.remember('patient', ['appointments']);
    defaults.remember('orders', ['paid']);

    expect(defaults.of('patient'), ['appointments']);
  });

  test('the list handed back is a copy the caller can keep', () {
    defaults.remember('patient', ['appointments']);
    defaults.of('patient')!.add('labwork');

    expect(defaults.of('patient'), ['appointments']);
  });

  test('the list handed in is copied, not held onto', () {
    final open = ['appointments'];
    defaults.remember('patient', open);
    open.add('labwork');

    expect(defaults.of('patient'), ['appointments']);
  });

  test('nothing remembered when storage holds rubbish', () {
    // A preference is not worth a crash: a panel that cannot read it opens the
    // way it always did.
    for (final rubbish in ['not json', '[]', '{"patient": "appointments"}']) {
      stored = rubbish;
      expect(defaults.of('patient'), isNull);
    }
  });

  test('entries that are not lists of strings are skipped, not fatal', () {
    stored = jsonEncode({
      'patient': ['appointments', 7, null],
      'orders': 'paid',
    });

    expect(defaults.of('patient'), ['appointments']);
    expect(defaults.of('orders'), isNull);
  });

  test('a corrupt note does not stop a later one being written', () {
    stored = 'not json';
    defaults.remember('patient', ['appointments']);

    expect(defaults.of('patient'), ['appointments']);
  });
}

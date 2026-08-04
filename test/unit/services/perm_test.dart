import 'package:apexo/services/perm.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Perm constants', () {
    test('slot indices are correct', () {
      expect(Perm.patients, 0);
      expect(Perm.appointments, 1);
      expect(Perm.postOp, 2);
      expect(Perm.stats, 3);
      expect(Perm.expenses, 4);
      expect(Perm.setting, 5);
      expect(Perm.photos, 6);
      expect(Perm.notes, 7);
      expect(Perm.revenue, 8);
    });

    test('count is 9', () {
      expect(Perm.count, 9);
    });
  });

  group('Perm.zeroes', () {
    test('returns list of 9 zeros', () {
      expect(Perm.zeroes, List.filled(9, 0));
    });

    test('returns a new list each call', () {
      final a = Perm.zeroes;
      final b = Perm.zeroes;
      a[0] = 1;
      expect(b[0], 0);
    });
  });

  group('Perm.full', () {
    test('first 5 slots are 2, rest are 1', () {
      final f = Perm.full;
      expect(f.length, 9);
      expect(f[0], 2); // patients
      expect(f[1], 2); // appointments
      expect(f[2], 2); // postOp
      expect(f[3], 2); // stats
      expect(f[4], 2); // expenses
      expect(f[5], 1); // setting
      expect(f[6], 1); // photos
      expect(f[7], 1); // notes
      expect(f[8], 1); // revenue
    });
  });

  group('Perm.parse', () {
    test('parses valid JSON string', () {
      final result = Perm.parse('[2, 1, 0]');
      expect(result[0], 2);
      expect(result[1], 1);
      expect(result[2], 0);
    });

    test('null source → zeroes', () {
      expect(Perm.parse(null), Perm.zeroes);
    });

    test('empty string → zeroes', () {
      expect(Perm.parse(''), Perm.zeroes);
    });

    test('List<int> source → padded', () {
      final result = Perm.parse([2, 2, 2]);
      expect(result.length, 9);
      expect(result[0], 2);
      expect(result[3], 0); // padded
    });

    test('List<int> longer than count → truncated copy', () {
      final result = Perm.parse(List.filled(12, 1));
      expect(result.length, 12); // pad doesn't truncate, it returns copy
    });

    test('malformed JSON string → zeroes', () {
      expect(Perm.parse('not-json'), Perm.zeroes);
    });

    test('valid JSON but wrong type → zeroes', () {
      expect(Perm.parse('{"a": 1}'), Perm.zeroes);
    });

    test('List<int> already length 9 → unchanged', () {
      final source = [1, 1, 1, 1, 1, 1, 1, 1, 1];
      final result = Perm.parse(source);
      expect(result, source);
    });
  });

  group('Perm.pad', () {
    test('pads short list to 9 elements', () {
      final result = Perm.pad([2, 1]);
      expect(result.length, 9);
      expect(result[0], 2);
      expect(result[1], 1);
      expect(result[2], 0);
      expect(result[8], 0);
    });

    test('list already length 9 → unchanged copy', () {
      final source = [1, 2, 3, 4, 5, 6, 7, 8, 9];
      final result = Perm.pad(source);
      expect(result, source);
      expect(identical(result, source), false); // new list
    });

    test('list longer than 9 → preserved as-is', () {
      final source = List.filled(15, 1);
      final result = Perm.pad(source);
      expect(result.length, 15);
    });

    test('empty list → 9 zeros', () {
      final result = Perm.pad([]);
      expect(result, List.filled(9, 0));
    });
  });

  group('PermLevel', () {
    test('none is true for value 0', () {
      expect(const PermLevel(0).none, true);
      expect(const PermLevel(1).none, false);
      expect(const PermLevel(2).none, false);
    });

    test('some/read is true for value > 0', () {
      expect(const PermLevel(0).some, false);
      expect(const PermLevel(0).read, false);
      expect(const PermLevel(1).some, true);
      expect(const PermLevel(1).read, true);
      expect(const PermLevel(2).some, true);
    });

    test('full is true for value >= 2', () {
      expect(const PermLevel(0).full, false);
      expect(const PermLevel(1).full, false);
      expect(const PermLevel(2).full, true);
      expect(const PermLevel(3).full, true);
    });

    test('exact(n) checks equality', () {
      expect(const PermLevel(0).exact(0), true);
      expect(const PermLevel(0).exact(1), false);
      expect(const PermLevel(1).exact(1), true);
      expect(const PermLevel(2).exact(2), true);
      expect(const PermLevel(2).exact(1), false);
    });

    test('min(n) checks >= n', () {
      expect(const PermLevel(0).min(0), true);
      expect(const PermLevel(0).min(1), false);
      expect(const PermLevel(1).min(1), true);
      expect(const PermLevel(1).min(2), false);
      expect(const PermLevel(2).min(1), true);
      expect(const PermLevel(2).min(2), true);
    });

    test('not(n) checks != n', () {
      expect(const PermLevel(0).not(0), false);
      expect(const PermLevel(0).not(1), true);
      expect(const PermLevel(1).not(0), true);
      expect(const PermLevel(1).not(1), false);
      expect(const PermLevel(2).not(2), false);
      expect(const PermLevel(2).not(0), true);
    });
  });

  group('PermListAccess extension', () {
    test('perm(slot) returns PermLevel for given slot', () {
      final perms = [2, 1, 0, 0, 0, 0, 0, 0, 0];
      expect(perms.perm(Perm.patients).full, true);
      expect(perms.perm(Perm.appointments).some, true);
      expect(perms.perm(Perm.appointments).full, false);
      expect(perms.perm(Perm.expenses).none, true);
    });

    test('perm(slot) works on parsed permissions', () {
      final perms = Perm.parse('[2, 0, 1]');
      expect(perms.perm(Perm.patients).full, true);
      expect(perms.perm(Perm.appointments).none, true);
      expect(perms.perm(Perm.postOp).some, true);
      expect(perms.perm(Perm.expenses).none, true); // padded to 0
    });
  });
}

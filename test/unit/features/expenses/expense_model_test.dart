import 'package:apexo/features/expenses/expense_model.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Expense.fromJson', () {
    test('parses supplier expense', () {
      final e = Expense.fromJson({
        'id': 'exp1',
        'isSupplier': true,
        'supplierName': 'Dental Co.',
        'date': 1700000000000,
        'cost': 500.0,
        'paidAmount': 200.0,
        'notes': 'Preferred supplier',
      });

      expect(e.id, 'exp1');
      expect(e.isSupplier, true);
      expect(e.supplierName, 'Dental Co.');
      expect(e.cost, 500.0);
      expect(e.paidAmount, 200.0);
      expect(e.notes, 'Preferred supplier');
    });

    test('parses order expense', () {
      final e = Expense.fromJson({
        'id': 'ord1',
        'isSupplier': false,
        'supplierId': 'sup1',
        'items': ['Composite kit', 'Gloves'],
        'cost': 150.0,
        'paidAmount': 150.0,
        'processed': true,
      });

      expect(e.isSupplier, false);
      expect(e.supplierId, 'sup1');
      expect(e.items, ['Composite kit', 'Gloves']);
      expect(e.processed, true);
    });

    test('parses date in ms format (> 99999999)', () {
      final e = Expense.fromJson({'date': 1700000000000});
      expect(e.date.millisecondsSinceEpoch, 1700000000000);
    });

    test('parses date in seconds*3600 format (legacy)', () {
      // Seconds * 3600000 → ms
      final e = Expense.fromJson({'date': 472222}); // ~1700000000000 / 3600000
      expect(e.date, isA<DateTime>());
    });

    test('handles missing fields with defaults', () {
      final e = Expense.fromJson({});
      expect(e.isSupplier, false);
      expect(e.supplierName, '');
      expect(e.supplierId, '');
      expect(e.items, isEmpty);
      expect(e.cost, 0.0);
      expect(e.paidAmount, 0.0);
      expect(e.processed, false);
      expect(e.photos, isEmpty);
      expect(e.notes, '');
    });

    test('malformed numeric strings are rejected rather than silently changed',
        () {
      expect(
        () => Expense.fromJson({'cost': 'not-a-number'}),
        throwsFormatException,
      );
      expect(
        () => Expense.fromJson({'paidAmount': 'not-a-number'}),
        throwsFormatException,
      );
    });

    test('negative and fractional money values are preserved', () {
      final expense = Expense.fromJson({
        'cost': -12.50,
        'paidAmount': -2.25,
      });

      expect(expense.cost, -12.50);
      expect(expense.paidAmount, -2.25);
      expect(expense.toJson()['cost'], -12.50);
      expect(expense.toJson()['paidAmount'], -2.25);
    });
  });

  group('Expense.toJson', () {
    test('round-trip preserves data', () {
      final original = Expense.fromJson({
        'id': 'exp1',
        'isSupplier': true,
        'supplierName': 'Dental Co.',
        'date': DateTime(2026, 1, 15).millisecondsSinceEpoch,
        'cost': 500.0,
        'paidAmount': 200.0,
        'photos': ['receipt.jpg'],
        'notes': 'Note',
      });
      final json = original.toJson();
      expect(json['isSupplier'], true);
      expect(json['supplierName'], 'Dental Co.');
      expect(json['cost'], 500.0);
      expect(json['photos'], ['receipt.jpg']);
    });

    test('default collections are omitted while date is always serialized', () {
      final json = Expense.fromJson({'id': 'defaults'}).toJson();

      expect(json.containsKey('items'), isFalse);
      expect(json.containsKey('photos'), isFalse);
      expect(json['date'], isA<int>());
    });
  });

  group('Expense computed getters', () {
    test('isOrder is !isSupplier', () {
      expect(Expense.fromJson({'isSupplier': true}).isOrder, false);
      expect(Expense.fromJson({'isSupplier': false}).isOrder, true);
    });

    test('title format for supplier', () {
      final e = Expense.fromJson({
        'id': 't1',
        'isSupplier': true,
        'supplierName': 'Dental Co.',
      });
      expect(e.title, contains('Dental Co.'));
    });

    test('viewableImgs filters non-image names', () {
      final e = Expense.fromJson({
        'photos': ['photo.jpg', 'doc.pdf', 'scan.png', 'notes.txt'],
      });
      expect(e.viewableImgs, ['photo.jpg', 'scan.png']);
    });

    test('viewableImgs empty when no photos', () {
      final e = Expense.fromJson({});
      expect(e.viewableImgs, isEmpty);
    });

    test('locked depends on permissions', () {
      final original = login.savedPermissions;
      try {
        login.savedPermissions = Perm.zeroes;
        expect(Expense.fromJson({}).locked, isTrue);

        final some = Perm.zeroes;
        some[Perm.expenses] = 1;
        login.savedPermissions = some;
        expect(Expense.fromJson({}).locked, isFalse);
      } finally {
        login.savedPermissions = original;
      }
    });

    test('title distinguishes supplier and order without losing names', () {
      final supplier = Expense.fromJson({
        'isSupplier': true,
        'supplierName': 'Dental Co.',
      });
      final order = Expense.fromJson({
        'isSupplier': false,
        'supplierId': 'supplier-id',
      });

      expect(supplier.title, contains('Dental Co.'));
      expect(order.title, startsWith('Order:'));
    });

    test('copy deep-copies collection fields', () {
      final original = Expense.fromJson({
        'id': 'copy-expense',
        'items': ['gloves'],
        'photos': ['receipt.jpg'],
      });
      final clone = original.copy(false);
      clone.items.add('mask');
      clone.photos.add('second.jpg');

      expect(original.items, ['gloves']);
      expect(original.photos, ['receipt.jpg']);
    });
  });
}

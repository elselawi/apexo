import 'package:apexo/core/observable.dart';
import 'package:apexo/features/expenses/expense_model.dart';
import 'package:apexo/features/expenses/expenses_store.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../helpers/model_factory.dart';

void main() {
  group('Expenses store', () {
    setUp(() {
      expenses.observableMap.clear();
      login.savedPermissions = Perm.full;
    });

    test('singleton is Expenses instance', () {
      expect(expenses, isA<Expenses>());
    });

    test('observableMap is ObservableDict', () {
      expect(expenses.observableMap, isA<ObservableDict<Expense>>());
    });

    test('observableMap values returns list', () {
      expect(expenses.observableMap.values, isA<List<Expense>>());
    });

    test('present returns a map', () {
      expect(expenses.present, isA<Map<String, Expense>>());
    });

    test('amountDue returns a double', () {
      expect(expenses.amountDue, isA<double>());
    });

    test('totalDue returns a double', () {
      expect(expenses.totalDue, isA<double>());
    });

    test('allItems returns a list', () {
      expect(expenses.allItems, isA<List<String>>());
    });

    test('ordersPerSupplier returns a map', () {
      expect(expenses.ordersPerSupplier, isA<Map<String, List<Expense>>>());
    });

    test('allOrders returns a list', () {
      expect(expenses.allOrders, isA<List<Expense>>());
    });

    test('suppliers returns a list', () {
      expect(expenses.suppliers, isA<List<Expense>>());
    });

    test('supplierMap returns a map', () {
      expect(expenses.supplierMap, isA<Map<String, Expense>>());
    });

    test('amountDue and totalDue exclude suppliers and processed orders', () {
      expenses.setAll([
        testExpense(id: 'supplier', isSupplier: true, cost: 1000),
        testExpense(
            id: 'open', supplierId: 'supplier', cost: 200, paidAmount: 50),
        testExpense(id: 'processed', cost: 300, paidAmount: 0, processed: true),
      ]);

      expect(expenses.amountDue, 200);
      expect(expenses.totalDue, 150);
    });

    test('allItems is distinct and cache rebuilds after insertion', () {
      expenses.set(testExpense(id: 'first', items: ['gloves', 'mask']));
      expect(expenses.allItems.toSet(), {'gloves', 'mask'});

      expenses.set(testExpense(id: 'second', items: ['mask', 'syringe']));
      expect(expenses.allItems.toSet(), {'gloves', 'mask', 'syringe'});
    });

    test('suppliers, supplierMap, and ordersPerSupplier group correctly', () {
      final supplierA =
          testExpense(id: 'supplier-a', isSupplier: true, supplierName: 'A');
      final supplierB =
          testExpense(id: 'supplier-b', isSupplier: true, supplierName: 'B');
      final orderA = testExpense(
          id: 'order-a', supplierId: 'supplier-a', date: DateTime(2026, 1, 2));
      final orderB = testExpense(
          id: 'order-b', supplierId: 'supplier-b', date: DateTime(2026, 1, 1));
      expenses.setAll([supplierA, supplierB, orderA, orderB]);

      expect(expenses.supplierMap.keys, {'supplier-a', 'supplier-b'});
      expect(expenses.ordersPerSupplier['supplier-a']!.map((x) => x.id),
          ['order-a']);
      expect(expenses.ordersPerSupplier['supplier-b']!.map((x) => x.id),
          ['order-b']);
      expect(expenses.allOrders.map((x) => x.id),
          containsAllInOrder(['order-a', 'order-b']));
    });

    test('archive filtering removes records from present and derived totals',
        () {
      final order = testExpense(id: 'archived-order', cost: 500);
      expenses.set(order);
      expect(expenses.amountDue, 500);

      expenses.archive(order.id);
      expect(expenses.present, isEmpty);
      expect(expenses.amountDue, 0);
      expect(expenses.totalDue, 0);
    });

    test('cache invalidation rebuilds allOrders after a new order', () {
      expenses.set(testExpense(id: 'one', date: DateTime(2026, 1, 1)));
      expect(expenses.allOrders.map((x) => x.id), ['one']);

      expenses.set(testExpense(id: 'two', date: DateTime(2026, 1, 2)));
      expect(expenses.allOrders.map((x) => x.id), ['two', 'one']);
    });
  });
}

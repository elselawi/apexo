import 'package:apexo/services/ai_services/receipt_scanner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReceiptItem', () {
    test('fromJson parses all fields', () {
      final json = {
        'name': 'Composite Kit',
        'quantity': 2,
        'unitPrice': 45.0,
        'totalPrice': 90.0,
      };

      final item = ReceiptItem.fromJson(json);

      expect(item.name, 'Composite Kit');
      expect(item.quantity, 2);
      expect(item.unitPrice, 45.0);
      expect(item.totalPrice, 90.0);
    });

    test('fromJson handles missing fields with defaults', () {
      final item = ReceiptItem.fromJson({});

      expect(item.name, isEmpty);
      expect(item.quantity, 1);
      expect(item.unitPrice, 0.0);
      expect(item.totalPrice, 0.0);
    });

    test('fromJson handles int/double conversions', () {
      final item = ReceiptItem.fromJson({
        'name': 'Item',
        'quantity': 3,
        'unitPrice': 10,
        'totalPrice': 30,
      });

      expect(item.quantity, 3);
      expect(item.unitPrice, 10.0);
      expect(item.totalPrice, 30.0);
    });

    test('toJson round-trip', () {
      final original = ReceiptItem(
        name: 'Gloves',
        quantity: 5,
        unitPrice: 8.5,
        totalPrice: 42.5,
      );

      final json = original.toJson();
      final restored = ReceiptItem.fromJson(json);

      expect(restored.name, 'Gloves');
      expect(restored.quantity, 5);
      expect(restored.unitPrice, 8.5);
      expect(restored.totalPrice, 42.5);
    });
  });

  group('ReceiptData', () {
    test('fromJson parses all fields', () {
      final json = {
        'supplierName': 'Dental Supplies Co.',
        'orderDate': '2026-01-15',
        'orderItems': [
          {
            'name': 'Composite',
            'quantity': 2,
            'unitPrice': 45.0,
            'totalPrice': 90.0
          },
          {
            'name': 'Gloves',
            'quantity': 5,
            'unitPrice': 8.0,
            'totalPrice': 40.0
          },
        ],
        'totalPrice': 130.0,
      };

      final data = ReceiptData.fromJson(json);

      expect(data.supplierName, 'Dental Supplies Co.');
      expect(data.orderDate, '2026-01-15');
      expect(data.orderItems.length, 2);
      expect(data.orderItems[0].name, 'Composite');
      expect(data.totalPrice, 130.0);
    });

    test('fromJson handles missing fields with defaults', () {
      final data = ReceiptData.fromJson({});

      expect(data.supplierName, 'Unknown');
      expect(data.orderDate, isEmpty);
      expect(data.orderItems, isEmpty);
      expect(data.totalPrice, 0.0);
    });

    test('fromJson handles null orderItems', () {
      final data = ReceiptData.fromJson({'orderItems': null});
      expect(data.orderItems, isEmpty);
    });

    test('toJson round-trip', () {
      final items = [
        ReceiptItem(name: 'A', quantity: 1, unitPrice: 10.0, totalPrice: 10.0),
      ];
      final original = ReceiptData(
        supplierName: 'Supplier',
        orderDate: '2026-01-15',
        orderItems: items,
        totalPrice: 10.0,
      );

      final json = original.toJson();
      final restored = ReceiptData.fromJson(json);

      expect(restored.supplierName, 'Supplier');
      expect(restored.totalPrice, 10.0);
      expect(restored.orderItems.length, 1);
    });

    test('ReceiptScanner class exists', () {
      expect(ReceiptScanner, isNotNull);
    });
  });
}

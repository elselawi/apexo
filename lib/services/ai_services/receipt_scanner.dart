import 'dart:io';
import 'package:apexo/features/expenses/expenses_store.dart';
import 'package:apexo/services/ai_services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

// ============================================================================
//  Models
// ============================================================================

class ReceiptItem {
  final String name;
  final int quantity;
  final double unitPrice;
  final double totalPrice;

  ReceiptItem({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
  });

  factory ReceiptItem.fromJson(Map<String, dynamic> json) => ReceiptItem(
        name: json['name'] as String? ?? '',
        quantity: (json['quantity'] as num?)?.toInt() ?? 1,
        unitPrice: (json['unitPrice'] as num?)?.toDouble() ?? 0.0,
        totalPrice: (json['totalPrice'] as num?)?.toDouble() ?? 0.0,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'quantity': quantity,
        'unitPrice': unitPrice,
        'totalPrice': totalPrice,
      };
}

class ReceiptData {
  final String supplierName;
  final String orderDate;
  final List<ReceiptItem> orderItems;
  final double totalPrice;

  ReceiptData({
    required this.supplierName,
    required this.orderDate,
    required this.orderItems,
    required this.totalPrice,
  });

  factory ReceiptData.fromJson(Map<String, dynamic> json) => ReceiptData(
        supplierName: json['supplierName'] as String? ?? 'Unknown',
        orderDate: json['orderDate'] as String? ?? '',
        orderItems: (json['orderItems'] as List<dynamic>?)
                ?.map((e) => ReceiptItem.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        totalPrice: (json['totalPrice'] as num?)?.toDouble() ?? 0.0,
      );
}

// ============================================================================
//  ReceiptScanner — uses the shared AIService token management
// ============================================================================

class ReceiptScanner extends AIService {
  /// Reads a receipt from an [XFile] (works on web + native).
  static Future<ReceiptData> readReceiptFromXFile(XFile xFile) async {
    return _sendImage(await xFile.readAsBytes());
  }

  /// Extracts only item names from a remote image URL.
  static Future<List<String>> extractItemsFromUrl(String imageUrl) async {
    final bytes = await _downloadBytes(imageUrl);
    return _extractItemsFromBytes(bytes);
  }

  // ── Internal ────────────────────────────────────────────────────────────

  static Future<List<int>> _downloadBytes(String url) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('Failed to download image (${response.statusCode})');
    }
    return response.bodyBytes;
  }

  /// Sends image bytes to the Worker for full receipt parsing.
  static Future<ReceiptData> _sendImage(List<int> bytes) async {
    final r = await AIService.createMultipartRequest('expense');

    // Pass existing supplier names so the AI can match the receipt
    final supplierNames = expenses.suppliers
        .map((s) => s.supplierName)
        .where((n) => n.isNotEmpty)
        .toList();
    if (supplierNames.isNotEmpty) {
      r.fields['suppliers'] = supplierNames.join(',');
    }

    r.files.add(
      http.MultipartFile.fromBytes('image', bytes, filename: 'receipt.jpg'),
    );
    final res = await http.Response.fromStream(await r.send());
    return AIService.parseResponse(res, ReceiptData.fromJson);
  }

  /// Sends image bytes to the Worker in items-only mode.
  static Future<List<String>> _extractItemsFromBytes(List<int> bytes) async {
    final r = await AIService.createMultipartRequest('expense');
    r.fields['mode'] = 'items_only';
    r.files.add(
      http.MultipartFile.fromBytes('image', bytes, filename: 'receipt.jpg'),
    );
    final res = await http.Response.fromStream(await r.send());
    final body = AIService.parseResponse(res, ReceiptData.fromJson);
    return body.orderItems.map((e) => e.name).toList();
  }
}

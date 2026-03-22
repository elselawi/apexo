import 'package:apexo/core/model.dart';
import 'package:apexo/features/expenses/expenses_store.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/utils/constants.dart';

class Expense extends Model {
  @override
  bool get locked {
    return login.permissions[PInt.expenses] == 0;
  }

  bool get isOrder {
    return !isSupplier;
  }

  double get duePayments {
    final items = expenses.present.values.toList();
    double amount = 0;
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item.supplierId != id) continue;
      if (item.processed) continue;
      amount = amount + (item.cost - item.paidAmount);
    }
    return amount;
  }

  // id: id of the expense item (inherited from Model)
  // title: title of the expense item (inherited from Model, useless)

  /* 1 */ bool isSupplier = false;
  /* 2 */ String supplierName = "";

  // when its an order
  /* 3 */ String supplierId = "";
  /* 4 */ DateTime date = DateTime.now();
  /* 5 */ List<String> items = [];
  /* 6 */ double cost = 0;
  /* 7 */ double paidAmount = 0;
  /* 8 */ bool processed = false;
  /* 9 */ List<String> photos = [];

  Expense.fromJson(super.json) : super.fromJson();

  @override
  Expense copy(bool blank) {
    return Expense.fromJson(blank ? {} : toJson());
  }

  @override
  void fromJson(Map<String, dynamic> json) {
    super.fromJson(json);
    /* 1 */ isSupplier = json['isSupplier'] ?? isSupplier;
    /* 2 */ supplierName = json['supplierName'] ?? supplierName;

    /* 3 */ supplierId = json['supplierId'] ?? supplierId;
    /* 4 */ date = json["date"] != null
        ? DateTime.fromMillisecondsSinceEpoch(json["date"] > 99999999
            ? json["date"]
            : json["date"] * 60 * 60 * 1000)
        : date;
    /* 5 */ items = List<String>.from(json["items"] ?? items);
    /* 6 */ cost = double.parse((json["cost"] ?? cost).toString());
    /* 7 */ paidAmount =
        double.parse((json["paidAmount"] ?? paidAmount).toString());
    /* 8 */ processed = json['processed'] ?? processed;
    /* 9 */ photos = List<String>.from(json["photos"] ?? photos);
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    final d = Expense.fromJson({});
    /* 1 */ if (isSupplier != d.isSupplier) json['isSupplier'] = isSupplier;
    /* 2 */ if (supplierName != d.supplierName) {
      json['supplierName'] = supplierName;
    }

    /* 3 */ if (supplierId != d.supplierId) json['supplierId'] = supplierId;
    /* 4 */ json['date'] = date.millisecondsSinceEpoch;
    /* 5 */ if (items.isNotEmpty) json['items'] = items;
    /* 6 */ if (cost != d.cost) json['cost'] = cost;
    /* 7 */ if (paidAmount != d.paidAmount) json['paidAmount'] = paidAmount;
    /* 8 */ if (processed != d.processed) json['processed'] = processed;
    /* 9 */ if (photos.isNotEmpty) json['photos'] = photos;

    return json;
  }
}

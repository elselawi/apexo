import 'package:apexo/features/login/login_controller.dart';
import 'package:apexo/services/launch.dart';
import 'package:apexo/services/network.dart';
import 'package:apexo/utils/hash.dart';
import 'package:apexo/utils/demo_generator.dart';
import '../../core/save_local.dart';
import '../../core/save_remote.dart';
import '../network_actions/network_actions_controller.dart';
import '../../services/login.dart';
import 'expense_model.dart';
import '../../core/store.dart';

const _storeName = "expenses";

class Expenses extends Store<Expense> {
  Expenses()
      : super(
          modeling: Expense.fromJson,
          isDemo: launch.isDemo,
          onSyncStart: () {
            networkActions.isSyncing(networkActions.isSyncing() + 1);
          },
          onSyncEnd: () {
            networkActions.isSyncing(networkActions.isSyncing() - 1);
          },
        );

  @override
  init() {
    super.init();
    observableMap.observe((_) => nullifyExpensesCache());

    login.activators[_storeName] = () async {
      await loaded;

      local = SaveLocal(name: _storeName, uniqueId: simpleHash(login.url));
      await deleteMemoryAndLoadFromPersistence();
      if (launch.isDemo) {
        if (docs.isEmpty) setAll(demoExpenses(100));
      } else {
        remote = SaveRemote(
          pbInstance: login.pb!,
          storeName: _storeName,
          onOnlineStatusChange: (current) {
            if (network.isOnline() != current) {
              network.isOnline(current);
            }
          },
        );
      }
      return () async {
        loginCtrl.loadingIndicator("Synchronizing expenses");
        await synchronize();
        networkActions.syncCallbacks[_storeName] = synchronize;
        networkActions.reconnectCallbacks[_storeName] = remote!.checkOnline;

        network.onOnline[_storeName] = synchronize;
        network.onOffline[_storeName] = cancelRealtimeSub;
      };
    };
  }

  void nullifyExpensesCache() {
    _cachedAllItems = null;
    _cachedSuppliers = null;
    _cachedSupplierMap = null;
    _cachedOrdersPerSupplier = null;
    _cachedTotalDue = null;
  }

  List<String>? _cachedAllItems;
  List<Expense>? _cachedSuppliers;

  @override
  void set(Expense item) {
    super.set(item);
    nullifyExpensesCache();
  }

  @override
  void setAll(List<Expense> items) {
    super.setAll(items);
    nullifyExpensesCache();
  }

  double get amountDue {
    double total = 0;
    for (var doc in present.values) {
      if (doc.isOrder && !doc.processed) {
        total += doc.cost;
      }
    }
    return total;
  }

  List<String> get allItems {
    if (_cachedAllItems != null) return _cachedAllItems!;
    Set<String> items = {};
    for (var doc in docs.values) {
      for (var item in doc.items) {
        items.add(item);
      }
    }
    _cachedAllItems = items.toList();
    return _cachedAllItems!;
  }

  double? _cachedTotalDue;
  double get totalDue {
    return _cachedTotalDue ??= present.values
        .where((x) => x.isOrder && x.processed == false)
        .fold<double>(0, (sum, o) => sum + (o.cost - o.paidAmount));
  }

  Map<String, List<Expense>>? _cachedOrdersPerSupplier;
  Map<String, List<Expense>> get ordersPerSupplier {
    return _cachedOrdersPerSupplier ??= {
      for (var supplier in suppliers)
        supplier.id: expenses.present.values
            .where((e) => e.supplierId == supplier.id)
            .toList()
          ..sort((x, y) => y.date.compareTo(x.date))
    };
  }

  List<Expense>? _cachedAllOrders;
  List<Expense> get allOrders {
    return _cachedAllOrders ??= present.values.where((e) => e.isOrder).toList()
      ..sort((x, y) => y.date.compareTo(x.date));
  }

  List<Expense> get suppliers {
    if (_cachedSuppliers != null) return _cachedSuppliers!;
    _cachedSuppliers = expenses.present.values
        .where((e) => e.isSupplier)
        .toList()
      ..sort((x, y) => y.duePayments.compareTo(x.duePayments));
    return _cachedSuppliers!;
  }

  Map<String, Expense>? _cachedSupplierMap;
  Map<String, Expense> get supplierMap {
    if (_cachedSupplierMap != null) return _cachedSupplierMap!;
    _cachedSupplierMap = {
      for (var s in suppliers) s.id: s,
    };
    return _cachedSupplierMap!;
  }
}

final expenses = Expenses();

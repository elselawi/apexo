import 'dart:convert';
import 'package:apexo/app/routes.dart';
import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/money_display.dart';
import 'package:apexo/common_widgets/no_items_found.dart';
import 'package:apexo/common_widgets/screen_command_bar.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/features/expenses/expense_model.dart';
import 'package:apexo/features/expenses/expenses_store.dart';
import 'package:apexo/features/expenses/order_row.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/utils/constants.dart';
import 'package:apexo/utils/flyout_focus_fix.dart';
import 'package:fluent_ui/fluent_ui.dart' hide TextBox;

// NOTE: Unlike other panels (patient, appointment) which track unsaved
// changes on a single item, this panel manages multiple orders. It uses
// [checkUnsavedChanges] and [onSave] callbacks so the panel's footer Save
// button saves ALL changed orders at once. New orders are persisted
// immediately in [addOrderForSupplier] so photo uploads work right away.
// Archive/restore is handled per-order via the more menu in [OrderRow].
Future<Expense> openExpenses(
    List<Expense> orders, String supplierName, String? supplierId) {
  // Snapshot of each order's JSON at panel-open time.
  // Updated after each save so we only re-save what changed.
  final Map<String, String> savedSnapshots = {
    for (var o in orders) o.id: jsonEncode(o.toJson()),
  };

  final panel = Panel<Expense>(
    showTitles: true,
    showBottomControls: true,
    inherentlyScrollable: true,
    singularName: "orders",
    unicodeSymbol: "📁",
    selectedTabIndex: 0,
    item: Expense.fromJson({"id": supplierName}),
    store: expenses,
    icon: WindowsIcons.folder,
    title: supplierName,
    canNotBeNew: true,
    archiveButtonReplacement: const SizedBox.shrink(),
    additionalControls: _SupplierOrdersFooter(orders: orders),
    checkUnsavedChanges: () {
      return orders.any((o) => jsonEncode(o.toJson()) != savedSnapshots[o.id]);
    },
    onSave: () {
      for (var o in orders) {
        final current = jsonEncode(o.toJson());
        if (current != savedSnapshots[o.id]) {
          expenses.set(o);
          savedSnapshots[o.id] = current;
        }
      }
    },
    tabs: [
      PanelTab(
        title: txt("due"),
        icon: WindowsIcons.warning,
        body: _SupplierDetails(
            allOrders: orders, supplierId: supplierId, processed: false),
        padding: 0,
      ),
      PanelTab(
        title: txt("paid"),
        icon: WindowsIcons.check_mark,
        body: _SupplierDetails(
            allOrders: orders, supplierId: supplierId, processed: true),
        padding: 0,
      ),
    ],
  );
  routes.openPanel(panel);
  return panel.result.future;
}

class _SupplierDetails extends StatefulWidget {
  const _SupplierDetails({
    required this.allOrders,
    required this.processed,
    required this.supplierId,
  });

  final List<Expense> allOrders;
  final bool processed;
  final String? supplierId;

  @override
  State<_SupplierDetails> createState() => _SupplierDetailsState();
}

class _SupplierDetailsState extends State<_SupplierDetails> {
  final _searchOrderController = TextEditingController();
  final _scrollController = ScrollController();
  final pickSupplierForAdditionFlyout = FlyoutController();
  final bool canEdit = login.permissions[PInt.expenses] == 2;
  String? justCreatedId;

  addOrderForSupplier(String supplierId) async {
    final expense = Expense.fromJson({
      "supplierId": supplierId,
      "processed": widget.processed,
    });

    expenses.set(expense);
    widget.allOrders.insert(0, expense);
    justCreatedId = expense.id;

    await Future.delayed(const Duration(milliseconds: 100));
    if (_scrollController.hasClients) {
      await _scrollController.animateTo(
        _scrollController.position.minScrollExtent,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _searchOrderController.dispose();
    _scrollController.dispose();
    pickSupplierForAdditionFlyout.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final search = _searchOrderController.text.toLowerCase();
    final orders = (widget.processed
            ? widget.allOrders.where((e) => e.processed == true).toList()
            : widget.allOrders.where((e) => e.processed == false).toList())
        .where((e) =>
            e.archived != true &&
            e.items.join("").toLowerCase().contains(search))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return MStreamBuilder(
        streams: [expenses.observableMap.stream],
        builder: (context, asyncSnapshot) {
          return Column(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: FluentTheme.of(context)
                      .resources
                      .solidBackgroundFillColorBase,
                  border: Border(
                    bottom: BorderSide(
                        color: FluentTheme.of(context)
                            .resources
                            .dividerStrokeColorDefault),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(5.0),
                  child: Row(
                    spacing: 3,
                    children: [
                      Expanded(
                        child: TopSearch(
                            controller: _searchOrderController,
                            setState: setState),
                      ),
                      if (canEdit)
                        FlyoutTarget(
                          controller: pickSupplierForAdditionFlyout,
                          child: Button(
                            child: ButtonContent(
                                WindowsIcons.add, txt("addOrder")),
                            onPressed: () async {
                              if (widget.supplierId == null) {
                                await flyoutFocusFix(context);
                                pickSupplierForAdditionFlyout.showFlyout(
                                    builder: (ctx) {
                                  return MenuFlyout(
                                    items: expenses.suppliers
                                        .map((e) => MenuFlyoutItem(
                                              text: Text(e.supplierName),
                                              leading: const Icon(
                                                  WindowsIcons.folder),
                                              onPressed: () {
                                                setState(() {
                                                  addOrderForSupplier(e.id);
                                                });
                                              },
                                            ))
                                        .toList(),
                                  );
                                });
                              } else {
                                setState(() {
                                  addOrderForSupplier(widget.supplierId!);
                                });
                              }
                            },
                          ),
                        )
                    ],
                  ),
                ),
              ),
              orders.isEmpty
                  ? const NoItemsFound()
                  : Expanded(
                      child: ListView.separated(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(10),
                        itemCount: orders.length,
                        separatorBuilder: (context, index) {
                          return const SizedBox(height: 10);
                        },
                        itemBuilder: (context, index) {
                          final order = orders[index];
                          return OrderRow(
                            order: order,
                            key: ValueKey(order.id),
                            justCreated: order.id == justCreatedId,
                          );
                        },
                      ),
                    ),
            ],
          );
        });
  }
}

class _SupplierOrdersFooter extends StatefulWidget {
  const _SupplierOrdersFooter({required this.orders});

  final List<Expense> orders;

  @override
  State<_SupplierOrdersFooter> createState() => _SupplierOrdersFooterState();
}

class _SupplierOrdersFooterState extends State<_SupplierOrdersFooter> {
  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final currency = globalSettings.get("currency").value;
    return StreamBuilder(
        stream: expenses.observableMap.stream,
        builder: (context, asyncSnapshot) {
          // Calculations moved inside the builder so they react to store changes
          final double totalDue = widget.orders
              .where((e) => e.processed == false)
              .fold(0, (sum, order) => sum + (order.cost - order.paidAmount));

          final double totalPaid = widget.orders
              .where((e) => e.processed == true)
              .fold(0, (a, b) => a + b.paidAmount);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    txt("totalDue"),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: theme.typography.caption?.color,
                    ),
                  ),
                  const SizedBox(width: 16),
                  MoneyDisplay(
                    "${totalDue.toStringAsFixed(2)} $currency",
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      color: totalDue > 0
                          ? Colors.orange
                          : theme.typography.body?.color,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    txt("totalPayments"),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: theme.typography.caption?.color,
                    ),
                  ),
                  const SizedBox(width: 16),
                  MoneyDisplay(
                    "${totalPaid.toStringAsFixed(2)} $currency",
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      color: totalPaid > 0
                          ? Colors.green
                          : theme.typography.body?.color,
                    ),
                  ),
                ],
              ),
            ],
          );
        });
  }
}

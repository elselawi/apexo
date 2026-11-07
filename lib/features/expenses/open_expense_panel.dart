import 'dart:async';
import 'dart:convert';
import 'package:apexo/ui/workspace/panel_accent.dart';
import 'package:apexo/ui/workspace/delegated_panel.dart';
import 'package:apexo/ui/workspace/panel_window.dart';
import 'package:apexo/ui/workspace/panels_manager.dart';
import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/delete_button.dart';
import 'package:apexo/common_widgets/money_display.dart';
import 'package:apexo/common_widgets/no_items_found.dart';
import 'package:apexo/common_widgets/screen_command_bar.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/features/expenses/expense_model.dart';
import 'package:apexo/features/expenses/expense_windows.dart';
import 'package:apexo/widget_keys.dart';
import 'package:apexo/features/expenses/expenses_store.dart';
import 'package:apexo/features/expenses/expense_summary.dart';
import 'package:apexo/features/expenses/order_row.dart';
import 'package:apexo/ui/workspace/windows_manager.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/utils/constants.dart';
import 'package:apexo/utils/flyout_focus_fix.dart';
import 'package:fluent_ui/fluent_ui.dart' hide TextBox;

export 'package:apexo/features/expenses/expense_windows.dart'
    show ExpenseWindow, expenseWindows;

/// The panel's summary body, which is not one of [expenseWindows].
const String expenseSummaryWindowId = 'summary';

// Multi-order panel: the footer Save writes every changed order; new orders are
// stored on creation (so photos can upload), and archive/restore happen per row.
Future<String?> openExpenses(
    List<Expense> orders, String supplierName, String? supplierId,
    [bool? singleArchived, ExpenseWindow? window]) async {
  final itemId = supplierId ?? supplierName;
  // An open panel owns this supplier's windows: a second editor would give the
  // same orders two drafts, and whichever saved last would win.
  final panelIsOpen =
      PanelsManager.active().any((panel) => panel.itemId == itemId);
  if (!panelIsOpen && window != null && window != ExpenseWindow.order) {
    _showOrdersWindow(orders, supplierId, window, supplierName: supplierName);
    return null;
  }
  return _openSupplierPanel(
    orders,
    supplierName,
    supplierId,
    singleArchived: singleArchived,
    focus: window?.id,
  );
}

Future<String?> _openSupplierPanel(
  List<Expense> orders,
  String supplierName,
  String? supplierId, {
  bool? singleArchived,
  String? focus,
}) async {
  // The panel holds this supplier's windows now, so the standalone ones close.
  final scope = _supplierScope(supplierId, supplierName);

  // The panel may already be on screen; building another would be discarded along
  // with the baselines it had adopted, so check before touching window state.
  final itemId = supplierId ?? supplierName;
  final existing = PanelsManager.find(itemId);
  if (existing != null) {
    WindowsManager.showOnPanel(existing, scope: scope, focus: focus);
    await existing.result;
    return existing.savedId;
  }

  // A window's work comes in with the panel: its older baselines make the touched
  // orders dirty here, so the panel's Save is the one write.
  final carried = WindowsManager.adoptBaselines(scope);
  WindowsManager.closeScope(scope);

  // Per-order JSON baseline, re-taken after each save. A carried window baseline
  // wins over the fresh snapshot, so the work it held starts dirty.
  final savedSnapshots = {..._snapshotsOf(orders), ...?carried};
  void remember(Expense order) =>
      savedSnapshots[order.id] = jsonEncode(order.toJson());

  // An order added while the panel was up has no snapshot; it is stored as soon
  // as added, so it is unsaved only when the store's copy differs.
  bool isDirty(Expense order) {
    final snapshot = savedSnapshots[order.id];
    final current = jsonEncode(order.toJson());
    if (snapshot != null) return current != snapshot;
    final stored = expenses.get(order.id);
    return stored == null || jsonEncode(stored.toJson()) != current;
  }

  late final DelegatedPanel panel;
  panel = DelegatedPanel(
    // Key the panel by supplier id when there is one: names can collide, and a
    // rename would orphan a name-keyed panel.
    itemId: itemId,
    initialWindow: focus,
    showBottomControls: true,
    singularName: "orders",
    accent: PanelAccents.orders,
    unicodeSymbol: "📁",
    icon: WindowsIcons.folder,
    recordTitle: () async =>
        _supplierNameOf(supplierId, supplierName),
    liveTitle: () => _supplierNameOf(supplierId, supplierName),
    archiveButtonReplacement: singleArchived == true
        ? DeleteButton(
            onConfirm: () => expenses.unarchive(orders.firstOrNull?.id ?? ""),
            preview: Row(spacing: 5, mainAxisSize: MainAxisSize.min, children: [
              const Icon(FluentIcons.receipt_processing),
              Txt(orders.firstOrNull?.fromSupplierName ?? ""),
              Txt(DF.allNumbers(orders.firstOrNull?.date ?? DateTime.now()))
            ]),
            actionText: txt("restore"),
            actionIcon: WindowsIcons.undo,
            restorable: true,
            style: filledButtonStyle(Colors.teal),
            child: ButtonContent(
                WindowsIcons.undo, "${txt("restore")} ${txt("order")}"),
          )
        : const SizedBox.shrink(),
    checkUnsavedChanges: () => orders.any(isDirty),
    onSave: () async => _saveOrders(orders, savedSnapshots),
    windows: [
      PanelWindow(
        id: expenseSummaryWindowId,
        title: "orders",
        icon: WindowsIcons.folder,
        body: ExpenseSummary(
          orders: orders,
          supplierId: supplierId,
          supplierName: supplierName,
          singleArchived: singleArchived == true,
          onOpenWindow: (id) => panel.workspace.show(id),
        ),
      ),
      for (final entry in expenseWindows(singleArchived: singleArchived))
        _ordersWindow(orders, supplierId, entry,
            supplierName: supplierName, onOrderSaved: remember),
    ],
  );
  await panel.readTitle();
  final shown = PanelsManager.open(panel);
  // The panel is done when the user saves it or closes it without saving.
  await shown.result;
  return shown.savedId;
}

// Read the supplier's current record: a rename writes the supplier, so a captured
// name would go stale in the header and window subtitles.
String _supplierNameOf(String? supplierId, String fallback) {
  if (supplierId == null) return fallback;
  return expenses.get(supplierId)?.supplierName ?? fallback;
}

PanelWindow _ordersWindow(
  List<Expense> orders,
  String? supplierId,
  ExpenseWindow window, {
  required String supplierName,
  void Function(Expense order)? onOrderSaved,
}) {
  // The `order` window is the single archived order, so no totals footer.
  final archived = window == ExpenseWindow.order;
  return PanelWindow(
    id: window.id,
    title: window.titleKey,
    icon: window.icon,
    subtitle: () => _supplierNameOf(supplierId, supplierName),
    padding: 0,
    scrollable: false,
    maxHeight: 640,
    // The orders are edited here, so the panel's write is offered here too.
    editsRecord: true,
    minHeight: 440,
    body: _SupplierDetails(
      allOrders: orders,
      supplierId: supplierId,
      processed: window == ExpenseWindow.paid,
      singleArchived: archived ? true : null,
      onOrderSaved: onOrderSaved,
    ),
    footer: archived ? null : _SupplierOrdersFooter(orders: orders),
  );
}

void _showOrdersWindow(
  List<Expense> orders,
  String? supplierId,
  ExpenseWindow window, {
  required String supplierName,
}) {
  final snapshots = _snapshotsOf(orders);
  void remember(Expense order) =>
      snapshots[order.id] = jsonEncode(order.toJson());
  WindowsManager.showStandalone(
    _ordersWindow(orders, supplierId, window,
        supplierName: supplierName, onOrderSaved: remember),
    // The supplier a panel is opened for names it: the same id the panel uses.
    scope: _supplierScope(supplierId, supplierName),
    onSave: () async {
      _saveOrders(orders, snapshots);
    },
    hasChanges: () =>
        orders.any((o) => jsonEncode(o.toJson()) != snapshots[o.id]),
    // A panel of the same supplier takes the work in with it.
    baselines: () => snapshots,
    onOpenRecord: () async {
      await _openSupplierPanel(
        orders,
        supplierName,
        supplierId,
        focus: window.id,
      );
    },
  );
}

// Standalone windows share this scope with the panel for the same supplier, so
// opening the panel closes them.
String _supplierScope(String? supplierId, String supplierName) =>
    'supplier:${supplierId ?? supplierName}';

Map<String, String> _snapshotsOf(List<Expense> orders) => {
      for (final order in orders) order.id: jsonEncode(order.toJson()),
    };

// Writes the orders changed since `snapshots` and re-baselines each one, so a
// second Save with no edits writes nothing.
List<String> _saveOrders(
  List<Expense> orders,
  Map<String, String> snapshots,
) {
  final saved = <String>[];
  for (final order in orders) {
    final current = jsonEncode(order.toJson());
    if (current != snapshots[order.id]) {
      expenses.set(order);
      snapshots[order.id] = current;
      saved.add(order.id);
    }
  }
  return saved;
}

class _SupplierDetails extends StatefulWidget {
  const _SupplierDetails({
    required this.allOrders,
    required this.processed,
    required this.supplierId,
    this.singleArchived,
    this.onOrderSaved,
  });

  final List<Expense> allOrders;
  final bool processed;
  final String? supplierId;
  final bool? singleArchived;

  // An order was written outside Save (added here or edited in a row), so the
  // owner can re-baseline its dirty check.
  final void Function(Expense order)? onOrderSaved;

  @override
  State<_SupplierDetails> createState() => _SupplierDetailsState();
}

class _SupplierDetailsState extends State<_SupplierDetails> {
  final _searchOrderController = TextEditingController();
  final _scrollController = ScrollController();
  final pickSupplierForAdditionFlyout = FlyoutController();
  final bool canEdit = login.perm(Perm.expenses).exact(2);
  String? justCreatedId;

  Future<void> addOrderForSupplier(String supplierId) async {
    final expense = Expense.fromJson({
      "supplierId": supplierId,
      "processed": widget.processed,
    });

    expenses.set(expense);
    widget.onOrderSaved?.call(expense);
    widget.allOrders.insert(0, expense);
    justCreatedId = expense.id;

    await Future<void>.delayed(const Duration(milliseconds: 100));
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

  // Computed at draw time, not when the window is built: store changes reach this
  // list before `widget.allOrders`, so a snapshot would keep showing stale rows.
  List<Expense> ordersFor(String search) {
    if (widget.singleArchived == true) return widget.allOrders;
    return (widget.processed
            ? widget.allOrders.where((e) => e.processed == true)
            : widget.allOrders.where((e) => e.processed == false))
        .where((e) =>
            e.archived != true &&
            e.items.join("").toLowerCase().contains(search))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  @override
  Widget build(BuildContext context) {
    return MStreamBuilder(
        streams: [expenses.observableMap.stream],
        builder: (context, asyncSnapshot) {
          final orders = ordersFor(_searchOrderController.text.toLowerCase());
          return Column(
            children: [
              if (widget.singleArchived != true)
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
                              key: WK.btnAddOrder,
                              child: ButtonContent(
                                  WindowsIcons.add, txt("addOrder")),
                              onPressed: () async {
                                if (widget.supplierId == null) {
                                  await flyoutFocusFix(context);
                                  unawaited(pickSupplierForAdditionFlyout
                                      .showFlyout(builder: (ctx) {
                                    return MenuFlyout(
                                      items: expenses.suppliers
                                          .map((e) => MenuFlyoutItem(
                                                text: Text(e.supplierName),
                                                leading: const Icon(
                                                    WindowsIcons.folder),
                                                onPressed: () {
                                                  unawaited(addOrderForSupplier(
                                                      e.id));
                                                },
                                              ))
                                          .toList(),
                                    );
                                  }));
                                } else {
                                  unawaited(
                                      addOrderForSupplier(widget.supplierId!));
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
                            onSaved: () =>
                                widget.onOrderSaved?.call(order),
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
    final currency = globalSettings.currency;
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: StreamBuilder(
          stream: expenses.observableMap.stream,
          builder: (context, asyncSnapshot) {
            // The same totals the panel's summary uses, so both agree.
            final totals = OrderTotals.of(widget.orders);
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
                      "${totals.outstanding.toStringAsFixed(2)} $currency",
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        color: totals.outstanding > 0
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
                      "${totals.paid.toStringAsFixed(2)} $currency",
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        color: totals.paid > 0
                            ? Colors.green
                            : theme.typography.body?.color,
                      ),
                    ),
                  ],
                ),
              ],
            );
          }),
    );
  }
}

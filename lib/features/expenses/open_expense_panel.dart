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

/// The windows the orders panel offers beside it, in the order it offers them.
///
/// The panel builds its list from [expenseWindows] and a supplier row's context
/// menu offers one item per entry, so neither can drift from the other. The
/// supplier's own figures stay in the panel; the orders live in these windows.
export 'package:apexo/features/expenses/expense_windows.dart'
    show ExpenseWindow, expenseWindows;

/// The id of the panel's own body: the supplier's figures, which are not one of
/// the floating windows.
const String expenseSummaryWindowId = 'summary';

// NOTE: Unlike the row panels (patient, appointment) which track unsaved
// changes on a single item, this panel manages multiple orders. It is a
// [DelegatedPanel]: its [checkUnsavedChanges] and [onSave] callbacks make the
// panel's footer Save button save ALL changed orders at once. New orders are
// persisted immediately in [addOrderForSupplier] so photo uploads work right
// away. Archive/restore is handled per-order via the more menu in [OrderRow].
Future<String?> openExpenses(
    List<Expense> orders, String supplierName, String? supplierId,
    [bool? singleArchived, ExpenseWindow? window]) async {
  final itemId = supplierId ?? supplierName;
  // A window of a supplier whose panel is already open is that panel's window:
  // a second editor for the same orders would let the two disagree about what
  // was saved, and the one saved last would win.
  final panelIsOpen =
      PanelsManager.active().any((panel) => panel.itemId == itemId);
  // A window that is not the panel's own body opens on its own: asking a
  // supplier row for "the unpaid orders" should not unfold the supplier.
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

/// The supplier's own panel, led by their figures and offering their order lists
/// beside them — [focus] is the window the caller asked for, if any.
Future<String?> _openSupplierPanel(
  List<Expense> orders,
  String supplierName,
  String? supplierId, {
  bool? singleArchived,
  String? focus,
}) async {
  // The panel holds these windows now, so the ones standing on their own for
  // this supplier have nothing left to show.
  final scope = _supplierScope(supplierId, supplierName);

  // The supplier's panel may already be on screen. Then this is not a new
  // panel: the editor is already there, and a panel built here would be thrown
  // away — taking the baselines it had adopted with it, silently. So the
  // question is asked *before* any window state is touched.
  final itemId = supplierId ?? supplierName;
  final existing = PanelsManager.find(itemId);
  if (existing != null) {
    WindowsManager.showOnPanel(existing, scope: scope, focus: focus);
    await existing.result;
    return existing.savedId;
  }

  // Work a window of this supplier still holds comes in with the panel: the
  // panel takes the baselines the window opened with, so the orders it touched
  // are dirty here and its own Save is the one write.
  final carried = WindowsManager.adoptBaselines(scope);
  WindowsManager.closeScope(scope);

  // Snapshot of each order's JSON at panel-open time.
  // Updated after each save so we only re-save what changed. A window's older
  // baseline wins over a snapshot taken now — that is what makes the panel start
  // dirty on the work the window was holding.
  final savedSnapshots = {..._snapshotsOf(orders), ...?carried};
  void remember(Expense order) =>
      savedSnapshots[order.id] = jsonEncode(order.toJson());

  /// Whether [order] differs from what the panel last knew of it.
  ///
  /// An order the panel did not see when it opened was added while the panel
  /// was up — and such an order is written to the store as soon as it is
  /// added, so it is only unsaved work when the store's copy differs from it.
  bool isDirty(Expense order) {
    final snapshot = savedSnapshots[order.id];
    final current = jsonEncode(order.toJson());
    if (snapshot != null) return current != snapshot;
    final stored = expenses.get(order.id);
    return stored == null || jsonEncode(stored.toJson()) != current;
  }

  late final DelegatedPanel panel;
  panel = DelegatedPanel(
    // The supplier the panel is about, named by its id when there is one: two
    // suppliers can share a name, and a rename must not leave the panel under an
    // id nothing else can find again.
    itemId: itemId,
    // The window the caller asked for — a menu that names "the unpaid orders"
    // means that window, not just the supplier it belongs to.
    initialWindow: focus,
    showBottomControls: true,
    singularName: "orders",
    accent: PanelAccents.orders,
    unicodeSymbol: "📁",
    icon: WindowsIcons.folder,
    // The header keeps the supplier's name — as it is *now*: a rename writes the
    // supplier's own record, and the header must follow it.
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
          // The figures are a way into the orders behind them: on a phone,
          // where only one window is on screen at a time, the lists are
          // otherwise a click away and no one would know it.
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

/// The supplier's name as it is now.
///
/// A rename writes the supplier's own record, so a name captured when the panel
/// was opened would keep showing the old one — in the header, and in the line
/// under a window's title.
String _supplierNameOf(String? supplierId, String fallback) {
  if (supplierId == null) return fallback;
  return expenses.get(supplierId)?.supplierName ?? fallback;
}

/// One supplier's orders as a window — the panel's, or one standing on its own
/// when a row or a menu names it.
PanelWindow _ordersWindow(
  List<Expense> orders,
  String? supplierId,
  ExpenseWindow window, {
  required String supplierName,
  void Function(Expense order)? onOrderSaved,
}) {
  // The single-order window a supplier-less list opens (an archived order) is
  // the one that has no running totals to speak of.
  final archived = window == ExpenseWindow.order;
  return PanelWindow(
    id: window.id,
    title: window.titleKey,
    icon: window.icon,
    // Whose orders these are: the panel may be a supplier's, or the whole
    // clinic's — several such windows can be open at once. The name is read
    // when the window is drawn, so a rename shows up in it.
    subtitle: () => _supplierNameOf(supplierId, supplierName),
    padding: 0,
    scrollable: false,
    maxHeight: 640,
    // The orders are edited here, so the panel's write is offered here too.
    editsRecord: true,
    // A list of orders: enough room for a few of them, and it scrolls itself for
    // the rest. Too short and the window is all header and one row.
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

/// Shows one of a supplier's order lists on its own, with the Save and Close a
/// panel would have offered — the orders are edited in place, so it needs both.
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

/// The record a supplier's standalone windows belong to, named the way a panel
/// names the supplier it edits: opening the panel closes the windows it holds.
String _supplierScope(String? supplierId, String supplierName) =>
    'supplier:${supplierId ?? supplierName}';

Map<String, String> _snapshotsOf(List<Expense> orders) => {
      for (final order in orders) order.id: jsonEncode(order.toJson()),
    };

/// Writes every order that changed since [snapshots] was taken, and re-baselines
/// it. Answering with the ids it wrote is what makes the panel's `savedId` mean
/// something: this panel's caller holds the drafts, so it is the only one that
/// can report them.
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

  /// An order was written on the spot — added here, or edited in a row — so the
  /// owner's dirty check can be re-baselined without a Save.
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

  @override
  Widget build(BuildContext context) {
    final search = _searchOrderController.text.toLowerCase();
    final orders = widget.singleArchived == true
        ? widget.allOrders
        : (widget.processed
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
            // The same figures the panel's summary shows, computed the same way:
            // the panel and the window beside it must not report two different
            // numbers for the same orders.
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

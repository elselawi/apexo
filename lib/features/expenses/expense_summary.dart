import 'package:apexo/common_widgets/money_display.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/features/expenses/expense_actions.dart';
import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/features/expenses/expense_model.dart';
import 'package:apexo/features/expenses/expense_windows.dart';
import 'package:apexo/features/expenses/expenses_store.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// A supplier's order totals; the orders themselves stay in their own windows.
class ExpenseSummary extends StatelessWidget {
  const ExpenseSummary({
    super.key,
    required this.orders,
    required this.supplierName,
    this.supplierId,
    this.singleArchived = false,
    this.onOpenWindow,
  });

  final List<Expense> orders;

  /// Null means the whole clinic's orders, which belong to no supplier.
  final String? supplierId;

  /// Snapshot name; the live supplier record wins while it still exists.
  final String supplierName;

  /// Covers one archived order, which the totals would otherwise skip.
  final bool singleArchived;

  /// Opens the order list behind a figure, by id; null leaves figures inert.
  final void Function(String windowId)? onOpenWindow;

  /// What the orders add up to — the same figures the windows' footers show.
  OrderTotals get _totals =>
      OrderTotals.of(orders, singleArchived: singleArchived);

  @override
  Widget build(BuildContext context) {
    // Orders are edited in other windows, so the figures must follow the store.
    return MStreamBuilder(
      streams: [expenses.observableMap.stream],
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSupplierLine(context),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _SummaryTile(
                key: WK.expenseSummaryDue,
                icon: WindowsIcons.warning,
                label: txt('due'),
                value:
                    '${_totals.outstanding.toStringAsFixed(2)} ${globalSettings.currency}',
                color: Colors.orange,
                onPressed: onOpenWindow == null
                    ? null
                    : () => onOpenWindow!(ExpenseWindow.due.id),
              ),
              _SummaryTile(
                key: WK.expenseSummaryPaid,
                icon: WindowsIcons.check_mark,
                label: txt('paid'),
                value: '${_totals.paid.toStringAsFixed(2)} ${globalSettings.currency}',
                color: Colors.teal,
                onPressed: onOpenWindow == null
                    ? null
                    : () => onOpenWindow!(ExpenseWindow.paid.id),
              ),
              _SummaryTile(
                icon: FluentIcons.receipt_processing,
                label: txt('orders'),
                value: _totals.count.toString(),
                color: FluentTheme.of(context).accentColor,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Resolved by id, not from [orders]: a supplier with no orders is still a
  /// supplier, and null means the clinic's own orders.
  Expense? get _supplier {
    final id = supplierId;
    if (id == null) return null;
    return expenses.get(id);
  }

  Widget _buildSupplierLine(BuildContext context) {
    final theme = FluentTheme.of(context);
    final supplier = _supplier;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Txt(
                supplier?.supplierName ?? supplierName,
                style: theme.typography.subtitle
                    ?.copyWith(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
              Txt(
                txt(singleArchived ? 'archived' : 'orders'),
                style: theme.typography.caption
                    ?.copyWith(color: theme.inactiveColor),
              ),
            ],
          ),
        ),
        if (supplier != null)
          Button(
            key: WK.editSupplierName,
            onPressed: () => renameSupplierDialog(context, supplier.id),
            child: ButtonContent(WindowsIcons.edit, txt('rename'), size: 13),
          ),
      ],
    );
  }
}

/// One totals computation shared by the panel and the window footers, so the
/// same orders are never reported two different ways.
class OrderTotals {
  const OrderTotals({
    required this.outstanding,
    required this.paid,
    required this.count,
  });

  /// Archived orders are skipped unless [singleArchived]; an order paid above
  /// its cost contributes zero, never a negative amount.
  factory OrderTotals.of(
    List<Expense> orders, {
    bool singleArchived = false,
  }) {
    var outstanding = 0.0;
    var paid = 0.0;
    var count = 0;
    for (final order in orders) {
      if (!singleArchived && order.archived == true) continue;
      outstanding += (order.cost - order.paidAmount).clamp(0, 1e9);
      paid += order.paidAmount;
      count++;
    }
    return OrderTotals(outstanding: outstanding, paid: paid, count: count);
  }

  /// What is still owed.
  final double outstanding;

  /// What has been paid.
  final double paid;

  /// How many orders there are.
  final int count;
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.onPressed,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  /// Null for the order-count tile, which has no single list behind it.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final tile = Container(
      constraints: const BoxConstraints(minWidth: 132),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.resources.solidBackgroundFillColorBase,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.resources.dividerStrokeColorDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Txt(
                label,
                style: theme.typography.caption?.copyWith(
                  color: theme.inactiveColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          MoneyDisplay(
            value,
            style: theme.typography.subtitle?.copyWith(
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    final onPressed = this.onPressed;
    if (onPressed == null) return tile;
    // On a phone the lists are off-screen, so the figure is the way into them.
    return Tooltip(
      message: txt('showOrders'),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onPressed,
          child: tile,
        ),
      ),
    );
  }
}

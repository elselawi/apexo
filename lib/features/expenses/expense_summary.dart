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

/// What a supplier's orders add up to, and the one thing a summary is good for:
/// renaming them.
///
/// The panel keeps this in front of the user — what is owed and what has been
/// paid — and leaves the orders themselves to the windows beside it, so the
/// panel is never a second copy of the lists.
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

  /// The supplier these orders belong to, by id — null for the whole clinic's
  /// orders, which belong to no one supplier.
  final String? supplierId;

  /// The supplier's name, as it was when the panel opened. The line below
  /// prefers the name the supplier's own record holds now.
  final String supplierName;

  /// A single archived order: it has no running totals to speak of, so the
  /// figures describe that order alone.
  final bool singleArchived;

  /// Opens the window that lists the orders behind a figure, by the window's
  /// own id.
  ///
  /// The figures are a summary of orders the user cannot see from here — on a
  /// phone, where only one window is on screen at a time, the order lists are
  /// a click away. So the figures are the way in.
  final void Function(String windowId)? onOpenWindow;

  /// What the orders add up to — the same figures the windows' footers show.
  OrderTotals get _totals =>
      OrderTotals.of(orders, singleArchived: singleArchived);

  @override
  Widget build(BuildContext context) {
    // The orders these add up are edited in the windows beside the panel, so
    // the figures follow the store the way the lists do.
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

  /// The supplier these orders belong to: one record, so one name and one place
  /// a rename is written to.
  ///
  /// Null when the panel is about the whole clinic's orders — where the panel's
  /// own title is the right name and there is nothing to rename. The supplier
  /// is named by its id, not worked out from the orders: a supplier with no
  /// orders at all is still a supplier, and the clinic's orders are nobody's.
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

/// What a set of orders adds up to.
///
/// One computation for the panel's summary and for the windows' footers: the
/// same orders must never be reported two different ways — a panel and the
/// window beside it showing two different totals for one supplier is a number
/// the user cannot explain.
class OrderTotals {
  const OrderTotals({
    required this.outstanding,
    required this.paid,
    required this.count,
  });

  /// The figures of [orders]: what is still owed on them, what has been paid
  /// on them, and how many there are.
  ///
  /// Archived orders are left out — they are history, not a position — unless
  /// [singleArchived] says this is about the one archived order on its own.
  ///
  /// What is owed is never negative: an order that was paid more than it cost
  /// owes nothing, and must not make the total smaller than it is.
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

  /// Opens the list behind the figure. Null for a figure with no list — the
  /// number of orders, which is the two lists together.
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
    // The figure is a way into the orders behind it: on a phone, where only
    // one window is on screen at a time, they are otherwise a click away and
    // no one would know it.
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

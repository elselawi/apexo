import 'package:fluent_ui/fluent_ui.dart';

/// The windows the orders panel offers beside it, in the order it offers them.
///
/// The panel builds its list from [expenseWindows] and a supplier row's context
/// menu offers one item per entry, so neither can drift from the other. The
/// supplier's own figures stay in the panel; the orders live in these windows.
enum ExpenseWindow {
  order('order', "order", FluentIcons.receipt_processing),
  due('due', "due", WindowsIcons.warning),
  paid('paid', "paid", FluentIcons.check_mark);

  const ExpenseWindow(this.id, this.titleKey, this.icon);

  /// The window's [PanelWindow.id], for panels and openers to name it by.
  final String id;

  final String titleKey;
  final IconData icon;
}

/// The windows this panel floats: a single archived order has one, a supplier's
/// live orders have due and paid.
List<ExpenseWindow> expenseWindows({bool? singleArchived}) =>
    singleArchived == true
        ? [ExpenseWindow.order]
        : [ExpenseWindow.due, ExpenseWindow.paid];

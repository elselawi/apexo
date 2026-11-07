import 'package:fluent_ui/fluent_ui.dart';

/// The order-list windows the orders panel offers; [expenseWindows] is the one
/// list the panel and a supplier row's menu both build from.
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

List<ExpenseWindow> expenseWindows({bool? singleArchived}) =>
    singleArchived == true
        ? [ExpenseWindow.order]
        : [ExpenseWindow.due, ExpenseWindow.paid];

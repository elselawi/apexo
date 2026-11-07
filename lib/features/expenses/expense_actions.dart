import 'dart:async';

import 'package:apexo/common_widgets/dialogs/dialog_with_text_box.dart';
import 'package:apexo/features/expenses/expenses_store.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// Renaming is one write: orders point at the supplier by id, not by name.
Future<void> renameSupplierDialog(
  BuildContext context,
  String supplierID,
) async {
  final supplier = expenses.get(supplierID);
  if (supplier == null) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    dismissWithEsc: true,
    builder: (context) => DialogWithTextBox(
      title: txt("rename"),
      initialValue: supplier.supplierName,
      onSave: (String name) {
        expenses.set(supplier..supplierName = name);
      },
      icon: FluentIcons.edit,
    ),
  );
}

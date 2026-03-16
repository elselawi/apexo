import 'package:apexo/common_widgets/dialogs/dialog_with_text_box.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/features/expenses/expense_model.dart';
import 'package:apexo/features/expenses/folder_widget.dart';
import 'package:apexo/features/expenses/supplier_window_widget.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/archived.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/common_widgets/archive_toggle.dart';
import 'package:apexo/features/expenses/expenses_store.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/utils/constants.dart';
import 'package:apexo/utils/flyout_focus_fix.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';

class ExpensesScreen extends StatelessWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      key: WK.expensesScreen,
      padding: EdgeInsets.zero,
      resizeToAvoidBottomInset: true,
      content: Column(
        children: [
          Expanded(
            child: MStreamBuilder(
                streams: [expenses.observableMap.stream, showArchived.stream],
                // ignore: prefer_const_constructors
                builder: (context, snapshot) => SuppliersAndOrders()),
          ),
        ],
      ),
    );
  }
}

class SuppliersAndOrders extends StatefulWidget {
  const SuppliersAndOrders({super.key});

  @override
  State<SuppliersAndOrders> createState() => _SuppliersAndOrdersState();
}

class _SuppliersAndOrdersState extends State<SuppliersAndOrders> {
  Expense? selectedSupplier;
  FlyoutController addOrderFlyout = FlyoutController();

  @override
  Widget build(BuildContext context) {
    final due = expenses.amountDue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildCommandBar(),
        if (selectedSupplier != null)
          _buildInvoicesWindow()
        else ...[
          _buildSuppliersFolders(context, expenses.suppliers),
          InfoBar(
            title: Txt("${txt("due")}:"),
            content:
                Text("$due ${globalSettings.get("currency_______").value}"),
            severity: due == 0 ? InfoBarSeverity.info : InfoBarSeverity.warning,
          ),
        ]
      ],
    );
  }

  Expanded _buildInvoicesWindow() {
    return Expanded(
      child: Padding(
        padding:
            EdgeInsets.fromLTRB(0, selectedSupplier != null ? 0 : 500, 0, 0),
        child: SupplierWindow(
          orders: expenses.present.values
              .where((o) =>
                  (!o.isSupplier) && o.supplierId == selectedSupplier?.id)
              .toList(),
          supplier: selectedSupplier!,
          onClose: () {
            setState(() {
              selectedSupplier = null;
            });
          },
        ),
      ),
    );
  }

  Widget _buildSuppliersFolders(BuildContext context, List<Expense> suppliers) {
    return Expanded(
      child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 85,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          padding: const EdgeInsets.all(15),
          itemCount: suppliers.length,
          itemBuilder: (ctx, i) {
            final supplier = suppliers[i];
            return Folder(
              key: Key(supplier.id),
              isArchived: supplier.archived ?? false,
              icon: FluentIcons.shop,
              title: supplier.supplierName,
              subtitle:
                  "${supplier.duePayments} ${globalSettings.get("currency_______").value}",
              color: supplier.archived == true
                  ? Colors.grey.toAccentColor().lightest.toAccentColor()
                  : supplier.duePayments > 0
                      ? Colors.yellow.toAccentColor().lightest.toAccentColor()
                      : Colors.yellow
                          .toAccentColor()
                          .lightest
                          .toAccentColor()
                          .lightest
                          .toAccentColor(),
              onOpen: () => setState(() => selectedSupplier = supplier),
              onRename: (newName) {
                setState(() {
                  expenses.set(supplier..supplierName = newName);
                });
              },
              onArchive: () => setState(() {
                expenses
                    .set(supplier..archived = !(supplier.archived ?? false));
              }),
            );
          }),
    );
  }

  Widget _buildCommandBar() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            offset: const Offset(0.0, 6.0),
            blurRadius: 30.0,
            spreadRadius: 5.0,
            color: Colors.grey.withAlpha(50),
          )
        ],
        color: FluentTheme.of(context).menuColor,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          login.permissions[PInt.expenses] == 1
              ? const SizedBox()
              : selectedSupplier == null
                  ? _buildAddSupplierButton()
                  : _buildAddOrderButton(),
          const ArchiveToggle(),
        ],
      ),
    );
  }

  Widget _buildAddOrderButton() {
    return FlyoutTarget(
      controller: addOrderFlyout,
      child: IconButton(
        onPressed: () async {
          await flyoutFocusFix(context);
          addOrderFlyout.showFlyout(builder: (context) {
            return MenuFlyout(
              items: [
                MenuFlyoutItem(
                  text: Txt(txt("unpaid")),
                  leading: const Icon(FluentIcons.file_request),
                  onPressed: () {
                    expenses.set(Expense.fromJson({
                      "supplierId": selectedSupplier!.id,
                      "processed": false,
                    }));
                  },
                ),
                MenuFlyoutItem(
                  text: Txt(txt("paid")),
                  leading: const Icon(FluentIcons.fabric_folder_confirm),
                  onPressed: () {
                    expenses.set(Expense.fromJson({
                      "supplierId": selectedSupplier!.id,
                      "processed": true,
                    }));
                  },
                ),
              ],
            );
          });
        },
        icon: Row(
          children: [
            const Icon(
              FluentIcons.add_notes,
              size: 17,
            ),
            const SizedBox(width: 10),
            Txt(txt("addOrder"))
          ],
        ),
      ),
    );
  }

  Widget _buildAddSupplierButton() {
    return IconButton(
      onPressed: () {
        showDialog(
          barrierDismissible: true,
          dismissWithEsc: true,
          context: context,
          builder: (context) {
            return DialogWithTextBox(
              title: "${txt("addSupplier")}: ${txt("name")}",
              onSave: (supplierNewName) {
                expenses.set(
                  Expense.fromJson({
                    "isSupplier": true,
                    "supplierName": supplierNewName,
                  }),
                );
              },
              icon: FluentIcons.fabric_new_folder,
            );
          },
        );
      },
      icon: Row(
        children: [
          const Icon(
            FluentIcons.fabric_new_folder,
            size: 17,
          ),
          const SizedBox(width: 10),
          Txt(txt("addSupplier"))
        ],
      ),
    );
  }
}

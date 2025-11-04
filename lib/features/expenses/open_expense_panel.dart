import 'package:apexo/app/routes.dart';
import 'package:apexo/common_widgets/operators_picker.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/common_widgets/call_button.dart';
import 'package:apexo/common_widgets/date_time_picker.dart';
import 'package:apexo/common_widgets/tag_input.dart';
import 'package:apexo/features/expenses/expense_model.dart';
import 'package:apexo/features/expenses/expenses_store.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/cupertino.dart';

void openExpense([Expense? expense]) {
  final editingCopy = Expense.fromJson(expense?.toJson() ?? {});

  routes.openPanel(Panel(
    item: editingCopy,
    store: expenses,
    icon: FluentIcons.receipt_processing,
    title: expenses.get(editingCopy.id) == null ? txt("newReceipt") : editingCopy.title,
    tabs: [
      PanelTab(
        title: txt("receipt"),
        icon: FluentIcons.receipt_processing,
        body: _ReceiptEditing(editingCopy),
      ),
    ],
  ));
}

class _ReceiptEditing extends StatefulWidget {
  final Expense expense;

  const _ReceiptEditing(this.expense);

  @override
  State<_ReceiptEditing> createState() => _ReceiptEditingState();
}

class _ReceiptEditingState extends State<_ReceiptEditing> {
  final TextEditingController issuerController = TextEditingController();
  final TextEditingController issuerPhoneController = TextEditingController();

  @override
  void initState() {
    super.initState();
    issuerController.text = widget.expense.issuer;
    issuerPhoneController.text = widget.expense.phoneNumber;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InfoLabel(
          label: "${txt("date")}:",
          child: DateTimePicker(
            key: WK.fieldReceiptDate,
            initValue: widget.expense.date,
            onChange: (d) => widget.expense.date = d,
            buttonText: txt("changeDate"),
          ),
        ),
        InfoLabel(
          label: "${txt("specificForDoctors")}:",
          child: OperatorsPicker(
              value: widget.expense.operatorsIDs,
              onChanged: (ids) {
                widget.expense.operatorsIDs = ids;
              }),
        ),
        InfoLabel(
          label: "${txt("receiptItems")}:",
          isHeader: true,
          child: TagInputWidget(
            key: WK.fieldReceiptItems,
            suggestions: expenses.allItems.map((t) => TagInputItem(value: t, label: t)).toList(),
            onChanged: (items) {
              widget.expense.items = List<String>.from(items.map((e) => e.value).where((e) => e != null));
            },
            initialValue: widget.expense.items.map((e) => TagInputItem(value: e, label: e)).toList(),
            strict: false,
            limit: 9999,
            placeholder: "${txt("receiptItems")}...",
          ),
        ),
        InfoLabel(
          label: "${txt("receiptNotes")}:",
          child: CupertinoTextField(
            key: WK.fieldReceiptNotes,
            controller: TextEditingController(text: widget.expense.note),
            placeholder: "${txt("receiptNotes")}...",
            onChanged: (val) {
              widget.expense.note = val;
            },
            maxLines: null,
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: InfoLabel(
                label: "${txt("amountIn")} ${globalSettings.get("currency_______").value}",
                child: NumberBox(
                  key: WK.fieldReceiptAmount,
                  style: textFieldTextStyle(),
                  clearButton: false,
                  mode: SpinButtonPlacementMode.inline,
                  value: widget.expense.amount,
                  onChanged: (n) => widget.expense.amount = n ?? 0.0,
                ),
              ),
            ),
            const SizedBox(width: 15),
            Padding(
              padding: const EdgeInsets.only(top: 22.5),
              child: Checkbox(
                key: WK.fieldReceiptPaidToggle,
                checked: widget.expense.paid,
                onChanged: (n) {
                  setState(() {
                    widget.expense.paid = n == true;
                  });
                },
                content: widget.expense.paid ? Txt(txt("paid")) : Txt(txt("due")),
              ),
            )
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: InfoLabel(
                label: "${txt("issuer")}:",
                child: AutoSuggestBox<String>(
                  key: WK.fieldReceiptIssuer,
                  style: textFieldTextStyle(),
                  decoration: WidgetStatePropertyAll(textFieldDecoration()),
                  clearButtonEnabled: false,
                  placeholder: "${txt("issuer")}...",
                  controller: issuerController,
                  noResultsFoundBuilder: (context) => Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Txt(txt("noSuggestions")),
                  ),
                  onChanged: (text, reason) {
                    widget.expense.issuer = text;
                    String? phoneNumber = expenses.getPhoneNumber(text);
                    if (phoneNumber != null) {
                      issuerPhoneController.text = phoneNumber;
                      widget.expense.phoneNumber = phoneNumber;
                    }
                  },
                  items:
                      expenses.allIssuers.map((name) => AutoSuggestBoxItem<String>(value: name, label: name)).toList(),
                ),
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: InfoLabel(
                label: "${txt("phone")}:",
                child: AutoSuggestBox<String>(
                  key: WK.fieldLabworkPhoneNumber,
                  style: textFieldTextStyle(),
                  decoration: WidgetStatePropertyAll(textFieldDecoration()),
                  clearButtonEnabled: false,
                  placeholder: "${txt("phone")}...",
                  controller: issuerPhoneController,
                  noResultsFoundBuilder: (context) => Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Txt(txt("noSuggestions")),
                  ),
                  onChanged: (text, reason) {
                    widget.expense.phoneNumber = text;
                  },
                  trailingIcon: CallIconButton(phoneNumber: widget.expense.phoneNumber),
                  items: expenses.allPhones.map((pn) => AutoSuggestBoxItem<String>(value: pn, label: pn)).toList(),
                ),
              ),
            ),
          ],
        ),
        InfoLabel(
          label: "${txt("receiptTags")}:",
          isHeader: true,
          child: TagInputWidget(
            key: WK.fieldReceiptTags,
            suggestions: expenses.allTags.map((t) => TagInputItem(value: t, label: t)).toList(),
            onChanged: (tags) {
              widget.expense.tags = List<String>.from(tags.map((e) => e.value).where((e) => e != null));
            },
            initialValue: widget.expense.tags.map((e) => TagInputItem(value: e, label: e)).toList(),
            strict: false,
            limit: 9999,
            placeholder: "${txt("receiptTags")}...",
          ),
        ),
      ].map((e) => [e, const SizedBox(height: 10)]).expand((e) => e).toList(),
    );
  }
}

BoxDecoration textFieldDecoration() {
  return BoxDecoration(
    borderRadius: BorderRadius.circular(5),
    border: Border.all(color: const Color.fromARGB(255, 192, 192, 192)),
  );
}

TextStyle textFieldTextStyle() {
  return const TextStyle(
    fontSize: 16,
  );
}

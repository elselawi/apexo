import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/confirm_delete_flyout.dart';
import 'package:apexo/common_widgets/dialogs/dialog_styling.dart';
import 'package:apexo/features/notes/notes_model.dart';
import 'package:apexo/features/notes/notes_store.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/utils/flyout_focus_fix.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/cupertino.dart';

final _archiveFlyoutCtrl = FlyoutController();

void showColumnEditDialog(BuildContext context, {Note? column}) {
  final controller = TextEditingController(text: column?.columnName ?? "");
  Color? selectedColor = column?.computedTint;
  showDialog(
    context: context,
    dismissWithEsc: true,
    barrierDismissible: true,
    builder: (context) => ContentDialog(
      style: dialogStyling(context, false, true),
      title: Row(
        spacing: 8,
        children: [
          Icon(column == null ? FluentIcons.add : FluentIcons.rename),
          Txt(column == null ? txt("addColumn") : txt("editColumn")),
        ],
      ),
      content: SizedBox(
        width: 312,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InfoLabel(
              label: txt("columnTitle"),
              isHeader: true,
              child: CupertinoTextField(
                controller: controller,
                placeholder: "${txt("columnTitle")}...",
                autofocus: true,
              ),
            ),
            if (column != null) ...[
              const SizedBox(height: 10),
              const Divider(),
              const SizedBox(height: 10),
              InfoLabel(
                label: txt("columnColor"),
                isHeader: true,
                child: ColorPicker(
                  color: selectedColor ?? column.computedTint,
                  onChanged: (color) => selectedColor = color,
                  isAlphaEnabled: false,
                  isMoreButtonVisible: false,
                  colorSpectrumShape: ColorSpectrumShape.ring,
                  isHexInputVisible: false,
                  isAlphaSliderVisible: false,
                  isColorSliderVisible: false,
                  isAlphaTextInputVisible: false,
                  isColorChannelTextInputVisible: false,
                  minSaturation: 40,
                ),
              )
            ]
          ],
        ),
      ),
      actions: [
        FilledButton(
          style: filledButtonStyle(Colors.grey),
          child: ButtonContent(WindowsIcons.cancel, txt("cancel")),
          onPressed: () => Navigator.pop(context),
        ),
        if (column != null)
          FlyoutTarget(
            controller: _archiveFlyoutCtrl,
            child: FilledButton(
                style: filledButtonStyle(
                  column.archived == true
                      ? Colors.teal
                      : Colors.errorPrimaryColor,
                ),
                child: ButtonContent(
                  column.archived == true
                      ? FluentIcons.archive_undo
                      : FluentIcons.archive,
                  column.archived == true ? txt("restore") : txt("archive"),
                ),
                onPressed: () async {
                  await flyoutFocusFix(context);
                  _archiveFlyoutCtrl.showFlyout(builder: (ctx) {
                    return ConfirmDeleteFlyout(
                      controller: _archiveFlyoutCtrl,
                      onConfirm: () {
                        if (column.archived == true) {
                          notes.unarchive(column.id);
                        } else {
                          notes.archive(column.id);
                        }
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          Navigator.pop(context);
                        });
                      },
                      actionText:
                          column.archived == true ? "restore" : "archive",
                      actionIcon: column.archived == true
                          ? FluentIcons.archive_undo
                          : FluentIcons.archive,
                    );
                  });
                }),
          ),
        FilledButton(
          style: filledButtonStyle(Colors.blue),
          child: ButtonContent(
              WindowsIcons.save, column == null ? txt("add") : txt("save")),
          onPressed: () {
            if (controller.text.isNotEmpty) {
              if (column == null) {
                final newColumn = Note.fromJson({})
                  ..columnName = controller.text
                  ..isColumn = true
                  ..order = notes.columns.length.toDouble();
                notes.set(newColumn);
              } else {
                column.columnName = controller.text;
                column.tint = selectedColor;
                notes.set(column);
              }
              Navigator.pop(context);
            }
          },
        ),
      ],
    ),
  );
}

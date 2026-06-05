import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/confirm_delete_flyout.dart';
import 'package:apexo/common_widgets/dialogs/dialog_styling.dart';
import 'package:apexo/common_widgets/keyboard_aware.dart';
import 'package:apexo/features/notes/notes_model.dart';
import 'package:apexo/features/notes/notes_store.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/utils/flyout_focus_fix.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/cupertino.dart';

void showColumnEditDialog(BuildContext context, {Note? column}) {
  showDialog(
    context: context,
    dismissWithEsc: true,
    barrierDismissible: true,
    builder: (context) => _ColumnEditingWidget(column: column),
  );
}

class _ColumnEditingWidget extends StatefulWidget {
  final Note? column;
  const _ColumnEditingWidget({
    required this.column,
  });

  @override
  State<_ColumnEditingWidget> createState() => _ColumnEditingWidgetState();
}

class _ColumnEditingWidgetState extends State<_ColumnEditingWidget> {
  final controller = TextEditingController();
  Color? selectedColor;

  @override
  void initState() {
    super.initState();
    if (widget.column != null) {
      controller.text = widget.column!.columnName;
      selectedColor = widget.column!.computedTint;
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardAwareView(
      child: ContentDialog(
        style: dialogStyling(context, false, true),
        title: Row(
          spacing: 8,
          children: [
            Icon(widget.column == null ? FluentIcons.add : FluentIcons.rename),
            Txt(widget.column == null ? txt("addColumn") : txt("editColumn")),
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
              if (widget.column != null) ...[
                const SizedBox(height: 10),
                const Divider(),
                const SizedBox(height: 10),
                InfoLabel(
                  label: txt("columnColor"),
                  isHeader: true,
                  child: ColorPicker(
                    color: selectedColor ?? widget.column!.computedTint,
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
          if (widget.column != null)
            _ArchiveColumnButton(column: widget.column!),
          FilledButton(
            style: filledButtonStyle(Colors.blue),
            child: ButtonContent(WindowsIcons.save,
                widget.column == null ? txt("add") : txt("save")),
            onPressed: () {
              if (controller.text.isNotEmpty) {
                if (widget.column == null) {
                  final newColumn = Note.fromJson({})
                    ..columnName = controller.text
                    ..isColumn = true
                    ..order = notes.columns.length.toDouble();
                  notes.set(newColumn);
                } else {
                  widget.column!.columnName = controller.text;
                  widget.column!.tint = selectedColor;
                  notes.set(widget.column!);
                }
                Navigator.pop(context);
              }
            },
          ),
        ],
      ),
    );
  }
}

class _ArchiveColumnButton extends StatefulWidget {
  final Note column;
  const _ArchiveColumnButton({required this.column});

  @override
  State<_ArchiveColumnButton> createState() => _ArchiveColumnButtonState();
}

class _ArchiveColumnButtonState extends State<_ArchiveColumnButton> {
  final _archiveFlyoutCtrl = FlyoutController();

  @override
  void dispose() {
    _archiveFlyoutCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FlyoutTarget(
      controller: _archiveFlyoutCtrl,
      child: FilledButton(
          style: filledButtonStyle(
            widget.column.archived == true
                ? Colors.teal
                : Colors.errorPrimaryColor,
          ),
          child: ButtonContent(
            widget.column.archived == true
                ? FluentIcons.archive_undo
                : FluentIcons.archive,
            widget.column.archived == true ? txt("restore") : txt("archive"),
          ),
          onPressed: () async {
            await flyoutFocusFix(context);
            _archiveFlyoutCtrl.showFlyout(builder: (ctx) {
              return ConfirmDeleteFlyout(
                controller: _archiveFlyoutCtrl,
                onConfirm: () {
                  if (widget.column.archived == true) {
                    notes.unarchive(widget.column.id);
                  } else {
                    notes.archive(widget.column.id);
                  }
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    Navigator.pop(context);
                  });
                },
                actionText:
                    widget.column.archived == true ? "restore" : "archive",
                actionIcon: widget.column.archived == true
                    ? FluentIcons.archive_undo
                    : FluentIcons.archive,
              );
            });
          }),
    );
  }
}

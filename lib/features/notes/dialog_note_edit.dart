import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/confirm_delete_flyout.dart';
import 'package:apexo/common_widgets/date_time_picker.dart';
import 'package:apexo/common_widgets/dialogs/dialog_styling.dart';
import 'package:apexo/common_widgets/keyboard_aware.dart';
import 'package:apexo/common_widgets/patient_picker.dart';
import 'package:apexo/common_widgets/tag_input.dart';
import 'package:apexo/features/accounts/accounts_controller.dart';
import 'package:apexo/features/notes/note_attachments_widget.dart';
import 'package:apexo/features/notes/notes_model.dart';
import 'package:apexo/features/notes/notes_store.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/utils/flyout_focus_fix.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

void showNoteEditDialog(BuildContext context, {Note? note, String? columnID}) {
  showDialog(
    context: context,
    dismissWithEsc: true,
    barrierDismissible: true,
    builder: (context) => NoteEditDialog(note: note, columnID: columnID),
  );
}

class NoteEditDialog extends StatefulWidget {
  final Note? note;
  final String? columnID;

  const NoteEditDialog({super.key, this.note, this.columnID});

  @override
  State<NoteEditDialog> createState() => _NoteEditDialogState();
}

class _NoteEditDialogState extends State<NoteEditDialog> {
  late final TextEditingController titleController;
  late final TextEditingController noteController;
  late final TextEditingController recurrenceIntervalController;
  final _archiveFlyoutCtrl = FlyoutController();

  late bool isDone;
  late DateTime dueDate;
  late String assignedTo;
  late String selectedColumnID;
  late String forPatient;
  late bool isRecurringChecked;
  bool titleIsEmpty = false;

  @override
  void initState() {
    super.initState();
    titleController = TextEditingController(text: widget.note?.title ?? "");
    noteController = TextEditingController(text: widget.note?.note ?? "");
    recurrenceIntervalController = TextEditingController(
      text: widget.note?.parent?.recurringInterval?.toString() ??
          widget.note?.recurringInterval?.toString() ??
          "90",
    );
    isDone = widget.note?.done ?? false;
    dueDate = widget.note?.dueDate ?? DateTime.now();
    assignedTo = widget.note?.assignedTo ?? "";
    selectedColumnID = widget.note?.columnID ?? widget.columnID ?? "";
    forPatient = widget.note?.forPatient ?? "";
    isRecurringChecked =
        widget.note?.parent?.isRecurring ?? widget.note?.isRecurring ?? false;
  }

  @override
  void dispose() {
    titleController.dispose();
    noteController.dispose();
    recurrenceIntervalController.dispose();
    _archiveFlyoutCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final note = widget.note;
    final theme = FluentTheme.of(context);

    return KeyboardAwareView(
      child: ContentDialog(
        style: dialogStyling(context, false, true),
        title: Txt(note == null ? txt("addNote") : txt("editNote")),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 10,
              children: [
                ComboBox<String>(
                  value: selectedColumnID.isEmpty ? '' : selectedColumnID,
                  items: [
                    ComboBoxItem(value: '', child: Txt(txt("uncategorized"))),
                    ...notes.columns.map((column) => ComboBoxItem(
                        value: column.id, child: Text(column.columnName))),
                  ],
                  onChanged: (value) =>
                      setState(() => selectedColumnID = value ?? ''),
                ),
                CupertinoTextField(
                  placeholderStyle: TextStyle(
                    color: (titleIsEmpty ? Colors.red : Colors.black)
                        .withAlpha(100),
                  ),
                  suffix: titleIsEmpty
                      ? Padding(
                          padding: const EdgeInsetsDirectional.only(end: 10),
                          child: Icon(WindowsIcons.warning, color: Colors.red),
                        )
                      : null,
                  controller: titleController,
                  placeholder: "${txt("title")}...",
                ),
                CupertinoTextField(
                  controller: noteController,
                  placeholder: "${txt("note")}...",
                  maxLines: 3,
                ),
                Column(
                  children: [
                    if (note?.isRecurringInstance == true)
                      Txt(
                        txt("isARecurrenceOfOlderNote"),
                        style: TextStyle(
                            fontStyle: FontStyle.italic,
                            backgroundColor: theme.inactiveBackgroundColor),
                      ),
                    const SizedBox(height: 3),
                    Row(spacing: 5, children: [
                      Checkbox(
                        checked: isRecurringChecked,
                        onChanged: (checked) {
                          if (checked == true) {
                            recurrenceIntervalController.text = "90";
                          }
                          setState(() {
                            isRecurringChecked = checked ?? false;
                          });
                        },
                        content: Txt(
                            isRecurringChecked
                                ? txt("recurringEvery")
                                : txt("recurring"),
                            style: theme.typography.bodyStrong),
                      ),
                      if (isRecurringChecked)
                        Expanded(
                          child: CupertinoTextField(
                            suffix: Padding(
                              padding: const EdgeInsetsDirectional.only(end: 3),
                              child: Txt(txt("day")),
                            ),
                            controller: recurrenceIntervalController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            maxLength: 3,
                            maxLines: 1,
                            textAlign: TextAlign.end,
                          ),
                        )
                    ])
                  ],
                ),
                InfoLabel(
                  label: "${txt("relatingToPatient")}:",
                  child: PatientPicker(
                    onChanged: (id) {
                      forPatient = id ?? "";
                    },
                    value: forPatient.isEmpty ? null : forPatient,
                  ),
                ),
                InfoLabel(
                  label: "${txt("assignedTo")}:",
                  child: TagInputWidget(
                    suggestions: accounts
                        .list()
                        .map((account) => TagInputItem(
                            value: account.id, label: accounts.name(account)))
                        .toList(),
                    onChanged: (s) {
                      setState(() => assignedTo = s
                              .where((x) => x.value != null)
                              .map((x) => x.value!)
                              .toList()
                              .firstOrNull ??
                          "");
                    },
                    initialValue: assignedTo.isEmpty
                        ? []
                        : [
                            TagInputItem(
                                value: assignedTo,
                                label: accounts.nameOrEmailFromID(assignedTo))
                          ],
                    strict: true,
                    limit: 1,
                    placeholder: "${txt("assignedTo")}...",
                  ),
                ),
                InfoLabel(
                  label: "${txt("dueDate")}:",
                  child: DateTimePicker(
                    initValue: dueDate,
                    onChange: (value) => setState(() => dueDate = value),
                    pickTime: false,
                    showButton: true,
                  ),
                ),
                if (note != null && !note.isGhost)
                  InfoLabel(
                    label: "${txt("attachments")}:",
                    child: NoteAttachmentsWidget(note: note),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            style: filledButtonStyle(Colors.grey),
            child: ButtonContent(WindowsIcons.cancel, txt("cancel")),
            onPressed: () => Navigator.pop(context),
          ),
          if (note != null)
            FlyoutTarget(
              controller: _archiveFlyoutCtrl,
              child: FilledButton(
                  style: filledButtonStyle(
                    note.archived == true
                        ? Colors.teal
                        : Colors.errorPrimaryColor,
                  ),
                  child: ButtonContent(
                    note.archived == true
                        ? FluentIcons.archive_undo
                        : FluentIcons.archive,
                    note.archived == true ? txt("restore") : txt("archive"),
                  ),
                  onPressed: () async {
                    await flyoutFocusFix(context);
                    _archiveFlyoutCtrl.showFlyout(builder: (ctx) {
                      return ConfirmDeleteFlyout(
                        controller: _archiveFlyoutCtrl,
                        onConfirm: () {
                          if (note.archived == true) {
                            notes.unarchive(note.id);
                          } else {
                            notes.archive(note.id);
                          }
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            Navigator.pop(context);
                          });
                        },
                        actionText:
                            note.archived == true ? "restore" : "archive",
                        actionIcon: note.archived == true
                            ? FluentIcons.archive_undo
                            : FluentIcons.archive,
                      );
                    });
                  }),
            ),
          FilledButton(
            style: filledButtonStyle(Colors.blue),
            child: ButtonContent(
                note == null ? FluentIcons.add_field : WindowsIcons.save,
                txt("save")),
            onPressed: () {
              if (titleController.text.isNotEmpty) {
                if (note == null) {
                  final newNote = Note.fromJson({})
                    ..isColumn = false
                    ..title = titleController.text
                    ..note = noteController.text
                    ..columnID = selectedColumnID
                    ..done = isDone
                    ..dueDate = dueDate
                    ..assignedTo = assignedTo
                    ..createdBy = login.currentAccountID
                    ..recurringInterval = isRecurringChecked
                        ? int.tryParse(recurrenceIntervalController.text)
                        : null
                    ..forPatient = forPatient;
                  notes.set(newNote);
                } else {
                  note
                    ..title = titleController.text
                    ..note = noteController.text
                    ..columnID = selectedColumnID
                    ..done = isDone
                    ..dueDate = dueDate
                    ..assignedTo = assignedTo
                    ..forPatient = forPatient;

                  if (note.parent != null) {
                    if (isRecurringChecked == false) {
                      note.parent!.recurringInterval = null;
                    } else {
                      note.parent!.recurringInterval =
                          int.tryParse(recurrenceIntervalController.text);
                    }
                    notes.set(note.parent!);
                  } else {
                    if (isRecurringChecked) {
                      note.recurringInterval =
                          int.tryParse(recurrenceIntervalController.text);
                    } else {
                      note.recurringInterval = null;
                    }
                  }
                  notes.set(note);
                }
                Navigator.pop(context);
              } else {
                setState(() {
                  titleIsEmpty = true;
                });
              }
            },
          ),
        ],
      ),
    );
  }
}

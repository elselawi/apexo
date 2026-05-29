import 'package:apexo/common_widgets/confirm_delete_flyout.dart';
import 'package:apexo/common_widgets/patient_picker.dart';
import 'package:apexo/common_widgets/small_label.dart';
import 'package:apexo/features/accounts/accounts_controller.dart';
import 'package:apexo/features/notes/note_attachments_widget.dart';
import 'package:apexo/features/notes/notes_model.dart';
import 'package:apexo/features/notes/notes_store.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/utils/constants.dart';
import 'package:apexo/utils/flyout_focus_fix.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show showDatePicker;
import 'package:flutter/services.dart';

class NoteCard extends StatefulWidget {
  final Note note;

  const NoteCard({super.key, required this.note});

  @override
  State<NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends State<NoteCard> with TickerProviderStateMixin {
  final FlyoutController _assigningFlyoutCtrl = FlyoutController();
  final FlyoutController _confirmArchiveFlyoutCtrl = FlyoutController();
  final TextEditingController _commentController = TextEditingController();
  final TextEditingController _recurringIntervalController =
      TextEditingController();
  late final TextEditingController _titleController;
  late final TextEditingController _noteController;
  bool _showTitleSaveButton = false;
  bool _showNoteSaveButton = false;
  bool _commentButtonVisible = false;
  bool expanded = false;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _elevationAnimation;
  late Animation<double> _borderRadiusAnimation;
  late AnimationController _checkBoxScaleAnimationController;
  late Animation<double> _checkboxScaleAnimation;

  @override
  void didUpdateWidget(covariant NoteCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    _recurringIntervalController.text =
        widget.note.recurringInterval?.toString() ?? '';

    if (widget.note.isRecurringInstance) {
      _recurringIntervalController.text =
          widget.note.parent?.recurringInterval?.toString() ?? '';
    }
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);

    _recurringIntervalController.text =
        widget.note.recurringInterval?.toString() ?? '';

    if (widget.note.isRecurringInstance) {
      _recurringIntervalController.text =
          widget.note.parent?.recurringInterval?.toString() ?? '';
    }
  }

  @override
  void initState() {
    super.initState();

    _titleController = TextEditingController(text: widget.note.title);
    _noteController = TextEditingController(text: widget.note.note);

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );

    _scaleAnimation =
        Tween<double>(begin: 1.0, end: 1.04).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.fastOutSlowIn,
    ));

    _elevationAnimation = Tween<double>(
      begin: 0,
      end: 20.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));

    _borderRadiusAnimation = Tween<double>(
      begin: 5.0,
      end: 8.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));

    // Checkbox rotation animation
    _checkBoxScaleAnimationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _checkboxScaleAnimation = Tween<double>(
      begin: 1.5,
      end: 3,
    ).animate(CurvedAnimation(
      parent: _checkBoxScaleAnimationController,
      curve: Curves.easeIn,
    ));
  }

  @override
  void dispose() {
    _animationController.dispose();
    _checkBoxScaleAnimationController.dispose();
    _titleController.dispose();
    _noteController.dispose();
    _assigningFlyoutCtrl.dispose();
    _confirmArchiveFlyoutCtrl.dispose();
    _commentController.dispose();
    _recurringIntervalController.dispose();
    super.dispose();
  }

  bool get canEdit {
    if (login.isAdmin) return true;
    if (login.permissions[PInt.notes] > 0) return true;
    if (widget.note.createdBy == login.currentAccountID) return true;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return RepaintBoundary(
      child: LongPressDraggable<Note>(
        data: widget.note,
        feedback: SizedBox(
          width: 280,
          child: _buildCard(theme, context),
        ),
        childWhenDragging: Opacity(
          opacity: 0.5,
          child: _buildCard(theme, context),
        ),
        child: _buildCard(theme, context),
      ),
    );
  }

  Widget _buildCard(FluentThemeData theme, BuildContext context) {
    final Color borderColor;
    if (widget.note.archived == true) {
      borderColor = theme.inactiveColor;
    } else if (widget.note.overdue) {
      borderColor = Colors.red;
    } else if (widget.note.pending) {
      borderColor = Colors.orange;
    } else if (widget.note.done) {
      borderColor = Colors.successPrimaryColor;
    } else {
      borderColor = theme.inactiveColor;
    }

    return GestureDetector(
      onTap: () {
        if (!expanded) {
          setState(() {
            expanded = true;
            _titleController.text = widget.note.title;
            _noteController.text = widget.note.note;
            _showTitleSaveButton = false;
            _showNoteSaveButton = false;
          });
          _animationController.forward();
        }
      },
      child: AnimatedBuilder(
        animation: _animationController,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              padding: EdgeInsets.fromLTRB(12, 16, 12, expanded ? 12 : 6),
              margin: EdgeInsetsDirectional.only(
                  end: 12, bottom: expanded ? 20 : 6, top: expanded ? 20 : 6),
              decoration: _mainContainerDecoration(theme, borderColor),
              child: child,
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildNoteMainBody(theme),
                const SizedBox(width: 8),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildDoneCheckMarkButton(context),
                    if (expanded) ...[
                      const SizedBox(height: 10),
                      Tooltip(
                          message: txt("close"),
                          child: _buildCloseSideButton(theme)),
                      const SizedBox(height: 5),
                    ],
                    if (expanded ||
                        widget.note.done ||
                        widget.note.archived == true) ...[
                      SizedBox(height: expanded ? 0 : 10),
                      if (canEdit && !widget.note.isGhost)
                        Tooltip(
                          message: widget.note.archived == true
                              ? txt("restore")
                              : txt("archive"),
                          child: _buildArchiveButton(theme),
                        ),
                      if (widget.note.isGhost)
                        Tooltip(
                          message: txt("save"),
                          child: _saveGhostButton(theme),
                        )
                    ]
                  ],
                )
              ],
            ),
            if (expanded) ...[
              ..._dividerWithPadding(10),
              _buildAssignation(theme),
              ..._dividerWithPadding(10),
              _buildDateRelatedRow(theme, context),
              ..._dividerWithPadding(10),
              ..._buildCommentSection(theme),
            ],
            const SizedBox(height: 10),
            _buildExpandCollapseButton(theme),
          ],
        ),
      ),
    );
  }

  IconButton _saveGhostButton(FluentThemeData theme) {
    return IconButton(
      icon: const Icon(FluentIcons.save),
      style: _iconButtonStyle(theme, color: Colors.grey),
      onPressed: () {
        notes.set(widget.note);
      },
    );
  }

  IconButton _buildCloseSideButton(FluentThemeData theme) {
    return IconButton(
      icon: const Icon(WindowsIcons.cancel),
      style: _iconButtonStyle(theme, color: Colors.grey),
      onPressed: () {
        setState(() {
          expanded = false;
          _animationController.reverse();
        });
      },
    );
  }

  Widget _buildExpandCollapseButton(FluentThemeData theme) {
    return SizedBox(
      width: double.infinity,
      child: IconButton(
        style: ButtonStyle(
          backgroundColor: WidgetStatePropertyAll(expanded
              ? Colors.grey
              : theme.inactiveColor.withValues(alpha: 0.1)),
          foregroundColor:
              WidgetStatePropertyAll(expanded ? Colors.white : null),
          iconSize: const WidgetStatePropertyAll(20),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(100),
          )),
        ),
        icon: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              spacing: 5,
              children: [
                const SizedBox.shrink(),
                Icon(expanded
                    ? WindowsIcons.cancel
                    : WindowsIcons.explore_content),
                Txt(expanded ? txt("close") : txt("open")),
              ],
            ),
            Row(
              spacing: 5,
              children: [
                if (expanded == false) ...[
                  if (widget.note.hasAttachments)
                    const Icon(WindowsIcons.attach, size: 16),
                  if (widget.note.hasComments)
                    const Icon(WindowsIcons.comment, size: 16),
                  const SizedBox.shrink(),
                  if (widget.note.unAssigned)
                    SmallLabel(
                      label: txt("unassigned"),
                      textColor: theme.inactiveColor,
                      bgColor: Colors.grey.withValues(alpha: 0.2),
                      icon: WindowsIcons.block_contact,
                    )
                ]
              ],
            )
          ],
        ),
        onPressed: () {
          setState(() {
            expanded = !expanded;
            _titleController.text = widget.note.title;
            _noteController.text = widget.note.note;
            _showTitleSaveButton = false;
            _showNoteSaveButton = false;
          });
          if (expanded) {
            _animationController.forward();
          } else {
            _animationController.reverse();
          }
        },
      ),
    );
  }

  Flexible _buildNoteMainBody(FluentThemeData theme) {
    final isArchived = widget.note.archived == true;
    return Flexible(
      flex: 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        mainAxisSize: MainAxisSize.max,
        spacing: 5,
        children: [
          _buildNoteTitle(theme),
          ..._dividerWithPadding(0),
          expanded ? _noteEditingTextField(theme) : Text(widget.note.note),
          _buildNoteLabels(isArchived, theme),
          if (widget.note.isRecurringInstance)
            Row(
              spacing: 5,
              children: [
                const Icon(WindowsIcons.repeat_all, size: 13),
                Txt(txt("isARecurrenceOfOlderNote"),
                    style: theme.typography.caption?.copyWith(
                      fontStyle: FontStyle.italic,
                    ))
              ],
            )
          else if (widget.note.isRecurring)
            Row(
              spacing: 5,
              children: [
                const Icon(WindowsIcons.repeat_all, size: 13),
                Txt(txt("recurring"),
                    style: theme.typography.caption?.copyWith(
                      fontStyle: FontStyle.italic,
                    ))
              ],
            ),
          if (expanded) ...[
            _buildRecurrenceSection(theme),
            ..._dividerWithPadding(10),
            Txt(
              "${txt("relatingToPatient")}:",
              style: theme.typography.bodyStrong,
            ),
            _buildForPatientRow(),
            if (!widget.note.isGhost &&
                (canEdit || widget.note.attachments.isNotEmpty)) ...[
              ..._dividerWithPadding(10),
              ..._buildAttachments(theme),
            ]
          ]
        ],
      ),
    );
  }

  CupertinoTextField _noteEditingTextField(FluentThemeData theme) {
    return CupertinoTextField(
      readOnly: !canEdit,
      controller: _noteController,
      onChanged: (value) {
        setState(() {
          if (value != widget.note.note) {
            _showNoteSaveButton = true;
          } else {
            _showNoteSaveButton = false;
          }
        });
      },
      style: theme.typography.body,
      maxLines: null,
      suffix: _showNoteSaveButton
          ? IconButton(
              icon: const Icon(FluentIcons.save),
              onPressed: () {
                notes.set(widget.note..note = _noteController.text);
                _showNoteSaveButton = false;
                setState(() {});
              })
          : null,
    );
  }

  Widget _buildRecurrenceSection(FluentThemeData theme) {
    final Note target = widget.note.parent ?? widget.note;
    return Column(
        spacing: 5,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const SizedBox(height: 10),
          if (widget.note.isRecurringInstance)
            Row(
              children: [
                Txt(
                  txt("isARecurrenceOfOlderNote"),
                  style: TextStyle(
                      fontStyle: FontStyle.italic,
                      backgroundColor: theme.inactiveBackgroundColor),
                ),
              ],
            ),
          Row(spacing: 3, children: [
            Checkbox(
              content: Txt(
                  target.isRecurring ? txt("recurringEvery") : txt("recurring"),
                  style: theme.typography.bodyStrong),
              checked: target.isRecurring,
              onChanged: (checked) {
                setState(() {
                  if (checked == true) {
                    target.recurringInterval = 90;
                  } else {
                    target.recurringInterval = null;
                  }
                  _recurringIntervalController.text =
                      target.recurringInterval?.toString() ?? '';

                  notes.set(target);
                  notes.set(widget.note);
                });
              },
            ),
            if (target.isRecurring)
              Expanded(
                child: CupertinoTextField(
                  readOnly: !canEdit,
                  suffix: Padding(
                    padding: const EdgeInsetsDirectional.only(end: 2),
                    child: Row(
                      children: [
                        Txt(txt("day")),
                      ],
                    ),
                  ),
                  controller: _recurringIntervalController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 3,
                  maxLines: 1,
                  textAlign: TextAlign.end,
                  onSubmitted: (_) {
                    _saveRecurringInterval(target);
                  },
                ),
              )
          ]),
          if (target.isRecurring)
            Button(
              child: Txt(txt("save")),
              onPressed: () {
                _saveRecurringInterval(target);
              },
            )
        ]);
  }

  void _saveRecurringInterval(Note target) {
    final value = _recurringIntervalController.text;
    if (value.isNotEmpty) {
      final intValue = int.tryParse(value);
      if (intValue != null && intValue > 0) {
        notes.set(target..recurringInterval = intValue);
      }
      notes.set(widget.note);
    }
  }

  BoxDecoration _mainContainerDecoration(
      FluentThemeData theme, Color borderColor) {
    return BoxDecoration(
      color: theme.menuColor,
      borderRadius: BorderRadius.circular(_borderRadiusAnimation.value),
      boxShadow: [
        BoxShadow(
          offset: Offset(0.0, _elevationAnimation.value),
          blurRadius: expanded ? 40.0 : 5,
          spreadRadius: expanded ? 8.0 : 1,
          color: Colors.grey.withAlpha(expanded ? 80 : 30),
        ),
      ],
    );
  }

  List<Widget> _buildCommentSection(FluentThemeData theme) {
    return [
      ...widget.note.comments.map((comment) {
        return Container(
          padding: const EdgeInsets.all(3),
          margin: const EdgeInsets.only(bottom: 5),
          decoration: BoxDecoration(
            border:
                Border.all(color: theme.inactiveColor.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: theme.inactiveColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    const Icon(WindowsIcons.comment),
                    const SizedBox(width: 5),
                    Text(
                      accounts.nameOrEmailFromID(comment[0]),
                      style: theme.typography.bodyStrong,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 5),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(comment[1], softWrap: true),
              ),
            ],
          ),
        );
      }),
      Row(
        children: [
          Flexible(
            child: CupertinoTextField(
              controller: _commentController,
              maxLines: null,
              placeholder: txt("addComment"),
              prefix: const Padding(
                padding: EdgeInsetsDirectional.only(start: 8.0),
                child: Icon(WindowsIcons.comment),
              ),
              onSubmitted: (_) {
                _sendComment();
              },
              onChanged: (value) {
                if (_commentController.text.isNotEmpty) {
                  setState(() {
                    _commentButtonVisible = true;
                  });
                } else {
                  setState(() {
                    _commentButtonVisible = false;
                  });
                }
              },
            ),
          ),
          if (_commentButtonVisible) ...[
            const SizedBox(width: 5),
            Tooltip(
              message: txt("sendComment"),
              child: IconButton(
                icon: const Icon(WindowsIcons.send),
                onPressed: _sendComment,
                style: _iconButtonStyle(theme),
              ),
            ),
          ]
        ],
      )
    ];
  }

  Widget _buildArchiveButton(FluentThemeData theme) {
    final isArchived = widget.note.archived == true;
    return FlyoutTarget(
      controller: _confirmArchiveFlyoutCtrl,
      child: IconButton(
        style: _iconButtonStyle(theme,
            color: isArchived ? Colors.grey : Colors.errorPrimaryColor),
        icon: Icon(isArchived ? FluentIcons.archive_undo : FluentIcons.archive),
        onPressed: () async {
          await flyoutFocusFix(context);
          _confirmArchiveFlyoutCtrl.showFlyout(builder: (ctx) {
            return ConfirmDeleteFlyout(
              actionText: isArchived ? txt("restore") : txt("archive"),
              actionIcon:
                  isArchived ? FluentIcons.archive_undo : FluentIcons.archive,
              onConfirm: () {
                if (isArchived) {
                  notes.unarchive(widget.note.id);
                } else {
                  notes.archive(widget.note.id);
                }
              },
              controller: _confirmArchiveFlyoutCtrl,
            );
          });
        },
      ),
    );
  }

  Widget _buildDoneCheckMarkButton(BuildContext context) {
    return AnimatedBuilder(
      animation: _checkBoxScaleAnimationController,
      builder: (context, child) {
        return Transform.scale(
          scale: widget.note.done ? _checkboxScaleAnimation.value : 1.5,
          child: Tooltip(
            message: widget.note.done
                ? txt("tapToMarkAsPending")
                : txt("tapToMarkAsDone"),
            child: Checkbox(
              style: CheckboxThemeData(
                checkedDecoration: WidgetStatePropertyAll(
                  BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.successPrimaryColor,
                    border: Border.all(color: Colors.successPrimaryColor),
                  ),
                ),
                icon: widget.note.done
                    ? WindowsIcons.completed
                    : WindowsIcons.checkbox14,
                uncheckedIconColor: WidgetStatePropertyAll(
                    FluentTheme.of(context).inactiveColor),
              ),
              checked: widget.note.done,
              onChanged: (checked) {
                notes.set(widget.note..done = checked == true);
                // Trigger checkbox rotation animation when note is marked as done
                if (checked == true) {
                  _checkBoxScaleAnimationController.forward().then((_) {
                    _checkBoxScaleAnimationController.reverse();
                  });
                }
              },
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildAttachments(FluentThemeData theme) {
    return [
      Txt("${txt("attachments")}:", style: theme.typography.bodyStrong),
      NoteAttachmentsWidget(note: widget.note, canUpload: canEdit)
    ];
  }

  Row _buildForPatientRow() {
    return Row(
      spacing: 5,
      children: [
        const Icon(WindowsIcons.contact2, size: 30),
        Flexible(
          child: Transform.scale(
            scale: 0.85,
            alignment: AlignmentDirectional.centerStart,
            child: PatientPicker(
              enabled: canEdit,
              key: Key(widget.note.forPatient),
              onChanged: (id) {
                notes.set(widget.note..forPatient = id ?? "");
              },
              value: widget.note.forPatient.isEmpty
                  ? null
                  : widget.note.forPatient,
            ),
          ),
        ),
      ],
    );
  }

  Wrap _buildNoteLabels(bool isArchived, FluentThemeData theme) {
    return Wrap(
      spacing: 5,
      runSpacing: 5,
      children: [
        if (isArchived)
          SmallLabel(
            bgColor: theme.inactiveColor.withValues(alpha: 0.1),
            textColor: theme.inactiveColor,
            icon: FluentIcons.archive,
            label: txt("archived"),
          ),
        if (widget.note.overdue)
          SmallLabel(
            bgColor: Colors.errorPrimaryColor.withValues(alpha: 0.1),
            textColor: theme.inactiveColor,
            icon: WindowsIcons.warning,
            label: txt("overdue"),
          ),
        if (widget.note.incoming)
          SmallLabel(
            bgColor: Colors.yellow,
            textColor: theme.inactiveColor,
            icon: WindowsIcons.reply,
            label: txt("incoming"),
          ),
        if (widget.note.outgoing)
          SmallLabel(
            bgColor: Colors.blue.withValues(alpha: 0.1),
            textColor: theme.inactiveColor,
            icon: WindowsIcons.reply_mirrored,
            label: txt("outgoing"),
          ),
        if (widget.note.pending)
          SmallLabel(
            bgColor: Colors.warningPrimaryColor.withValues(alpha: 0.1),
            textColor: theme.inactiveColor,
            icon: WindowsIcons.error,
            label: txt("pending"),
          ),
      ],
    );
  }

  SizedBox _buildNoteTitle(FluentThemeData theme) {
    return SizedBox(
      width: expanded ? 175 : 179,
      child: expanded
          ? _titleEditingTextField(theme)
          : Text(
              overflow: TextOverflow.ellipsis,
              widget.note.title.isEmpty ? txt("note") : widget.note.title,
              style: theme.typography.bodyStrong?.copyWith(fontSize: 16),
            ),
    );
  }

  CupertinoTextField _titleEditingTextField(FluentThemeData theme) {
    return CupertinoTextField(
      controller: _titleController,
      onChanged: (value) {
        setState(() {
          if (value != widget.note.title) {
            _showTitleSaveButton = true;
          } else {
            _showTitleSaveButton = false;
          }
        });
      },
      suffix: _showTitleSaveButton
          ? IconButton(
              icon: const Icon(FluentIcons.save),
              onPressed: () {
                notes.set(widget.note..title = _titleController.text);
                _showTitleSaveButton = false;
                setState(() {});
              })
          : null,
      style: theme.typography.bodyStrong?.copyWith(fontSize: 16),
    );
  }

  Row _buildDateRelatedRow(FluentThemeData theme, BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _twoLinesProp(
                theme,
                txt("createdDate"),
                DF.allNumbers(widget.note.date),
                theme.inactiveColor,
                FontWeight.normal,
                FluentIcons.date_time2,
              ),
              _twoLinesProp(
                theme,
                txt("dueDate"),
                DF.allNumbers(widget.note.dueDate),
                widget.note.overdue
                    ? Colors.red
                    : widget.note.pending
                        ? Colors.warningPrimaryColor
                        : theme.inactiveColor,
                (widget.note.overdue || widget.note.pending)
                    ? FontWeight.bold
                    : FontWeight.normal,
                FluentIcons.date_time2,
              ),
            ],
          ),
        ),
        if (canEdit) ...[
          const SizedBox(width: 8),
          _buildDueDateChangeButton(theme, context)
        ]
      ],
    );
  }

  Tooltip _buildDueDateChangeButton(
    FluentThemeData theme,
    BuildContext context,
  ) {
    return Tooltip(
      message: txt("changeDueDate"),
      child: IconButton(
        style: _iconButtonStyle(theme),
        icon: const Icon(FluentIcons.edit_event),
        onPressed: () async {
          final dueDate = await showDatePicker(
            context: context,
            initialDate: widget.note.dueDate,
            firstDate: DateTime.now().subtract(const Duration(days: 9999)),
            lastDate: DateTime.now().add(const Duration(days: 9999)),
          );
          if (dueDate != null) {
            notes.set(widget.note..dueDate = dueDate);
          }
        },
      ),
    );
  }

  Row _buildAssignation(FluentThemeData theme) {
    final bool creator = widget.note.createdBy == login.currentAccountID;
    final bool assignee = widget.note.assignedTo == login.currentAccountID;
    return Row(
      children: [
        Flexible(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _twoLinesProp(
                theme,
                txt("createdBy"),
                widget.note.createdByUsername,
                creator ? Colors.teal : theme.inactiveColor,
                creator ? FontWeight.bold : FontWeight.normal,
                FluentIcons.contact,
              ),
              _twoLinesProp(
                theme,
                txt("assignedTo"),
                widget.note.assignedTo.isEmpty
                    ? txt("unassigned")
                    : widget.note.assignedUsername,
                assignee ? Colors.red : theme.inactiveColor,
                assignee ? FontWeight.bold : FontWeight.normal,
                widget.note.assignedTo.isEmpty
                    ? FluentIcons.warning
                    : FluentIcons.contact,
              ),
            ],
          ),
        ),
        if (canEdit) ...[
          const SizedBox(width: 8),
          FlyoutTarget(
            controller: _assigningFlyoutCtrl,
            child: _buildAssignButton(theme),
          )
        ]
      ],
    );
  }

  Widget _buildAssignButton(FluentThemeData theme) {
    return Tooltip(
      message: txt("switchAssignee"),
      child: IconButton(
        style: _iconButtonStyle(theme),
        icon: const Icon(FluentIcons.edit_contact),
        onPressed: () async {
          await flyoutFocusFix(context);
          _assigningFlyoutCtrl.showFlyout(builder: (context) {
            return MenuFlyout(
                items: List.generate(accounts.list().length, (i) {
              final item = accounts.list()[i];
              final id = item.id;
              final username = accounts.nameOrEmailFromID(id);
              return MenuFlyoutItem(
                leading: const Icon(FluentIcons.contact),
                text: Txt(username),
                onPressed: () {
                  notes.set(widget.note..assignedTo = id);
                },
              );
            })
                  ..add(MenuFlyoutItem(
                    leading: const Icon(FluentIcons.clear_filter),
                    text: Txt(txt("noAssignee")),
                    onPressed: () {
                      notes.set(widget.note..assignedTo = "");
                    },
                  )));
          });
        },
      ),
    );
  }

  Column _twoLinesProp(
    FluentThemeData theme,
    String title,
    String subtitle,
    Color color,
    FontWeight weight,
    IconData icon,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Txt(
          title,
          style: theme.typography.caption?.copyWith(
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Icon(icon, size: 12),
            const SizedBox(width: 4),
            SizedBox(
              width: 83,
              child: Txt(
                overflow: TextOverflow.ellipsis,
                subtitle,
                style: theme.typography.caption?.copyWith(
                    color: color,
                    fontWeight: weight,
                    height: 1.2,
                    fontSize: 11.5),
              ),
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> _dividerWithPadding(double padding) {
    return [
      SizedBox(height: padding),
      const Divider(),
      SizedBox(height: padding),
    ];
  }

  void _sendComment() {
    widget.note.comments.add([
      login.currentAccountID,
      _commentController.text,
    ]);
    notes.set(widget.note);
    setState(() {
      _commentController.text = '';
      _commentButtonVisible = false;
    });
  }

  ButtonStyle _iconButtonStyle(FluentThemeData theme, {Color? color}) {
    return ButtonStyle(
      backgroundColor: WidgetStatePropertyAll(color ?? theme.accentColor),
      foregroundColor: WidgetStatePropertyAll(theme.activeColor),
      iconSize: const WidgetStatePropertyAll(18),
    );
  }
}

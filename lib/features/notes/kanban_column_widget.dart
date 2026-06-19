import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/features/notes/dialog_column_edit.dart';
import 'package:apexo/features/notes/dialog_note_edit.dart';
import 'package:apexo/features/notes/note_card_widget.dart';
import 'package:apexo/features/notes/notes_model.dart';
import 'package:apexo/features/notes/notes_store.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/utils/constants.dart';
import 'package:apexo/utils/flyout_focus_fix.dart';
import 'package:fluent_ui/fluent_ui.dart';

class KanbanColumn extends StatefulWidget {
  final Note? column;
  final List<Note> columnNotes;
  const KanbanColumn({
    super.key,
    required this.column,
    required this.columnNotes,
  });

  @override
  State<KanbanColumn> createState() => _KanbanColumnState();
}

class _KanbanColumnState extends State<KanbanColumn> {
  final FlyoutController archiveConfirmation = FlyoutController();
  final FlyoutController moreMenuFlyout = FlyoutController();

  @override
  void dispose() {
    archiveConfirmation.dispose();
    moreMenuFlyout.dispose();
    super.dispose();
  }

  bool get canEdit {
    if (login.isAdmin) return true;
    if (login.permissions[PInt.notes] == 2) return true;
    return false;
  }

  Color get color {
    if (widget.column == null) {
      return Colors.grey;
    }
    return widget.column!.computedTint;
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return DragTarget<Note>(
      onAcceptWithDetails: (details) {
        final note = details.data;
        if (widget.column == null) {
          note.columnID = "";
        } else {
          note.columnID = widget.column!.id;
        }
        notes.set(note);
      },
      builder: (context, candidateData, rejectedData) {
        final borderSide = BorderSide(
          color: theme.inactiveColor.withValues(alpha: 0.2),
          width: 1,
        );
        return RepaintBoundary(
          child: Container(
            width: 325,
            decoration: locale.isRtl
                ? BoxDecoration(
                    color: FluentTheme.of(context)
                        .resources
                        .solidBackgroundFillColorBase,
                    border: Border(
                      right: (widget.column == notes.columns.firstOrNull)
                          ? BorderSide.none
                          : borderSide,
                      left: (widget.column == null)
                          ? borderSide
                          : BorderSide.none,
                      bottom: borderSide,
                    ),
                  )
                : BoxDecoration(
                    color: FluentTheme.of(context)
                        .resources
                        .subtleFillColorSecondary,
                    border: Border(
                      left: (widget.column == notes.columns.firstOrNull)
                          ? BorderSide.none
                          : borderSide,
                      right: (widget.column == null)
                          ? borderSide
                          : BorderSide.none,
                      bottom: borderSide,
                    ),
                  ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildColumnTitle(context, theme),
                _buildColumnBody(context),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildArchiveCompletedButton(FluentThemeData theme) {
    if (widget.columnNotes.any((note) => note.done && note.archived != true)) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
        child: FilledButton(
          style: filledButtonStyle(Colors.errorPrimaryColor),
          child: ButtonContent(
              WindowsIcons.delete, txt("deleteAllCompletedNotes")),
          onPressed: () {
            for (var note in widget.columnNotes) {
              if (note.done && note.archived != true) {
                notes.set(note..archived = true);
              }
            }
          },
        ),
      );
    } else {
      return const SizedBox.shrink();
    }
  }

  Widget _buildColumnBody(BuildContext context) {
    return Expanded(
      child: widget.columnNotes.isEmpty
          ? Center(
              child: Column(
                spacing: 10,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    WindowsIcons.quick_note,
                    size: 40,
                    color: FluentTheme.of(context)
                        .inactiveColor
                        .withValues(alpha: 0.3),
                  ),
                  Text(
                    txt("noItemsFound"),
                    style:
                        FluentTheme.of(context).typography.bodyStrong?.copyWith(
                              color: FluentTheme.of(context)
                                  .inactiveColor
                                  .withValues(alpha: 0.5),
                              fontStyle: FontStyle.italic,
                            ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsetsDirectional.fromSTEB(15, 20, 5, 12),
              itemCount: widget.columnNotes.length + 1,
              itemBuilder: (context, index) {
                if (index == widget.columnNotes.length) {
                  return _buildArchiveCompletedButton(FluentTheme.of(context));
                }
                return NoteCard(
                  note: widget.columnNotes[index],
                  key: Key(widget.columnNotes[index].id),
                );
              },
            ),
    );
  }

  Widget _buildColumnTitle(BuildContext context, FluentThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        spacing: 2,
        children: [
          Row(
            spacing: 5,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildStylishColor(context),
              Expanded(
                child: Tooltip(
                  message: txt("editColumn"),
                  child: GestureDetector(
                    onTap: () {
                      if (widget.column != null) {
                        showColumnEditDialog(context, column: widget.column);
                      }
                    },
                    child: _buildColumnName(context, theme),
                  ),
                ),
              ),
              Tooltip(
                message: txt("addNote"),
                child: _buildAddNoteButton(theme, context),
              ),
              if (widget.column != null && canEdit)
                FlyoutTarget(
                  controller: moreMenuFlyout,
                  child: IconButton(
                      icon: const Icon(WindowsIcons.more),
                      onPressed: () async {
                        await flyoutFocusFix(context);
                        moreMenuFlyout.showFlyout(builder: (context) {
                          return MenuFlyout(
                            items: [
                              MenuFlyoutItem(
                                text: Text(txt("edit")),
                                leading: const Icon(FluentIcons.edit),
                                onPressed: () {
                                  if (moreMenuFlyout.isOpen) {
                                    moreMenuFlyout.close();
                                  }
                                  WidgetsBinding.instance
                                      .addPostFrameCallback((_) {
                                    showColumnEditDialog(context,
                                        column: widget.column);
                                  });
                                },
                              ),
                              const MenuFlyoutSeparator(),
                              if (notes.columns.firstOrNull != widget.column)
                                MenuFlyoutItem(
                                  text: Text(txt("moveTowardsStart")),
                                  leading: Icon(locale.isRtl
                                      ? WindowsIcons.chevron_right
                                      : WindowsIcons.chevron_left),
                                  onPressed: () {
                                    final index =
                                        notes.columns.indexOf(widget.column!);
                                    final prev = notes.columns[index - 1];
                                    final thisOrder = double.parse(
                                        widget.column!.order.toString());
                                    final prevOrder =
                                        double.parse(prev.order.toString());
                                    notes
                                        .set(widget.column!..order = prevOrder);
                                    notes.set(prev..order = thisOrder);
                                  },
                                ),
                              if (notes.columns.lastOrNull != widget.column)
                                MenuFlyoutItem(
                                  text: Text(txt("moveTowardsEnd")),
                                  leading: Icon(locale.isRtl
                                      ? WindowsIcons.chevron_left
                                      : WindowsIcons.chevron_right),
                                  onPressed: () {
                                    final index =
                                        notes.columns.indexOf(widget.column!);
                                    final next = notes.columns[index + 1];
                                    final thisOrder = double.parse(
                                        widget.column!.order.toString());
                                    final nextOrder =
                                        double.parse(next.order.toString());
                                    notes
                                        .set(widget.column!..order = nextOrder);
                                    notes.set(next..order = thisOrder);
                                  },
                                )
                            ],
                          );
                        });
                      }),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Container _buildStylishColor(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: widget.column != null
            ? color
            : FluentTheme.of(context).inactiveColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Center(
        child: Txt(
          widget.columnNotes.length.toString(),
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
        ),
      ),
    );
  }

  IconButton _buildAddNoteButton(FluentThemeData theme, BuildContext context) {
    return IconButton(
      style: _addNoteButtonStyle(context),
      icon: const Icon(FluentIcons.add),
      onPressed: () {
        showNoteEditDialog(context, columnID: widget.column?.id);
      },
    );
  }

  ButtonStyle _addNoteButtonStyle(BuildContext context) {
    return ButtonStyle(
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(3),
        side: BorderSide(
            color: FluentTheme.of(context).inactiveColor.withValues(alpha: 0.4),
            width: 1),
      )),
    );
  }

  Widget _buildColumnName(BuildContext context, FluentThemeData theme) {
    return Container(
      height: 34,
      padding: const EdgeInsets.all(2),
      child: Row(
        children: [
          if (widget.column != null) const SizedBox(width: 5),
          Expanded(
            child: Txt(
              widget.column?.columnName ?? txt("uncategorized"),
              style: theme.typography.bodyStrong?.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

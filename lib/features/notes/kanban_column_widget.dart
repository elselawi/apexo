import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/features/notes/dialog_column_edit.dart';
import 'package:apexo/features/notes/dialog_note_edit.dart';
import 'package:apexo/features/notes/note_card_widget.dart';
import 'package:apexo/features/notes/notes_model.dart';
import 'package:apexo/features/notes/notes_store.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/utils/flyout_focus_fix.dart';
import 'package:fluent_ui/fluent_ui.dart';

class KanbanColumn extends StatelessWidget {
  final Note? column;
  final List<Note> columnNotes;
  final FlyoutController archiveConfirmation = FlyoutController();
  final FlyoutController moreMenuFlyout = FlyoutController();

  Color get color {
    if (column == null) {
      return Colors.grey;
    }
    return column!.computedTint;
  }

  KanbanColumn({
    super.key,
    required this.column,
    required this.columnNotes,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return DragTarget<Note>(
      onAcceptWithDetails: (details) {
        final note = details.data;
        if (column == null) {
          note.columnID = "";
        } else {
          note.columnID = column!.id;
        }
        notes.set(note);
      },
      builder: (context, candidateData, rejectedData) {
        final borderSide = BorderSide(
          color: theme.inactiveColor.withValues(alpha: 0.2),
          width: 1,
        );
        return Container(
          width: 325,
          margin: const EdgeInsets.only(top: 13),
          decoration: locale.isRtl
              ? BoxDecoration(
                  color: Colors.transparent,
                  border: Border(
                    top: borderSide,
                    right: (column == notes.columns.firstOrNull)
                        ? BorderSide.none
                        : borderSide,
                    left: (column == null) ? borderSide : BorderSide.none,
                    bottom: borderSide,
                  ),
                )
              : BoxDecoration(
                  color: Colors.transparent,
                  border: Border(
                    top: borderSide,
                    left: (column == notes.columns.firstOrNull)
                        ? BorderSide.none
                        : borderSide,
                    right: (column == null) ? borderSide : BorderSide.none,
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
        );
      },
    );
  }

  Widget _buildArchiveCompletedButton(FluentThemeData theme) {
    if (columnNotes.any((note) => note.done && note.archived != true)) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
        child: FilledButton(
          style: filledButtonStyle(Colors.errorPrimaryColor),
          child: ButtonContent(
              FluentIcons.archive, txt("archiveAllCompletedNotes")),
          onPressed: () {
            for (var note in columnNotes) {
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
      child: columnNotes.isEmpty
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
              itemCount: columnNotes.length + 1,
              itemBuilder: (context, index) {
                if (index == columnNotes.length) {
                  return _buildArchiveCompletedButton(FluentTheme.of(context));
                }
                return NoteCard(
                  note: columnNotes[index],
                  key: Key(columnNotes[index].id),
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
                      if (column != null) {
                        showColumnEditDialog(context, column: column);
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
              if (column != null)
                FlyoutTarget(
                  controller: moreMenuFlyout,
                  child: IconButton(
                      icon: const Icon(FluentIcons.more),
                      onPressed: () async {
                        await flyoutFocusFix(context);
                        moreMenuFlyout.showFlyout(builder: (context) {
                          return MenuFlyout(
                            items: [
                              MenuFlyoutItem(
                                text: Text(txt("edit")),
                                leading: const Icon(FluentIcons.edit),
                                onPressed: () {
                                  moreMenuFlyout.close();
                                  showColumnEditDialog(context, column: column);
                                },
                              ),
                              const MenuFlyoutSeparator(),
                              if (notes.columns.firstOrNull != column)
                                MenuFlyoutItem(
                                  text: Text(txt("moveTowardsStart")),
                                  leading: Icon(locale.isRtl
                                      ? FluentIcons.chevron_right
                                      : FluentIcons.chevron_left),
                                  onPressed: () {
                                    final index =
                                        notes.columns.indexOf(column!);
                                    final prev = notes.columns[index - 1];
                                    final thisOrder =
                                        double.parse(column!.order.toString());
                                    final prevOrder =
                                        double.parse(prev.order.toString());
                                    notes.set(column!..order = prevOrder);
                                    notes.set(prev..order = thisOrder);
                                  },
                                ),
                              if (notes.columns.lastOrNull != column)
                                MenuFlyoutItem(
                                  text: Text(txt("moveTowardsEnd")),
                                  leading: Icon(locale.isRtl
                                      ? FluentIcons.chevron_left
                                      : FluentIcons.chevron_right),
                                  onPressed: () {
                                    final index =
                                        notes.columns.indexOf(column!);
                                    final next = notes.columns[index + 1];
                                    final thisOrder =
                                        double.parse(column!.order.toString());
                                    final nextOrder =
                                        double.parse(next.order.toString());
                                    notes.set(column!..order = nextOrder);
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
        color: column != null ? color : FluentTheme.of(context).inactiveColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Center(
        child: Txt(
          columnNotes.length.toString(),
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
        showNoteEditDialog(context, columnID: column?.id);
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
          if (column != null) const SizedBox(width: 5),
          Expanded(
            child: Txt(
              column?.columnName ?? txt("uncategorized"),
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

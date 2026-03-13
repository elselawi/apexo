import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/features/notes/dialog_column_edit.dart';
import 'package:apexo/features/notes/dialog_note_edit.dart';
import 'package:apexo/features/notes/note_card_widget.dart';
import 'package:apexo/features/notes/notes_model.dart';
import 'package:apexo/features/notes/notes_store.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';

class KanbanColumn extends StatelessWidget {
  final Note? column;
  final List<Note> columnNotes;
  final FlyoutController archiveConfirmation = FlyoutController();

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
        return Container(
          width: 320,
          margin: const EdgeInsets.only(left: 10, top: 10, bottom: 10),
          decoration: BoxDecoration(
            color: column?.archived == true
                ? Colors.white.withValues(alpha: 0.5)
                : theme.menuColor,
            borderRadius: BorderRadius.circular(5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .2),
                blurRadius: 5,
                offset: const Offset(0, 0),
              ),
            ],
            border: Border.all(
              color: theme.inactiveColor.withValues(alpha: 0.3),
              width: 1,
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
            final List<Note> toSet = [];
            for (var note in columnNotes) {
              if (note.done && note.archived != true) {
                toSet.add(note..archived = true);
              }
            }
            notes.setAll(toSet);
          },
        ),
      );
    } else {
      return const SizedBox.shrink();
    }
  }

  Widget _buildColumnBody(BuildContext context) {
    if (columnNotes.isEmpty) {
      return _buildAddNoteFullButton(context);
    } else {
      return Expanded(
        child: ListView.builder(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 20, 20, 12),
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
  }

  Widget _buildAddNoteFullButton(BuildContext context) {
    return Center(
      child: Transform.scale(
        scale: 1.2,
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Button(
            style: _addNoteButtonStyle(),
            child: ButtonContent(
              FluentIcons.add_field,
              txt("addNote"),
            ),
            onPressed: () {
              showNoteEditDialog(context, columnID: column?.id);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildColumnTitle(BuildContext context, FluentThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: .07),
        border: Border(
          bottom: BorderSide(color: color.withValues(alpha: 0.8), width: 2),
        ),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        spacing: 5,
        children: [
          Row(
            spacing: 5,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (column != null &&
                  notes.columns.first != column &&
                  notes.columns.length > 1)
                _buildReorderToBeginingButton(theme),
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
              if (column != null &&
                  notes.columns.last != column &&
                  notes.columns.length > 1)
                _buildReordertoEndButton(theme),
            ],
          ),
          _buildCountAndArchivedStatus(theme),
        ],
      ),
    );
  }

  Widget _buildReordertoEndButton(FluentThemeData theme) {
    return Tooltip(
      message: txt("moveTowardsEnd"),
      child: IconButton(
        style: _orderSwitchingButtonStyle(theme),
        icon: Icon(locale.isRtl ? FluentIcons.chevron_left : FluentIcons.chevron_right),
        onPressed: () {
          final index = notes.columns.indexOf(column!);
          final next = notes.columns[index + 1];
          final thisOrder = double.parse(column!.order.toString());
          final nextOrder = double.parse(next.order.toString());
          notes.set(column!..order = nextOrder);
          notes.set(next..order = thisOrder);
        },
      ),
    );
  }

  Widget _buildReorderToBeginingButton(FluentThemeData theme) {
    return Tooltip(
      message: txt("moveTowardsStart"),
      child: IconButton(
        style: _orderSwitchingButtonStyle(theme),
        icon: Icon(locale.isRtl ? FluentIcons.chevron_right : FluentIcons.chevron_left),
        onPressed: () {
          final index = notes.columns.indexOf(column!);
          final prev = notes.columns[index - 1];
          final thisOrder = double.parse(column!.order.toString());
          final prevOrder = double.parse(prev.order.toString());
          notes.set(column!..order = prevOrder);
          notes.set(prev..order = thisOrder);
        },
      ),
    );
  }

  ButtonStyle _orderSwitchingButtonStyle(FluentThemeData theme) {
    return ButtonStyle(
      iconSize: const WidgetStatePropertyAll(10),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(40),
          side: BorderSide(color: theme.inactiveColor.withValues(alpha: 0.4)),
        ),
      ),
    );
  }

  Container _buildStylishColor(BuildContext context) {
    return Container(
      width: 3,
      height: 30,
      decoration: BoxDecoration(
        color: column != null ? color : FluentTheme.of(context).inactiveColor,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  IconButton _buildRenameButton(BuildContext context) {
    return IconButton(
      icon: Icon(
        FluentIcons.rename,
        size: 16,
        color: column == null ? Colors.transparent : null,
      ),
      onPressed: () {
        showColumnEditDialog(context, column: column);
      },
    );
  }

  IconButton _buildAddNoteButton(FluentThemeData theme, BuildContext context) {
    return IconButton(
      style: _addNoteButtonStyle(),
      icon: const Icon(FluentIcons.add_field, size: 20),
      onPressed: () {
        showNoteEditDialog(context, columnID: column?.id);
      },
    );
  }

  ButtonStyle _addNoteButtonStyle() {
    return ButtonStyle(
      backgroundColor: WidgetStatePropertyAll(
        color.toAccentColor(),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(color: color.toAccentColor().darkest),
        ),
      ),
      foregroundColor: const WidgetStatePropertyAll(Colors.white),
      elevation: const WidgetStatePropertyAll(8),
    );
  }

  Widget _buildColumnName(BuildContext context, FluentThemeData theme) {
    return Container(
      height: 34,
      padding: const EdgeInsets.all(2),
      decoration: column != null
          ? BoxDecoration(
              border: Border.all(
                  color: theme.inactiveColor.withValues(alpha: 0.35), width: 1),
              borderRadius: BorderRadius.circular(5),
            )
          : null,
      child: Row(
        children: [
          if (column != null) const SizedBox(width: 5),
          Expanded(
            child: Txt(
              column?.columnName ?? txt("uncategorized"),
              style: theme.typography.bodyStrong?.copyWith(
                fontSize: 16,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (column != null) _buildRenameButton(context),
        ],
      ),
    );
  }

  Row _buildCountAndArchivedStatus(FluentThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Txt(
          "${columnNotes.length} ${txt("item")}",
          style: theme.typography.caption?.copyWith(
            color: theme.inactiveColor.withValues(alpha: 0.6),
          ),
        ),
        if (column?.archived == true)
          Txt(
            txt("archived"),
            style: theme.typography.caption?.copyWith(
              color: theme.inactiveColor.withValues(alpha: 0.6),
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w500,
            ),
          )
      ],
    );
  }
}

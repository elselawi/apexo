import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/screen_command_bar.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/features/notes/dialog_note_edit.dart';
import 'package:apexo/features/notes/kanban_column_widget.dart';
import 'package:apexo/features/notes/dialog_column_edit.dart';
import 'package:apexo/features/notes/notes_model.dart';
import 'package:apexo/features/notes/notes_store.dart';
import 'package:apexo/features/accounts/accounts_controller.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/utils/constants.dart';
import 'package:fluent_ui/fluent_ui.dart';

class NotesScreen extends StatelessWidget {
  const NotesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MStreamBuilder(
        streams: [
          notes.observableMap.stream,
          notes.filterByAccountId.stream,
          notes.sortDirection.stream,
          notes.showIncoming.stream,
        ],
        // ignore: prefer_const_constructors
        builder: (context, snapshot) => NotesKanBanBoard());
  }
}

class NotesKanBanBoard extends StatefulWidget {
  const NotesKanBanBoard({super.key});

  @override
  State<NotesKanBanBoard> createState() => _NotesKanBanBoardState();
}

class _NotesKanBanBoardState extends State<NotesKanBanBoard> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Note> get _filteredNotes {
    var allNotes = notes.filtered.values.where((e) => e.isNote).toList();

    // Search filter
    if (_searchController.text.isNotEmpty) {
      final searchLower = _searchController.text.toLowerCase();
      allNotes = allNotes
          .where((note) =>
              note.title.toLowerCase().contains(searchLower) ||
              note.note.toLowerCase().contains(searchLower))
          .toList();
    }

    return allNotes;
  }

  Map<String, List<Note>> get _groupedNotes {
    final grouped = <String, List<Note>>{};
    final filtered = _filteredNotes;

    for (final note in filtered) {
      grouped.putIfAbsent(note.columnID, () => []).add(note);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildCommandBar(),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [_buildSearch()],
          ),
        ),
        Container(
          decoration: topBarDecoration(context, Colors.grey),
          padding: const EdgeInsets.all(8),
          child: Row(
            spacing: 5,
            children: [
              Button(
                child: ButtonContent(
                  notes.sortDirection() == 1
                      ? FluentIcons.sort_up
                      : FluentIcons.sort_down,
                  "${txt("sort")} ${txt(notes.sortDirection() == 1 ? "ascending" : "descending")}",
                ),
                onPressed: () {
                  notes.sortDirection(notes.sortDirection() * -1);
                },
              ),
              if (login.permissions[PInt.notes] == 1 || login.isAdmin)
                ToggleButton(
                  checked: notes.filterByAccountId().isNotEmpty,
                  child: ButtonContent(FluentIcons.contact, txt("personal")),
                  onChanged: (value) {
                    if (value) {
                      notes.filterByAccountId(login.currentAccountID);
                    } else {
                      notes.filterByAccountId('');
                    }
                  },
                ),
              ToggleButton(
                checked: notes.showIncoming(),
                child: ButtonContent(FluentIcons.reply, txt("incoming")),
                onChanged: (value) {
                  notes.showIncoming(value);
                },
              )
            ],
          ),
        ),
        _buildKanabanBoard(),
      ],
    );
  }

  Expanded _buildKanabanBoard() {
    final grouped = _groupedNotes;
    final sortDir = notes.sortDirection();

    return Expanded(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...notes.columns.map((column) {
              final columnNotes = grouped[column.id] ?? [];
              final ghosts = notes
                  .ghostCreatorsInColumn(column.id)
                  .map((n) => n.createChild());

              final tNotes = [...columnNotes, ...ghosts]
                ..sort((a, b) => a.date.compareTo(b.date) * sortDir);

              return KanbanColumn(
                key: Key(column.id),
                column: column,
                columnNotes: tNotes,
              );
            }),
            KanbanColumn(
              column: null,
              columnNotes: (grouped[""] ?? [])
                ..addAll(
                    notes.ghostCreatorsInColumn("").map((n) => n.createChild()))
                ..sort((a, b) => a.date.compareTo(b.date) * sortDir),
            ),
            const _AddColumnButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildCommandBar() {
    return ScreenCommandBar(
      mainButton: IconButton(
        onPressed: () => showNoteEditDialog(context),
        icon: ButtonContent(FluentIcons.add, txt("newNote")),
      ),
      farItems: [_buildAccountsFilter()],
    );
  }

  ComboBox<String> _buildAccountsFilter() {
    return ComboBox<String>(
      style: const TextStyle(overflow: TextOverflow.ellipsis),
      items: [
        ComboBoxItem<String>(
          value: "",
          child: Txt(txt("allAccounts")),
        ),
        ...accounts.list().map((account) {
          var name = "🧑‍💼 ${accounts.name(account)}";
          if (name.length > 17) {
            name = "${name.substring(0, 14)}...";
          }
          return ComboBoxItem(value: account.id, child: Text(name));
        }),
      ],
      onChanged: (login.permissions[PInt.notes] == 0 && !login.isAdmin)
          ? null
          : (id) => notes.filterByAccountId(id ?? ""),
      value: notes.filterByAccountId(),
    );
  }

  Expanded _buildSearch() {
    return Expanded(
        child: TopSearch(controller: _searchController, setState: setState));
  }
}

class _AddColumnButton extends StatelessWidget {
  const _AddColumnButton();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 25),
      width: 220,
      child: Button(
        style: ButtonStyle(
          backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(0),
              side: const BorderSide(color: Colors.transparent),
            ),
          ),
        ),
        onPressed: () => showColumnEditDialog(context),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(FluentIcons.add, size: 25),
              const SizedBox(height: 8),
              Txt(
                txt("addColumn"),
                style: FluentTheme.of(context)
                    .typography
                    .bodyStrong
                    ?.copyWith(fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

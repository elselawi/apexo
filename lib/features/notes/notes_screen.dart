import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/features/notes/kanban_column_widget.dart';
import 'package:apexo/features/notes/dialog_column_edit.dart';
import 'package:apexo/features/notes/notes_model.dart';
import 'package:apexo/features/notes/notes_store.dart';
import 'package:apexo/features/accounts/accounts_controller.dart';
import 'package:apexo/services/archived.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/common_widgets/archive_toggle.dart';
import 'package:apexo/utils/constants.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/cupertino.dart';

class NotesScreen extends StatelessWidget {
  const NotesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      key: WK.notesScreen,
      padding: EdgeInsets.zero,
      resizeToAvoidBottomInset: true,
      content: Column(
        children: [
          Expanded(
            child: MStreamBuilder(
                streams: [
                  notes.observableMap.stream,
                  showArchived.stream,
                  notes.filterByAccountId.stream,
                  notes.sortDirection.stream
                ],
                // ignore: prefer_const_constructors
                builder: (context, snapshot) => NotesKanBanBoard()),
          ),
        ],
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildCommandBar(),
        Padding(
          padding: const EdgeInsets.only(top: 8, left: 8, right: 8),
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
                Button(
                  child: ButtonContent(
                      notes.filterByAccountId().isNotEmpty
                          ? FluentIcons.clear_filter
                          : FluentIcons.filter,
                      notes.filterByAccountId().isNotEmpty
                          ? txt("showAll")
                          : txt("showOnlyMine")),
                  onPressed: () {
                    if (notes.filterByAccountId().isEmpty) {
                      notes.filterByAccountId(login.currentAccountID);
                    } else {
                      notes.filterByAccountId('');
                    }
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
    return Expanded(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...notes.columns.map((column) {
              List<Note> tNotes = [
                ..._filteredNotes.where((e) => e.columnID == column.id),
                ...notes
                    .ghostCreatorsInColumn(column.id)
                    .map((n) => n.createChild())
              ]..sort((a, b) => a.date.compareTo(b.date));

              if (notes.sortDirection() == -1) {
                tNotes = tNotes.reversed.toList();
              }
              return KanbanColumn(
                  key: Key(column.id), column: column, columnNotes: tNotes);
            }),
            KanbanColumn(
              column: null,
              columnNotes: _filteredNotes.where((e) => e.unCategorized).toList()
                ..addAll(
                    notes.ghostCreatorsInColumn("").map((n) => n.createChild()))
                ..sort(
                    (a, b) => a.date.compareTo(b.date) * notes.sortDirection())
                ..reversed,
            ),
            _buildAddColumnButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildAddColumnButton() {
    return Container(
      padding: const EdgeInsets.all(8.0),
      margin: const EdgeInsets.all(2.0),
      child: Button(
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
        children: [
          Expanded(
            child: CupertinoTextField(
              decoration: BoxDecoration(
                  color: Colors.transparent,
                  border: Border.all(color: Colors.transparent)),
              placeholder: "🔍 ${txt("searchPlaceholder")}",
              controller: _searchController,
              onChanged: (text) => setState(() {}),
            ),
          ),
          const SizedBox(width: 5),
          ComboBox<String>(
            style: const TextStyle(overflow: TextOverflow.ellipsis),
            items: [
              ComboBoxItem<String>(
                value: "",
                child: Txt(txt("allAccounts")),
              ),
              ...accounts.list().map((account) {
                var name = "👨‍⚕️ ${accounts.name(account)}";
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
          ),
          const SizedBox(width: 5),
          const ArchiveToggle(),
        ],
      ),
    );
  }
}

// TODO: use notes screen in web & andnroid to see if it works fine

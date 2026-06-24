import 'dart:math';

import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/item_title.dart';
import 'package:apexo/common_widgets/screen_command_bar.dart';
import 'package:apexo/common_widgets/show_more_bar.dart';
import 'package:apexo/core/model.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/core/store.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/appointments/open_appointment_panel.dart';
import 'package:apexo/features/expenses/expenses_store.dart';
import 'package:apexo/features/expenses/open_expense_panel.dart';
import 'package:apexo/features/notes/dialog_column_edit.dart';
import 'package:apexo/features/notes/dialog_note_edit.dart';
import 'package:apexo/features/notes/notes_store.dart';
import 'package:apexo/features/patients/open_patient_panel.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/utils/constants.dart';
import 'package:fluent_ui/fluent_ui.dart';

class ArchivedScreen extends StatelessWidget {
  const ArchivedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MStreamBuilder(
      streams: [
        patients.observableMap.stream,
        appointments.observableMap.stream,
        expenses.observableMap.stream,
        notes.observableMap.stream,
      ],
      builder: (context, _) =>
          _ArchivedPage(DateTime.now().millisecondsSinceEpoch),
    );
  }
}

class _ArchivedPage extends StatefulWidget {
  const _ArchivedPage(this.tick);
  final int tick;

  @override
  State<_ArchivedPage> createState() => _ArchivedPageState();
}

class _ArchivedRow {
  final Model item;
  final String storeLabel;
  final Color storeColor;
  final IconData storeIcon;
  final String subtitle;
  final VoidCallback onRestore;
  final VoidCallback? onOpen;

  const _ArchivedRow({
    required this.item,
    required this.storeLabel,
    required this.storeColor,
    required this.storeIcon,
    required this.subtitle,
    required this.onRestore,
    required this.onOpen,
  });
}

class _ArchivedPageState extends State<_ArchivedPage> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // store filter — null = all
  String? _activeStore;

  // sort
  int _sortDirection = 1;

  // multi-select
  final Set<String> _selected = {};

  // slice for performance
  int _slice = 20;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void didUpdateWidget(covariant _ArchivedPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tick != widget.tick) {
      _updateItems();
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged() => _invalidateCache();
  void _rebuild() => setState(() {});

  /// Drop cached rows so the next [build] recomputes them.
  void _invalidateCache() {
    _rebuild();
  }

  /// Called by [didUpdateWidget] when stores emit changes.
  void _updateItems() {
    _invalidateCache();
    _collectionCache = {};
  }

  bool _storeVisible(String key) => _activeStore == null || _activeStore == key;

  bool _canAccess(int permissionIndex) {
    return login.perm(permissionIndex).some || login.isAdmin;
  }

  bool _matchesSearch(String text) {
    if (_searchController.text.isEmpty) return true;
    return text.toLowerCase().contains(_searchController.text.toLowerCase());
  }

  // ── cached data ──

  Map<String, List<List<String>>> _collectionCache = {};

  List<List<String>> _collect(String storeKey, Store store) {
    if (!_storeVisible(storeKey)) return [];
    if (_collectionCache.containsKey(storeKey)) {
      return _collectionCache[storeKey]!;
    }
    _collectionCache[storeKey] = [];
    for (final doc in store.archived.values) {
      _collectionCache[storeKey]!
          .add([doc.id, storeKey, doc.title.toLowerCase()]);
    }
    return _collectionCache[storeKey]!;
  }

  /// Lightweight sort keys for the entire filtered dataset.
  /// Only allocates id+storeKey+lowerTitle — no closures, no subtitles, no models.
  List<List<String>> get _sortKeys {
    final keys = <List<String>>[];

    if (_canAccess(Perm.patients)) keys.addAll(_collect("patients", patients));
    if (_canAccess(Perm.appointments)) {
      keys.addAll(_collect("appointments", appointments));
    }
    if (_canAccess(Perm.expenses)) keys.addAll(_collect("expenses", expenses));
    if (_canAccess(Perm.notes)) keys.addAll(_collect("notes", notes));

    keys.sort((a, b) => a[2].compareTo(b[2]) * _sortDirection);
    return keys;
  }

  /// Builds a full [_ArchivedRow] on demand from a [_SortKey].
  /// Called only for visible items (via [ListView.builder]).
  _ArchivedRow _rowForKey(List<String> key) {
    switch (key[1]) {
      case "patients":
        final p = patients.get(key[0])!;
        final g = p.gender == 1 ? txt("male") : txt("female");
        return _ArchivedRow(
          item: p,
          storeLabel: txt("patients"),
          storeColor: Colors.blue,
          storeIcon: FluentIcons.medication_admin,
          subtitle: '$g, ${p.age}',
          onRestore: () => patients.unarchive(p.id),
          onOpen: () => openPatient(p),
        );
      case "appointments":
        final a = appointments.get(key[0])!;
        final d =
            '${a.date.year}-${a.date.month.toString().padLeft(2, '0')}-${a.date.day.toString().padLeft(2, '0')}';
        final ops = a.operatorsNames;
        return _ArchivedRow(
          item: a,
          storeLabel: txt("appointments"),
          storeColor: Colors.green,
          storeIcon: WindowsIcons.calendar,
          subtitle: ops.isNotEmpty ? '$d — $ops' : d,
          onRestore: () => appointments.unarchive(a.id),
          onOpen: () => openAppointment(a),
        );
      case "expenses":
        final e = expenses.get(key[0])!;

        return _ArchivedRow(
          item: e,
          storeLabel: txt("expenses"),
          storeColor: Colors.orange,
          storeIcon: FluentIcons.receipt_processing,
          subtitle: e.isSupplier
              ? "${expenses.docs.values.where((x) => x.supplierId == e.id).length} ${txt("orders")}"
              : '${DF.commonDate(e.date)} - ${"${e.items.length} ${txt("items")}"}',
          onRestore: () => expenses.unarchive(e.id),
          onOpen: e.isOrder
              ? () => openExpenses(
                    [e],
                    "${e.fromSupplierName}-${DF.allNumbers(e.date)}-${txt("deleted")}${e.id}",
                    null,
                    true,
                  )
              : null,
        );
      case "notes":
        final n = notes.get(key[0])!;
        final t = n.isColumn ? txt("column") : txt("note");
        final d =
            '${n.date.year}-${n.date.month.toString().padLeft(2, '0')}-${n.date.day.toString().padLeft(2, '0')}';
        return _ArchivedRow(
          item: n.isColumn
              ? Model.fromJson(
                  {"title": n.columnName, "archived": true, "id": n.id})
              : n,
          storeLabel: txt("notes"),
          storeColor: Colors.purple,
          storeIcon: WindowsIcons.quick_note,
          subtitle: '$t — $d',
          onRestore: () => notes.unarchive(n.id),
          onOpen: () => n.isColumn
              ? showColumnEditDialog(context, column: n)
              : showNoteEditDialog(context, note: n),
        );
      default:
        throw ArgumentError("Unknown store key: ${key[1]}");
    }
  }

  void _restoreSelected() {
    for (final key in _sortKeys) {
      if (_selected.contains(key[0])) {
        _rowForKey(key).onRestore();
      }
    }
    _collectionCache = {};
    _selected.clear();
    _rebuild();
  }

  void _pruneStaleSelection(List<List<String>> keys) {
    final validIds = keys.map((k) => k[0]).toSet();
    _selected.removeWhere((id) => !validIds.contains(id));
  }

  // ────────────────────────────────────────────────────────────────
  // Build
  // ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final keys = _sortKeys.where((x) => _matchesSearch(x[2])).toList();
    _pruneStaleSelection(keys);

    final sliced = keys.sublist(0, min(_slice, keys.length));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildCommandBar(),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              _buildSearch(),
            ],
          ),
        ),
        Container(
          width: double.infinity,
          decoration: topBarDecoration(context, Colors.grey),
          padding: const EdgeInsets.all(8),
          child: Row(
            spacing: 5,
            children: [
              _buildStoreSelector(),
              _buildSortButton(),
            ],
          ),
        ),
        if (keys.isEmpty)
          _buildNoResults()
        else ...[
          Expanded(child: _buildTable(sliced)),
          ShowMoreBar(
            all: keys.length,
            slice: sliced.length,
            scrollController: _scrollController,
            callBack: () => setState(() => _slice += 20),
          ),
        ],
      ],
    );
  }

  // ────────────────────────────────────────────────────────────────
  // Command bar
  // ────────────────────────────────────────────────────────────────

  Widget _buildCommandBar() {
    final count = _selected.length;
    return ScreenCommandBar(
      mainButton: IconButton(
        icon: ButtonContent(
          WindowsIcons.undo,
          '${txt("restore")} ($count)',
        ),
        onPressed: _selected.isNotEmpty ? _restoreSelected : null,
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────
  // Search
  // ────────────────────────────────────────────────────────────────

  Widget _buildSearch() {
    return Expanded(
      child: TopSearch(controller: _searchController, setState: setState),
    );
  }

  // ────────────────────────────────────────────────────────────────
  // Store selector (ComboBox)
  // ────────────────────────────────────────────────────────────────

  Widget _buildStoreSelector() {
    final items = <ComboBoxItem<String?>>[
      ComboBoxItem<String?>(
        value: null,
        child: Txt(txt("showAll")),
      ),
    ];
    if (_canAccess(Perm.patients)) {
      items.add(ComboBoxItem(
        value: "patients",
        child: Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
          Icon(FluentIcons.medication_admin, size: 14, color: Colors.blue),
          Txt(txt("patients")),
        ]),
      ));
    }
    if (_canAccess(Perm.appointments)) {
      items.add(ComboBoxItem(
        value: "appointments",
        child: Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
          Icon(WindowsIcons.calendar, size: 14, color: Colors.green),
          Txt(txt("appointments")),
        ]),
      ));
    }
    if (_canAccess(Perm.expenses)) {
      items.add(ComboBoxItem(
        value: "expenses",
        child: Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
          Icon(FluentIcons.receipt_processing, size: 14, color: Colors.orange),
          Txt(txt("expenses")),
        ]),
      ));
    }
    if (_canAccess(Perm.notes)) {
      items.add(ComboBoxItem(
        value: "notes",
        child: Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
          Icon(WindowsIcons.quick_note, size: 14, color: Colors.purple),
          Txt(txt("notes")),
        ]),
      ));
    }

    return ComboBox<String?>(
      value: _activeStore,
      onChanged: (v) {
        _activeStore = v;
        _invalidateCache();
      },
      style: const TextStyle(overflow: TextOverflow.ellipsis),
      placeholder: Txt(txt("showAll")),
      items: items,
    );
  }

  // ────────────────────────────────────────────────────────────────
  // Sort
  // ────────────────────────────────────────────────────────────────

  Widget _buildSortButton() {
    return Button(
      onPressed: () {
        _sortDirection *= -1;
        _invalidateCache();
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          Icon(
            _sortDirection == 1 ? FluentIcons.sort_up : FluentIcons.sort_down,
            size: 14,
          ),
          Txt(txt("sort")),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────
  // Empty / no-results
  // ────────────────────────────────────────────────────────────────

  Widget _buildNoResults() {
    return Expanded(
      child: Center(
        child: Txt(
          txt("noResultsFound"),
          style: TextStyle(fontSize: 14, color: Colors.grey[120]),
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────
  // Table
  // ────────────────────────────────────────────────────────────────

  Widget _buildTable(List<List<String>> keys) {
    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.zero,
      itemCount: keys.length,
      itemExtent: 62,
      itemBuilder: (context, index) {
        final row = _rowForKey(keys[index]);
        return _buildRow(context, row);
      },
    );
  }

  Widget _buildRow(BuildContext context, _ArchivedRow row) {
    return ListTile.selectable(
      key: ValueKey(row.item.id),
      selected: _selected.contains(row.item.id),
      selectionMode: ListTileSelectionMode.multiple,
      onSelectionChange: (isSelected) {
        if (isSelected) {
          _selected.add(row.item.id);
        } else {
          _selected.remove(row.item.id);
        }
        _rebuild();
      },
      margin: EdgeInsets.zero,
      shape: listDividerBorder(context),
      tileColor: WidgetStateColor.resolveWith((states) {
        if (_selected.contains(row.item.id)) {
          return Colors.blue.withAlpha(20);
        }
        if (states.contains(WidgetState.hovered)) {
          return FluentTheme.of(context).resources.controlAltFillColorTertiary;
        }
        return FluentTheme.of(context).resources.solidBackgroundFillColorBase;
      }),
      contentPadding:
          const EdgeInsetsDirectional.only(top: 0, bottom: 0, start: 4, end: 4),
      leading: _buildStoreTag(context, row),
      title: GestureDetector(
        onTap: row.onOpen,
        child: ItemTitle(
          item: row.item,
          radius: 13,
          maxWidth: 160,
          fontSize: 13,
          icon: row.storeIcon,
          archivedStyling: false,
        ),
      ),
      subtitle: Text(
        row.subtitle,
        style: TextStyle(fontSize: 11, color: Colors.grey[120]),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildStoreTag(BuildContext context, _ArchivedRow row) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: row.storeColor.withAlpha(20),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: row.storeColor.withAlpha(50)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 3,
        children: [
          Icon(row.storeIcon, size: 13, color: row.storeColor),
          Text(
            row.storeLabel,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: row.storeColor,
            ),
          ),
        ],
      ),
    );
  }
}

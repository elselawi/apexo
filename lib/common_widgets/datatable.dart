import 'dart:convert';
import 'dart:math';
import 'package:apexo/app/routes.dart';
import 'package:apexo/core/store.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/cupertino.dart';
import '../utils/colors_without_yellow.dart';
import '../core/model.dart';
import 'item_title.dart';

class _SortableItem<Item> {
  String value;
  Item item;
  _SortableItem(this.value, this.item);
}

class ItemAction {
  IconData icon;
  String title;
  void Function(String) callback;
  ItemAction({required this.icon, required this.title, required this.callback});
}

class DataTableAction {
  void Function(List<String>) callback;
  IconData icon;
  String? title;
  Widget? child;
  DataTableAction({required this.callback, required this.icon, this.title, this.child});
}

class DataTable<Item extends Model> extends StatefulWidget {
  final List<Item> items;
  final Store store;
  final List<DataTableAction> actions;
  final void Function(Item) onSelect;
  final List<Widget> furtherActions;
  final bool compact;
  final List<ItemAction> itemActions;
  final int defaultSortDirection;
  final String defaultSortingName;

  const DataTable({
    super.key,
    required this.items,
    required this.store,
    required this.actions,
    required this.onSelect,
    this.furtherActions = const [],
    this.compact = false,
    this.itemActions = const [],
    this.defaultSortDirection = 1,
    this.defaultSortingName = "byTitle",
  });

  @override
  State<StatefulWidget> createState() => DataTableState<Item>();
}

class DataTableState<Item extends Model> extends State<DataTable<Item>> {
  Set<String> checkedIds = {};
  int sortBy = -1;
  int sortDirection = 1;
  int slice = 10;

  /// labels must be cached since this computation would
  /// occur too many times on every rebuild
  List<String>? _labels;
  List<String> get labels {
    return _labels ??= widget.items
        .fold(<String>{}, (labels, item) => labels..addAll((item.labels.keys.toList()))).toList()
      ..sort((a, b) => a.compareTo(b));
    //..removeWhere((label) => label.isEmpty);
  }

  List<String> get nonNullLabels {
    return labels.where((x) => !x.contains("\u200B")).toList();
  }

  List<Item> get filteredItems {
    final words = _searchValue.toLowerCase().replaceAll(RegExp("أ|إ"), "ا").split(" ");
    final List<Item> candidates = [];
    for (var item in widget.items) {
      final searchIn =
          (item.title + jsonEncode(item.labels.values.toList())).toLowerCase().replaceAll(RegExp("أ|إ"), "ا");
      final bool allTermsFound =
          words.map((word) => searchIn.contains(word)).where((x) => x == true).length == words.length;
      if (allTermsFound) candidates.add(item);
    }
    return candidates;
  }

  String removeNonNumbers(String input) {
    final regex = RegExp(r'^\D+|\D+$');
    final containsNumbers = RegExp(r'\d').hasMatch(input);

    if (containsNumbers) {
      return input.replaceAll(regex, '');
    }
    return input;
  }

  List<Item> get sortedItems {
    List<Item> result = List<Item>.from(filteredItems);
    if (sortBy < 0) {
      result.sort((a, b) {
        return a.title.toLowerCase().compareTo(b.title.toLowerCase()) * sortDirection;
      });
    } else {
      final sorted = List<_SortableItem<Item>>.from(result.map((e) => _SortableItem(e.labels[labels[sortBy]] ?? "", e)))
        ..sort((a, b) {
          if (double.tryParse(a.value) != null && double.tryParse(b.value) != null) {
            return double.parse(a.value).compareTo(double.parse(b.value)) * sortDirection;
          } else if (double.tryParse(removeNonNumbers(a.value)) != null &&
              double.tryParse(removeNonNumbers(b.value)) != null) {
            return double.parse(removeNonNumbers(a.value)).compareTo(double.parse(removeNonNumbers(b.value))) *
                sortDirection;
          } else {
            return a.value.compareTo(b.value) * sortDirection;
          }
        });
      result = sorted.map((e) => e.item).toList();
    }

    return result.sublist(0, min(result.length, slice));
  }

  showMore() {
    setState(() {
      slice = slice + 10;
    });
  }

  String _searchValue = '';

  setSearchTerm(String value) {
    setState(() {
      // Don't modify the controller directly, just use the value for filtering
      _searchValue = value;
    });
  }

  itemSelectToggle(Item item, bool? checked) {
    setState(() {
      if (checked == true) {
        checkedIds.add(item.id);
      } else {
        checkedIds.remove(item.id);
      }
    });
  }

  setSortBy(int? index) {
    setState(() {
      sortBy = index ?? -1;
    });
  }

  toggleSortDirection() {
    setState(() {
      sortDirection = sortDirection * -1;
    });
  }

  @override
  void initState() {
    super.initState();
    sortDirection = widget.defaultSortDirection;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildCommandBar(),
        _buildListController(),
        _buildItemsList(context),
      ],
    );
  }

  final contextMenuControllers = <String, FlyoutController>{};

  Expanded _buildItemsList(BuildContext context) {
    final sorted = [...sortedItems]; // caching those two for easier computation
    final filtered = [...filteredItems];

    for (var item in filtered) {
      contextMenuControllers.putIfAbsent(item.id, () => FlyoutController());
    }

    return Expanded(
      child: Container(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          children: [
            if (filtered.isEmpty) _buildNoItemsFound(),
            Expanded(
              child: ListView.builder(
                key: WK.dataTableListView,
                itemCount: filtered.length > sorted.length ? sorted.length + 1 : sorted.length,
                itemBuilder: (context, index) => filtered.length > sorted.length && index == sorted.length
                    ? _buildShowMore(context)
                    : _buildSingleItem(sorted[index], checkedIds.contains(sorted[index].id)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Center _buildShowMore(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(10),
        width: 100,
        height: 60,
        child: FilledButton(
          style: ButtonStyle(
              elevation: const WidgetStatePropertyAll(10),
              backgroundColor: WidgetStatePropertyAll(FluentTheme.of(context).accentColor),
              foregroundColor: const WidgetStatePropertyAll(Colors.white),
              shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(200)))),
          onPressed: showMore,
          child: const Icon(FluentIcons.double_chevron_down),
        ),
      ),
    );
  }

  _buildSingleItem(Item item, bool isChecked) {
    return Container(
      padding: widget.compact ? EdgeInsets.zero : const EdgeInsets.symmetric(vertical: 1.5),
      decoration: BoxDecoration(
        color: isChecked ? FluentTheme.of(context).selectionColor.withValues(alpha: 0.05) : null,
        border: Border(
          bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.2), width: 0.5),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(0),
        title: Container(
          margin: const EdgeInsets.fromLTRB(5, 5, 5, 0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
          ),
          child: Row(
            children: [
              Divider(direction: Axis.vertical, size: widget.compact ? 1 : 45),
              _buildInnerRow(item),
              Divider(direction: Axis.vertical, size: widget.compact ? 1 : 45),
            ],
          ),
        ),
        leading: _buildCheckBox(isChecked, item),
        onPressed: () => widget.onSelect(item),
        trailing: FlyoutTarget(
            controller: contextMenuControllers[item.id]!,
            child: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(5),
                child: const Icon(FluentIcons.more),
              ),
              onPressed: () {
                contextMenuControllers[item.id]!.showFlyout(
                  barrierDismissible: true,
                  dismissOnPointerMoveAway: false,
                  dismissWithEsc: true,
                  builder: (context) {
                    return StatefulBuilder(builder: (context, setState) {
                      return MenuFlyout(items: [
                        MenuFlyoutItem(
                          text: Txt(item.title),
                          leading: const Icon(FluentIcons.edit),
                          onPressed: () => widget.onSelect(item),
                          closeAfterClick: true,
                        ),
                        if (widget.itemActions.isNotEmpty) const MenuFlyoutSeparator(),
                        for (var action in widget.itemActions)
                          MenuFlyoutItem(
                            leading: Icon(action.icon),
                            text: Txt(action.title),
                            onPressed: () => action.callback(item.id),
                            closeAfterClick: true,
                          ),
                        if (routes.panels().where((p) => p.item.id == item.id).isEmpty)
                          MenuFlyoutItem(
                            leading: Icon(item.archived == true ? FluentIcons.archive_undo : FluentIcons.archive),
                            text: Txt(txt(item.archived == true ? "restore" : "archive")),
                            onPressed: () =>
                                item.archived == true ? widget.store.unarchive(item.id) : widget.store.archive(item.id),
                            closeAfterClick: true,
                          )
                      ]);
                    });
                  },
                );
              },
            )),
      ),
    );
  }

  int getCycledNumber(int num) {
    return (num - 1) % 7;
  }

  Expanded _buildInnerRow(Item item) {
    var nonEmptyLabels = labels.where((l) => item.labels[l] != null).toList();
    return Expanded(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Padding(
          padding: widget.compact ? const EdgeInsets.all(0) : const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ItemTitle(key: Key(item.id), radius: widget.compact ? 1 : 20, item: item),
              ...nonEmptyLabels.map((labelTitle) => _buildLabelPill(
                  labelTitle, item, colorsWithoutYellow[getCycledNumber(nonEmptyLabels.indexOf(labelTitle))]))
            ],
          ),
        ),
      ),
    );
  }

  _buildCheckBox(bool isChecked, Item item) {
    return Transform.scale(
      scale: 1.25,
      child: Checkbox(
        key: Key("dt_cb_${item.id}"),
        checked: isChecked,
        onChanged: (checked) => itemSelectToggle(item, checked),
      ),
    );
  }

  Padding _buildListController() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 5, 10, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [_buildItemsNumIndicator(), _buildSorters()],
      ),
    );
  }

  Row _buildSorters() {
    return Row(
      children: [_buildSortBy(), const SizedBox(width: 3), _buildSortDirectionToggle()],
    );
  }

  IconButton _buildSortDirectionToggle() {
    return IconButton(
      key: WK.toggleSortDirection,
      icon: sortDirection > 0 ? const Icon(FluentIcons.sort_up) : const Icon(FluentIcons.sort_down),
      onPressed: toggleSortDirection,
    );
  }

  ComboBox<int> _buildSortBy() {
    return ComboBox<int>(
      key: WK.dataTableSortBy,
      items: [
        ComboBoxItem<int>(value: -1, child: Txt(txt(widget.defaultSortingName))),
        ...nonNullLabels
            .map((l) => ComboBoxItem<int>(value: nonNullLabels.indexOf(l), child: Txt("${txt("by")} ${txt(l)}")))
      ],
      value: sortBy,
      onChanged: setSortBy,
    );
  }

  Widget _buildItemsNumIndicator() {
    final filtered = [...filteredItems];
    return Row(
      children: [
        Txt(
          "${txt("showing")} ${sortedItems.length}/${filtered.length}",
          style: TextStyle(color: Colors.grey.toAccentColor().lightest, fontSize: 11, fontWeight: FontWeight.bold),
        ),
        if (filtered.isNotEmpty) ..._buildToggleSorters(context),
      ],
    );
  }

  List<Widget> _buildToggleSorters(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (routes.panels().isNotEmpty || width < 865 || (width > 1000 && width < 1150)) {
      return [];
    }
    return [
      const SizedBox(width: 30),
      ...([widget.defaultSortingName, ...nonNullLabels])
          .map((e) => [
                Acrylic(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                  elevation: sortBy == nonNullLabels.indexOf(e) ? 12 : 0,
                  child: ToggleButton(
                    checked: sortBy == nonNullLabels.indexOf(e),
                    onChanged: (checked) {
                      if (checked) {
                        setSortBy(nonNullLabels.indexOf(e));
                      } else {
                        toggleSortDirection();
                      }
                    },
                    style: const ToggleButtonThemeData(
                        uncheckedButtonStyle: ButtonStyle(
                      backgroundColor: WidgetStatePropertyAll(Colors.transparent),
                    )),
                    child: Row(
                      children: [
                        Txt(txt(e)),
                        const SizedBox(width: 5),
                        if (sortBy == nonNullLabels.indexOf(e))
                          Icon(sortDirection > 0 ? FluentIcons.sort_up : FluentIcons.sort_down)
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 5)
              ])
          .expand((e) => e)
    ];
  }

  Acrylic _buildCommandBar() {
    return Acrylic(
      tintAlpha: 1,
      elevation: 140,
      luminosityAlpha: 0.8,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Builder(
                builder: (context) => CommandBar(
                  primaryItems: List.generate(widget.actions.length, (index) {
                    final action = widget.actions[index];
                    return CommandBarButton(
                      onPressed: () {
                        if (Navigator.canPop(context)) {
                          Navigator.pop(context);
                        }
                        action.callback(checkedIds.toList());
                      },
                      label: action.child ?? (action.title != null ? Txt(action.title!) : null),
                      icon: Icon(action.icon),
                    );
                  }),
                  overflowBehavior: CommandBarOverflowBehavior.dynamicOverflow,
                ),
              ),
            ),
            const Divider(size: 20, direction: Axis.vertical),
            DataTableSearchField(
              onChanged: setSearchTerm,
              placeholder: _searchValue,
            ),
            ...widget.furtherActions.map((a) => a)
          ],
        ),
      ),
    );
  }

  _buildNoItemsFound() {
    return Padding(
      padding: const EdgeInsets.all(15),
      child: InfoBar(
        isIconVisible: true,
        severity: InfoBarSeverity.warning,
        title: Txt(txt("noItemsFound")),
      ),
    );
  }

  Widget _buildLabelPill(String l, Item item, [Color? color]) {
    var selected = _searchValue.toLowerCase() == item.labels[l]?.toLowerCase();
    color = color ?? colorsWithoutYellow[((labels.indexOf(l) / labels.length) * colorsWithoutYellow.length).floor()];
    return Padding(
      padding: const EdgeInsets.all(2),
      child: GestureDetector(
        onTap: () {
          if (selected) {
            setSearchTerm("");
          } else {
            setSearchTerm((item.labels[l] ?? "").toLowerCase());
          }
        },
        child: DataTablePill(
          selected: selected,
          color: color,
          title: l,
          content: item.labels[l] ?? "",
        ),
      ),
    );
  }
}

class DataTablePill extends StatelessWidget {
  const DataTablePill({
    super.key,
    required this.selected,
    required this.color,
    required this.title,
    required this.content,
  });

  final bool selected;
  final Color color;
  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    return Row(
      textDirection: TextDirection.ltr,
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color.withValues(alpha: 0.15), color.withValues(alpha: 0.07), color.withValues(alpha: 0.15)],
            ),
            border: Border.all(color: color.withValues(alpha: 0.3), width: 0.3),
            borderRadius: BorderRadius.circular(5),
          ),
          padding: const EdgeInsets.fromLTRB(10, 5, 10, 0),
          child: Wrap(
            children: [
              Txt(
                (txt(title)),
                style:
                    TextStyle(fontStyle: FontStyle.italic, fontWeight: FontWeight.bold, fontSize: 11.5, color: color),
              ),
              const SizedBox(width: 5),
              const Divider(direction: Axis.vertical, size: 10),
              const SizedBox(width: 5),
              Txt((content), style: const TextStyle(fontSize: 15)),
            ],
          ),
        ),
        if (selected)
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .7),
              borderRadius: const BorderRadius.only(topRight: Radius.circular(5), bottomRight: Radius.circular(5)),
            ),
            child: const Icon(
              FluentIcons.filter,
              size: 13,
              color: Colors.white,
            ),
          ),
      ],
    );
  }
}

class DataTableSearchField extends StatefulWidget {
  final ValueChanged<String> onChanged;
  final String placeholder;

  const DataTableSearchField({
    super.key,
    required this.onChanged,
    this.placeholder = "",
  });

  @override
  State<DataTableSearchField> createState() => _DataTableSearchFieldState();
}

class _DataTableSearchFieldState extends State<DataTableSearchField> {
  final TextEditingController _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 165,
      child: CupertinoTextField(
          suffix: _controller.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(FluentIcons.clear),
                  onPressed: () {
                    _controller.clear();
                    widget.onChanged("");
                  },
                ),
          key: WK.dataTableSearch,
          placeholder:
              widget.placeholder.isEmpty ? "🔍 ${txt("searchPlaceholder")}" : "${txt("filter")}: ${widget.placeholder}",
          onChanged: widget.onChanged,
          controller: _controller,
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              gradient: LinearGradient(
                end: AlignmentDirectional.topStart,
                begin: AlignmentDirectional.bottomEnd,
                colors: [
                  Colors.white.withValues(alpha: 0.1),
                  Colors.white.withValues(alpha: 0.05),
                ],
              ))),
    );
  }
}

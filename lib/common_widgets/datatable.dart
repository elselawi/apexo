import 'dart:convert';
import 'dart:math';
import 'package:apexo/app/routes.dart';
import 'package:apexo/common_widgets/money_display.dart';
import 'package:apexo/common_widgets/no_items_found.dart';
import 'package:apexo/common_widgets/teeth_selector/tx_options.dart';
import 'package:apexo/core/store.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/utils/flyout_focus_fix.dart';
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
  DataTableAction(
      {required this.callback, required this.icon, this.title, this.child});
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
  String? byTreatment;

  /// labels must be cached since this computation would
  /// occur too many times on every rebuild
  List<String>? _labels;
  List<String> get labels {
    return _labels ??= widget.items.fold(<String>{},
        (labels, item) => labels..addAll((item.labels.keys.toList()))).toList()
      ..sort((a, b) => a.compareTo(b));
    //..removeWhere((label) => label.isEmpty);
  }

  List<String> get nonNullLabels {
    return labels.where((x) => !x.contains("\u200B")).toList();
  }

  List<Item> get filteredItems {
    final words =
        _searchValue.toLowerCase().replaceAll(RegExp("أ|إ"), "ا").split(" ");
    final List<Item> candidates = [];
    for (var item in widget.items) {
      final searchIn = (item.title + jsonEncode(item.labels.values.toList()))
          .toLowerCase()
          .replaceAll(RegExp("أ|إ"), "ا");
      final bool allTermsFound = words
              .map((word) => searchIn.contains(word))
              .where((x) => x == true)
              .length ==
          words.length;
      if (allTermsFound) candidates.add(item);
    }

    if (byTreatment != null && widget.items is List<Patient>) {
      return candidates.where((patient) {
        final Patient p = patient as Patient;
        if (byTreatment != "bridge") {
          return p.allPredefinedTreatments.contains(byTreatment);
        } else {
          return p.allPredefinedTreatments.contains("abutment") ||
              p.allPredefinedTreatments.contains("pontic") ||
              p.allPredefinedTreatments.contains("bridge");
        }
      }).toList();
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
        return a.title.toLowerCase().compareTo(b.title.toLowerCase()) *
            sortDirection;
      });
    } else {
      final sorted = List<_SortableItem<Item>>.from(
          result.map((e) => _SortableItem(e.labels[labels[sortBy]] ?? "", e)))
        ..sort((a, b) {
          if (double.tryParse(a.value) != null &&
              double.tryParse(b.value) != null) {
            return double.parse(a.value).compareTo(double.parse(b.value)) *
                sortDirection;
          } else if (double.tryParse(removeNonNumbers(a.value)) != null &&
              double.tryParse(removeNonNumbers(b.value)) != null) {
            return double.parse(removeNonNumbers(a.value))
                    .compareTo(double.parse(removeNonNumbers(b.value))) *
                sortDirection;
          } else {
            return a.value.compareTo(b.value) * sortDirection;
          }
        });
      result = sorted.map((e) => e.item).toList();
    }

    return result.sublist(0, min(result.length, slice));
  }

  void scrollToBottom() {
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
    );
  }

  showMore() {
    setState(() {
      slice = slice + 10;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        scrollToBottom();
      });
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
        _buildShowMore(context)
      ],
    );
  }

  final contextMenuControllers = <String, FlyoutController>{};
  final ScrollController _scrollController = ScrollController();

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
            if (filtered.isEmpty) const NoItemsFound(),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                key: WK.dataTableListView,
                itemCount: sorted.length,
                itemBuilder: (context, index) => _buildSingleItem(
                  sorted[index],
                  checkedIds.contains(sorted[index].id),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShowMore(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: FluentTheme.of(context).resources.cardStrokeColorDefault,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Txt(
            "${txt("showing")} ${sortedItems.length}/${filteredItems.length}",
            style: FluentTheme.of(context).typography.body,
          ),
          Row(
            children: [
              if (filteredItems.length > sortedItems.length)
                FilledButton(
                  onPressed: showMore,
                  child: Row(
                    children: [
                      const Icon(FluentIcons.double_chevron_down),
                      const SizedBox(width: 8),
                      Txt(txt("showMore")),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  _buildSingleItem(Item item, bool isChecked) {
    return ListTile(
      key: Key(item.id),
      tileColor: WidgetStatePropertyAll(
          isChecked ? Colors.blue.withAlpha(20) : Colors.transparent),
      contentPadding: const EdgeInsets.all(0),
      title: Row(
        children: [
          Divider(direction: Axis.vertical, size: widget.compact ? 1 : 45),
          _buildInnerRow(item),
          Divider(direction: Axis.vertical, size: widget.compact ? 1 : 45),
        ],
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
            onPressed: () async {
              await flyoutFocusFix(context);
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
                      if (widget.itemActions.isNotEmpty)
                        const MenuFlyoutSeparator(),
                      for (var action in widget.itemActions)
                        MenuFlyoutItem(
                          leading: Icon(action.icon),
                          text: Txt(action.title),
                          onPressed: () => action.callback(item.id),
                          closeAfterClick: true,
                        ),
                      if (routes
                          .panels()
                          .where((p) => p.item.id == item.id)
                          .isEmpty)
                        MenuFlyoutItem(
                          leading: Icon(item.archived == true
                              ? FluentIcons.archive_undo
                              : FluentIcons.archive),
                          text: Txt(txt(
                              item.archived == true ? "restore" : "archive")),
                          onPressed: () => item.archived == true
                              ? widget.store.unarchive(item.id)
                              : widget.store.archive(item.id),
                          closeAfterClick: true,
                        )
                    ]);
                  });
                },
              );
            },
          )),
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
          padding: widget.compact
              ? const EdgeInsets.all(0)
              : const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ItemTitle(
                labels: item is Patient
                    ? item.allPredefinedTreatments
                        .map((x) =>
                            x == "pontic" || x == "abutment" ? "bridge" : x)
                        .where((x) => txOptions.any(
                            (y) => y.type != StateType.state && y.label == x))
                        .toSet()
                        .map((x) => TreatmentLabel(
                            string: x,
                            color: labelToColor(x),
                            icon: labelToIcon(x)))
                        .toList()
                    : [],
                key: Key(item.id),
                radius: widget.compact ? 1 : 20,
                item: item,
                maxWidth: 110,
              ),
              ...nonEmptyLabels.map((labelTitle) => _buildLabelPill(
                  labelTitle,
                  item,
                  colorsWithoutYellow[
                      getCycledNumber(nonEmptyLabels.indexOf(labelTitle))]))
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
    final treatments =
        txOptions.where((x) => x.type != StateType.state).toList();
    return Row(
      children: [
        if (widget.items is List<Patient>) ...[
          ComboBox<String>(
            onChanged: (treatment) => setState(() => byTreatment = treatment),
            value: byTreatment,
            placeholder: Txt(txt("treatment")),
            items: [
              ComboBoxItem<String>(
                value: null,
                child: Txt(txt("allTreatments")),
              ),
              ...List.generate(
                treatments.length - 3,
                (i) {
                  final o = treatments[i];
                  return ComboBoxItem<String>(
                    value: o.label,
                    child: Row(
                      children: [
                        Icon(o.icon, color: o.color),
                        const SizedBox(width: 5),
                        Container(
                            decoration: BoxDecoration(
                                color: o.color,
                                borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 2),
                            child: Txt(
                              txt(o.label),
                              style: const TextStyle(color: Colors.white),
                            )),
                      ],
                    ),
                  );
                },
              )
            ],
          ),
          const SizedBox(width: 10)
        ],
        _buildSortBy(),
        const SizedBox(width: 3),
        _buildSortDirectionToggle()
      ],
    );
  }

  IconButton _buildSortDirectionToggle() {
    return IconButton(
      key: WK.toggleSortDirection,
      icon: sortDirection > 0
          ? const Icon(FluentIcons.sort_up)
          : const Icon(FluentIcons.sort_down),
      onPressed: toggleSortDirection,
    );
  }

  ComboBox<int> _buildSortBy() {
    return ComboBox<int>(
      key: WK.dataTableSortBy,
      items: [
        ComboBoxItem<int>(
            value: -1, child: Txt(txt(widget.defaultSortingName))),
        ...nonNullLabels.map((l) => ComboBoxItem<int>(
            value: nonNullLabels.indexOf(l),
            child: Txt("${txt("by")} ${txt(l)}")))
      ],
      value: sortBy,
      onChanged: setSortBy,
    );
  }

  Widget _buildItemsNumIndicator() {
    final width = MediaQuery.of(context).size.width;
    if (routes.panels().isNotEmpty ||
        width < 865 ||
        (width > 1000 && width < 1150)) {
      return const SizedBox();
    }
    final filtered = [...filteredItems];
    return Row(
      children: [
        Txt(
          "${txt("showing")} ${sortedItems.length}/${filtered.length}",
          style: TextStyle(
              color: Colors.grey.toAccentColor().lightest,
              fontSize: 11,
              fontWeight: FontWeight.bold),
        ),
        if (filtered.isNotEmpty) ..._buildToggleSorters(context),
      ],
    );
  }

  List<Widget> _buildToggleSorters(BuildContext context) {
    return [
      const SizedBox(width: 30),
      ...([widget.defaultSortingName, ...nonNullLabels])
          .map((e) => [
                ToggleButton(
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
                        Icon(sortDirection > 0
                            ? FluentIcons.sort_up
                            : FluentIcons.sort_down)
                    ],
                  ),
                ),
                const SizedBox(width: 5)
              ])
          .expand((e) => e)
    ];
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
                    label: action.child ??
                        (action.title != null ? Txt(action.title!) : null),
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
    );
  }

  Widget _buildLabelPill(String l, Item item, [Color? color]) {
    var selected = _searchValue.toLowerCase() == item.labels[l]?.toLowerCase();
    color = color ??
        colorsWithoutYellow[
            ((labels.indexOf(l) / labels.length) * colorsWithoutYellow.length)
                .floor()];
    return GestureDetector(
      onTap: () {
        if (selected) {
          setSearchTerm("");
        } else {
          setSearchTerm((item.labels[l] ?? "").toLowerCase());
        }
      },
      child: DataTablePill(
        selected: selected,
        color: l.length < 3 ? Colors.grey : color,
        title: l,
        content: item.labels[l] ?? "",
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
          color: color.withValues(alpha: 0.1),
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              if (title.length > 2) ...[
                Txt(
                  (txt(title)),
                  style: FluentTheme.of(context)
                      .typography
                      .caption
                      ?.copyWith(color: color, fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 10),
              ],
              if (content.contains("."))
                MoneyDisplay((content), style: const TextStyle(fontSize: 15))
              else
                Txt(content, style: const TextStyle(fontSize: 15)),
            ],
          ),
        ),
        if (selected)
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(color: color.withValues(alpha: .7)),
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
          placeholder: widget.placeholder.isEmpty
              ? "🔍 ${txt("searchPlaceholder")}"
              : "${txt("filter")}: ${widget.placeholder}",
          onChanged: widget.onChanged,
          controller: _controller,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
          )),
    );
  }
}

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
import 'item_title.dart';

class _SortableItem {
  String value;
  Patient item;
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

class DataTable extends StatefulWidget {
  final List<Patient> items;
  final Store store;
  final List<DataTableAction> actions;
  final void Function(Patient) onSelect;
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
  State<StatefulWidget> createState() => DataTableState();
}

class DataTableState extends State<DataTable> {
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
  }

  List<String> get nonNullLabels {
    return labels.where((x) => !x.contains("\u200B")).toList();
  }

  List<Patient> get filteredItems {
    final words =
        _searchValue.toLowerCase().replaceAll(RegExp("أ|إ"), "ا").split(" ");
    final List<Patient> candidates = [];
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

    if (byTreatment != null) {
      return candidates.where((patient) {
        if (byTreatment != "bridge") {
          return patient.allPredefinedTreatments.contains(byTreatment);
        } else {
          return patient.allPredefinedTreatments.contains("abutment") ||
              patient.allPredefinedTreatments.contains("pontic") ||
              patient.allPredefinedTreatments.contains("bridge");
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

  List<Patient> get sortedItems {
    List<Patient> result = List<Patient>.from(filteredItems);
    if (sortBy < 0) {
      result.sort((a, b) {
        return a.title.toLowerCase().compareTo(b.title.toLowerCase()) *
            sortDirection;
      });
    } else {
      final sorted = List<_SortableItem>.from(
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

  void showMore() {
    setState(() {
      slice = slice + 10;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        scrollToBottom();
      });
    });
  }

  String _searchValue = '';

  void setSearchTerm(String value) {
    setState(() {
      _searchValue = value;
    });
  }

  void itemSelectToggle(Patient item, bool? checked) {
    setState(() {
      if (checked == true) {
        checkedIds.add(item.id);
      } else {
        checkedIds.remove(item.id);
      }
    });
  }

  void setSortBy(int? index) {
    setState(() {
      sortBy = index ?? -1;
    });
  }

  void toggleSortDirection() {
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
    final theme = FluentTheme.of(context);
    return Container(
      color: theme.scaffoldBackgroundColor,
      child: Column(
        children: [
          _buildCommandBar(),
          _buildListController(),
          _buildItemsList(context),
          _buildShowMore(context)
        ],
      ),
    );
  }

  final contextMenuControllers = <String, FlyoutController>{};
  final ScrollController _scrollController = ScrollController();

  Widget _buildItemsList(BuildContext context) {
    final sorted = [...sortedItems];
    final filtered = [...filteredItems];

    for (var item in filtered) {
      contextMenuControllers.putIfAbsent(item.id, () => FlyoutController());
    }

    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            if (filtered.isEmpty) const NoItemsFound(),
            Expanded(
              child: GridView.builder(
                controller: _scrollController,
                key: WK.dataTableListView,
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 400,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 0.75,
                ),
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
    final theme = FluentTheme.of(context);
    final sorted = [...sortedItems];
    final filtered = [...filteredItems];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.resources.cardBackgroundFillColorDefault,
        border: Border(
          top: BorderSide(
            color: theme.resources.cardStrokeColorDefault,
            width: 1.0,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Txt(
            "${txt("showing")} ${sorted.length}/${filtered.length}",
            style: theme.typography.caption?.copyWith(
              color: theme.resources.textFillColorSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (filtered.length > sorted.length)
            FilledButton(
              onPressed: showMore,
              style: const ButtonStyle(
                padding: WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(FluentIcons.double_chevron_down, size: 12),
                  const SizedBox(width: 6),
                  Txt(txt("showMore"), style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSingleItem(Patient item, bool isChecked) {
    final theme = FluentTheme.of(context);
    return Padding(
      padding: EdgeInsets.zero,
      child: HoverButton(
        onPressed: () => widget.onSelect(item),
        builder: (context, states) {
          final isHovered = states.contains(WidgetState.hovered);
          return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeInOut,
            decoration: BoxDecoration(
              color: isChecked
                  ? theme.accentColor.withValues(alpha: 0.08)
                  : isHovered
                      ? theme.resources.subtleFillColorSecondary
                      : theme.resources.cardBackgroundFillColorDefault,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isChecked
                    ? theme.accentColor.withValues(alpha: 0.45)
                    : isHovered
                        ? theme.resources.controlStrokeColorDefault
                        : theme.resources.cardStrokeColorDefault,
                width: 1.0,
              ),
              boxShadow: isHovered && !isChecked
                  ? [
                      BoxShadow(
                        color: theme.shadowColor.withValues(alpha: 0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      )
                    ]
                  : null,
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildCardHeader(item, isChecked, theme),
                const SizedBox(height: 10),
                Expanded(
                  child: _buildCardContent(item),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCardHeader(Patient item, bool isChecked, FluentThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildCheckBox(isChecked, item),
        const SizedBox(width: 8),
        Expanded(
          child: ItemTitle(
            labels: [],
            key: Key(item.id),
            radius: 4,
            item: item,
            maxWidth: 200,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: FlyoutTarget(
            controller: contextMenuControllers[item.id]!,
            child: HoverButton(
              onPressed: () async {
                await flyoutFocusFix(context);
                contextMenuControllers[item.id]!.showFlyout(
                  barrierDismissible: true,
                  dismissOnPointerMoveAway: false,
                  dismissWithEsc: true,
                  builder: (context) {
                    return StatefulBuilder(
                        builder: (context, setState) {
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
                            text: Txt(txt(item.archived == true
                                ? "restore"
                                : "archive")),
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
              builder: (context, states) {
                final isBtnHovered =
                    states.contains(WidgetState.hovered);
                return Container(
                  decoration: BoxDecoration(
                    color: isBtnHovered
                        ? theme.resources.subtleFillColorTertiary
                        : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    FluentIcons.more,
                    size: 14,
                    color: theme.resources.textFillColorSecondary,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCardContent(Patient item) {
    var nonEmptyLabels = labels.where((l) => item.labels[l] != null).toList();
    final treatmentLabels = item.allPredefinedTreatments
        .map((x) => x == "pontic" || x == "abutment" ? "bridge" : x)
        .where((x) =>
            txOptions.any((y) => y.type != StateType.state && y.label == x))
        .toSet()
        .map((x) => TreatmentLabel(
            string: x, color: labelToColor(x), icon: labelToIcon(x)))
        .toList();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (treatmentLabels.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: treatmentLabels
                    .map((label) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: label.color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: label.color.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(label.icon,
                                  size: 12, color: label.color),
                              const SizedBox(width: 3),
                              Txt(
                                txt(label.string),
                                style: TextStyle(
                                    color: label.color,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 10),
                              ),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ),
          if (nonEmptyLabels.isNotEmpty)
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: nonEmptyLabels.map((labelTitle) {
                return _buildLabelPill(
                  labelTitle,
                  item,
                  colorsWithoutYellow[
                      getCycledNumber(nonEmptyLabels.indexOf(labelTitle))],
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  int getCycledNumber(int num) {
    return (num - 1) % 7;
  }

  Widget _buildCheckBox(bool isChecked, Patient item) {
    return Transform.scale(
      scale: 1.0,
      child: Checkbox(
        key: Key("dt_cb_${item.id}"),
        checked: isChecked,
        onChanged: (checked) => itemSelectToggle(item, checked),
      ),
    );
  }

  Widget _buildListController() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: _buildItemsNumIndicator()),
          _buildSorters(),
        ],
      ),
    );
  }

  Widget _buildSorters() {
    final treatments =
        txOptions.where((x) => x.type != StateType.state).toList();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
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
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(o.icon, color: o.color, size: 14),
                      const SizedBox(width: 6),
                      Container(
                        decoration: BoxDecoration(
                            color: o.color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: o.color.withValues(alpha: 0.3))),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 2),
                        child: Txt(
                          txt(o.label),
                          style: TextStyle(
                              color: o.color,
                              fontWeight: FontWeight.w600,
                              fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                );
              },
            )
          ],
        ),
        const SizedBox(width: 10),
        _buildSortBy(),
        const SizedBox(width: 6),
        _buildSortDirectionToggle()
      ],
    );
  }

  Widget _buildSortDirectionToggle() {
    final theme = FluentTheme.of(context);
    return Tooltip(
      message: txt("toggleSortDirection"),
      child: IconButton(
        key: WK.toggleSortDirection,
        icon: Icon(
          sortDirection > 0 ? FluentIcons.sort_up : FluentIcons.sort_down,
          size: 16,
          color: theme.accentColor,
        ),
        onPressed: toggleSortDirection,
      ),
    );
  }

  ComboBox<int> _buildSortBy() {
    return ComboBox<int>(
      key: WK.dataTableSortBy,
      items: [
        ComboBoxItem<int>(
          value: -1,
          child: Txt(txt(widget.defaultSortingName)),
        ),
        ...nonNullLabels.map((l) => ComboBoxItem<int>(
              value: nonNullLabels.indexOf(l),
              child: Txt("${txt("by")} ${txt(l)}"),
            ))
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
        if (filtered.isNotEmpty) ..._buildToggleSorters(context),
      ],
    );
  }

  List<Widget> _buildToggleSorters(BuildContext context) {
    final theme = FluentTheme.of(context);
    return [
      ...([widget.defaultSortingName, ...nonNullLabels])
          .map((e) => [
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ToggleButton(
                    checked: sortBy == nonNullLabels.indexOf(e),
                    onChanged: (checked) {
                      if (checked) {
                        setSortBy(nonNullLabels.indexOf(e));
                      } else {
                        toggleSortDirection();
                      }
                    },
                    style: ToggleButtonThemeData(
                      uncheckedButtonStyle: ButtonStyle(
                        backgroundColor:
                            const WidgetStatePropertyAll(Colors.transparent),
                        // border: WidgetStatePropertyAll(BorderSide(
                        //   color: theme.resources.controlStrokeColorDefault,
                        //   width: 1.0,
                        // )),
                      ),
                      checkedButtonStyle: ButtonStyle(
                        backgroundColor: WidgetStatePropertyAll(
                            theme.accentColor.withValues(alpha: 0.15)),
                        foregroundColor:
                            WidgetStatePropertyAll(theme.accentColor),
                        // border: WidgetStatePropertyAll(BorderSide(
                        //   color: theme.accentColor,
                        //   width: 1.5,
                        // )),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Txt(
                          txt(e),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: sortBy == nonNullLabels.indexOf(e)
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        if (sortBy == nonNullLabels.indexOf(e)) ...[
                          const SizedBox(width: 6),
                          Icon(
                            sortDirection > 0
                                ? FluentIcons.sort_up
                                : FluentIcons.sort_down,
                            size: 12,
                            color: theme.accentColor,
                          )
                        ]
                      ],
                    ),
                  ),
                ),
              ])
          .expand((e) => e)
    ];
  }

  Widget _buildCommandBar() {
    final theme = FluentTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: theme.resources.cardBackgroundFillColorDefault,
        border: Border(
          bottom: BorderSide(
            color: theme.resources.cardStrokeColorDefault,
            width: 1.0,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withValues(alpha: 0.025),
            blurRadius: 8,
            offset: const Offset(0, 3),
          )
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: CommandBar(
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
          const SizedBox(width: 10),
          DataTableSearchField(
            onChanged: setSearchTerm,
            placeholder: _searchValue,
          ),
          if (widget.furtherActions.isNotEmpty) ...[
            const SizedBox(width: 8),
            ...widget.furtherActions,
          ],
        ],
      ),
    );
  }

  Widget _buildLabelPill(String l, Patient item, [Color? color]) {
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
    final theme = FluentTheme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: selected
            ? color.withValues(alpha: 0.13)
            : color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title.length > 2) ...[
                  Txt(
                    txt(title).toUpperCase(),
                    style: theme.typography.caption?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 9,
                      letterSpacing: 0.4,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: Container(
                        width: 1,
                        height: 10,
                        color: color.withValues(alpha: 0.35)),
                  ),
                ],
                if (content.contains("."))
                  MoneyDisplay(
                    content,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: theme.resources.textFillColorPrimary,
                    ),
                  )
                else
                  Txt(
                    content,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: theme.resources.textFillColorPrimary,
                    ),
                  ),
              ],
            ),
          ),
          // Selected checkmark badge
          if (selected)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(3),
              ),
              child: const Icon(
                FluentIcons.check_mark,
                size: 9,
                color: Colors.white,
              ),
            ),
        ],
      ),
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
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return SizedBox(
      width: 200,
      height: 32,
      child: CupertinoTextField(
        suffix: _controller.text.isEmpty
            ? null
            : Padding(
                padding: const EdgeInsets.only(right: 6),
                child: GestureDetector(
                  onTap: () {
                    _controller.clear();
                    widget.onChanged("");
                  },
                  child: Icon(
                    FluentIcons.clear,
                    size: 12,
                    color: theme.resources.textFillColorSecondary,
                  ),
                ),
              ),
        key: WK.dataTableSearch,
        placeholder: widget.placeholder.isEmpty
            ? "🔍 ${txt("searchPlaceholder")}"
            : "${txt("filter")}: ${widget.placeholder}",
        placeholderStyle: TextStyle(
          color: theme.resources.textFillColorSecondary,
          fontSize: 13,
        ),
        style: TextStyle(
          color: theme.resources.textFillColorPrimary,
          fontSize: 13,
        ),
        onChanged: widget.onChanged,
        controller: _controller,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2C2C2C) : const Color(0xFFF9F9F9),
          border: Border.all(
            color: theme.resources.controlStrokeColorDefault,
            width: 1.0,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
  }
}

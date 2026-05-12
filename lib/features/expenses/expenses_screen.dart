import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/dialogs/dialog_styling.dart';
import 'package:apexo/common_widgets/dialogs/dialog_with_text_box.dart';
import 'package:apexo/app/routes.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/features/expenses/expense_model.dart';
import 'package:apexo/features/expenses/folder_widget.dart';
import 'package:apexo/features/expenses/order_row.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/archived.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/common_widgets/archive_toggle.dart';
import 'package:apexo/features/expenses/expenses_store.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart' hide TextDirection;

class ExpensesScreen extends StatelessWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      key: WK.expensesScreen,
      padding: EdgeInsets.zero,
      resizeToAvoidBottomInset: true,
      content: MStreamBuilder(
        streams: [expenses.observableMap.stream, showArchived.stream],
        // ignore: prefer_const_constructors
        builder: (context, snapshot) => AdaptiveExpensesView(),
      ),
    );
  }
}

class AdaptiveExpensesView extends StatefulWidget {
  const AdaptiveExpensesView({super.key});

  @override
  State<AdaptiveExpensesView> createState() => _AdaptiveExpensesViewState();
}

class _AdaptiveExpensesViewState extends State<AdaptiveExpensesView> {
  String? selectedSupplierId;
  bool? filterPaid = false; // null = all, true = paid, false = due
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  String justCreatedId = "";

  @override
  void initState() {
    super.initState();
    routes.onBackInterceptor = () {
      if (selectedSupplierId != null) {
        setState(() => selectedSupplierId = null);
        return false; // consumed — don't pop the route
      }
      return true; // nothing to close, proceed normally
    };
  }

  @override
  void dispose() {
    routes.onBackInterceptor = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    if (selectedSupplierId == null) {
      return _buildInitialFolderView(theme);
    }

    return _buildSelectedTimelineView(theme);
  }

  Widget _buildInitialFolderView(FluentThemeData theme) {
    final suppliers = expenses.suppliers;
    final currency = globalSettings.get("currency_______").value;

    return Column(
      children: [
        _buildInitialHeader(theme),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(32),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 120,
              crossAxisSpacing: 15,
              mainAxisSpacing: 15,
              childAspectRatio: 1.1,
            ),
            itemCount: suppliers.length + 2,
            itemBuilder: (context, index) {
              index = index - 1;
              if (index == -1) {
                return _buildAllSupplierFolder(theme);
              }
              if (index == suppliers.length) {
                return _buildAddFolderCard(theme);
              }
              final s = suppliers[index];
              return SupplierFolder(
                supplier: s,
                currency: currency,
                onTap: () => setState(() => selectedSupplierId = s.id),
                onRename: () {
                  _showRenameSupplierDialog(s);
                },
                onArchive: () => expenses
                    .set(s..archived = s.archived == true ? null : true),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildInitialHeader(FluentThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.menuColor,
        border: Border(
            bottom:
                BorderSide(color: theme.resources.dividerStrokeColorDefault)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(WindowsIcons.folder, size: 24),
              const SizedBox(width: 16),
              Text(
                txt("pickASupplier"),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: theme.typography.body?.color,
                ),
              ),
            ],
          ),
          const ArchiveToggle(),
        ],
      ),
    );
  }

  Widget _buildAllSupplierFolder(FluentThemeData theme) {
    return GestureDetector(
      onTap: () => setState(() => selectedSupplierId = ""),
      child: CustomPaint(
        painter: FolderPainter(
          color: theme.inactiveColor.withValues(alpha: .4),
          isDashed: true,
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              const Icon(WindowsIcons.calendar, size: 24),
              const SizedBox(height: 8),
              Text(
                txt("allByDate"),
                style: theme.typography.bodyStrong?.copyWith(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddFolderCard(FluentThemeData theme) {
    return GestureDetector(
      onTap: () => _showAddSupplierDialog(),
      child: CustomPaint(
        painter: FolderPainter(
          color: theme.inactiveColor.withValues(alpha: .4),
          isDashed: true,
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              const Icon(FluentIcons.add, size: 24),
              const SizedBox(height: 8),
              Text(
                txt("addSupplier"),
                style: theme.typography.bodyStrong?.copyWith(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedTimelineView(FluentThemeData theme) {
    // Memoize/Filter orders
    final allOrders = expenses.present.values
        .where((o) => !o.isSupplier)
        .where((o) =>
            (selectedSupplierId ?? "").isEmpty ||
            o.supplierId == selectedSupplierId)
        .where((o) => filterPaid == null || o.processed == filterPaid)
        .where((o) =>
            _searchController.text.isEmpty ||
            o.items.any((i) =>
                i.toLowerCase().contains(_searchController.text.toLowerCase())))
        .toList()
      ..sort((a, b) => b.date.millisecondsSinceEpoch
          .compareTo(a.date.millisecondsSinceEpoch));

    final totalDue =
        allOrders.fold<double>(0, (sum, o) => sum + (o.cost - o.paidAmount));
    final currency = globalSettings.get("currency_______").value;

    return Column(
      children: [
        _buildCommandBar(),
        _buildFilterBar(theme),
        Expanded(
          child: _buildVerticalTimeline(allOrders, theme),
        ),
        _buildSummaryFooter(theme, totalDue, currency),
      ],
    );
  }

  addOrderForSupplier(String supplierId) async {
    final expense = Expense.fromJson({
      "supplierId": supplierId,
      "processed": false,
    });
    expenses.set(expense);
    justCreatedId = expense.id;
    await _scrollController.animateTo(
      _scrollController.position.minScrollExtent,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOut,
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: ButtonContent(FluentIcons.add, txt("addOrder")),
            onPressed: () async {
              if (selectedSupplierId == null) return;
              if (selectedSupplierId!.isNotEmpty) {
                addOrderForSupplier(selectedSupplierId!);
              } else {
                showDialog(
                  barrierDismissible: true,
                  dismissWithEsc: true,
                  context: context,
                  builder: (context) => ContentDialog(
                    style: dialogStyling(context, false),
                    title: Txt("${txt("addOrder")}: ${txt("pickASupplier")}"),
                    content: SizedBox(
                      width: double.maxFinite,
                      height: 300,
                      child: ListView.builder(
                        itemCount: expenses.suppliers.length,
                        itemBuilder: (context, index) {
                          final s = expenses.suppliers[index];
                          return ListTile(
                            title: Text(s.supplierName),
                            onPressed: () {
                              Navigator.pop(context);
                              addOrderForSupplier(s.id);
                            },
                          );
                        },
                      ),
                    ),
                  ),
                );
              }
            },
          ),
          Row(
            children: [
              const Divider(
                size: 20,
                direction: Axis.vertical,
              ),
              Container(
                constraints: const BoxConstraints(maxWidth: 200),
                child: CupertinoTextField(
                  expands: false,
                  decoration: BoxDecoration(
                      color: Colors.transparent,
                      border: Border.all(color: Colors.transparent)),
                  placeholder: "🔍 ${txt("filterByItems")}",
                  controller: _searchController,
                  onChanged: (text) => setState(() {}),
                ),
              ),
              const SizedBox(width: 5),
              const ArchiveToggle(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSupplierRibbon(FluentThemeData theme) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemBuilder: (context, index) {
          index = index - 1;
          if (index == 0) {
            return Row(
              children: [
                Button(
                  style: filledButtonStyle(
                      selectedSupplierId == "" ? Colors.blue : Colors.grey),
                  child: ButtonContent(WindowsIcons.calendar, txt("allByDate")),
                  onPressed: () => setState(() => selectedSupplierId = ""),
                ),
                const SizedBox(width: 8),
              ],
            );
          }
          if (index == -1) {
            return Row(
              children: [
                _buildBackChip(theme),
                const SizedBox(width: 8),
              ],
            );
          }
          final s = expenses.suppliers[index - 1];
          return _buildSupplierChip(s);
        },
        itemCount: MediaQuery.of(context).size.width > 600
            ? expenses.suppliers.length + 2
            : 1,
      ),
    );
  }

  Widget _buildBackChip(FluentThemeData theme) {
    return HyperlinkButton(
      onPressed: () => setState(() => selectedSupplierId = null),
      child: Row(
        children: [
          Transform.flip(
              flipX: locale.isRtl ? false : true,
              child: const Icon(WindowsIcons.move_to_folder, size: 20)),
          const SizedBox(width: 8),
          Txt(txt("back")),
        ],
      ),
    );
  }

  Widget _buildSupplierChip(Expense s) {
    final theme = FluentTheme.of(context);
    final isSelected = selectedSupplierId == s.id;
    final due = s.duePayments;
    final hasDue = due > 0.01;

    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: GestureDetector(
        onTap: () => setState(() => selectedSupplierId = s.id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? theme.accentColor.withAlpha(50)
                : theme.cardColor.withAlpha(150),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? theme.accentColor
                  : (hasDue
                      ? Colors.orange.withAlpha(100)
                      : theme.resources.dividerStrokeColorDefault),
            ),
          ),
          child: Row(
            spacing: 8,
            children: [
              const Icon(WindowsIcons.folder, size: 16),
              Text(
                s.supplierName,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 11,
                  color: theme.typography.body?.color,
                ),
              ),
              if (hasDue) ...[
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                      color: Colors.orange, shape: BoxShape.circle),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterBar(FluentThemeData theme) {
    return Container(
      //width: 300,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        border: Border(
            bottom:
                BorderSide(color: theme.resources.dividerStrokeColorDefault)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: _buildSupplierRibbon(theme)),
          Divider(
            direction: Axis.vertical,
            size: 40,
            style: DividerThemeData(
                decoration:
                    BoxDecoration(color: theme.inactiveColor.withAlpha(50))),
          ),
          const SizedBox(width: 8),
          Row(
            spacing: 3,
            children: [
              _buildFilterChip("due", FluentIcons.warning, filterPaid == false,
                  () => setState(() => filterPaid = false)),
              _buildFilterChip("paid", FluentIcons.completed,
                  filterPaid == true, () => setState(() => filterPaid = true)),
              _buildFilterChip("all", FluentIcons.history, filterPaid == null,
                  () => setState(() => filterPaid = null)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(
      String label, IconData icon, bool isSelected, VoidCallback onTap) {
    final theme = FluentTheme.of(context);
    return Button(
      style: ButtonStyle(
        backgroundColor: WidgetStatePropertyAll(
            isSelected ? theme.accentColor.withAlpha(50) : null),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
                color:
                    isSelected ? theme.accentColor : Colors.grey.withAlpha(50)),
          ),
        ),
      ),
      onPressed: onTap,
      child: Row(
        spacing: 2,
        children: [
          Icon(icon, size: 14),
          Txt(txt(label)),
        ],
      ),
    );
  }

  Widget _buildVerticalTimeline(List<Expense> orders, FluentThemeData theme) {
    if (orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(FluentIcons.receipt_undelivered,
                size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text(txt("noItemsFound"),
                style: const TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    if ((selectedSupplierId ?? "").isNotEmpty) {
      return _simpleGrid(orders, theme);
    } else {
      return _timeLineGrid(orders, theme);
    }
  }

  Widget _timeLineGrid(List<Expense> orders, FluentThemeData theme) {
    final List<List<Expense>> groupedOrders = [];
    if (orders.isNotEmpty) {
      List<Expense> currentGroup = [orders[0]];
      for (int i = 1; i < orders.length; i++) {
        if (isSameDay(orders[i].date, orders[i - 1].date)) {
          currentGroup.add(orders[i]);
        } else {
          groupedOrders.add(currentGroup);
          currentGroup = [orders[i]];
        }
      }
      groupedOrders.add(currentGroup);
    }

    return ListView.builder(
      itemCount: groupedOrders.length,
      padding: const EdgeInsets.only(top: 16, bottom: 40),
      controller: _scrollController,
      itemBuilder: (context, index) {
        final group = groupedOrders[index];
        final date = group[0].date;

        return Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDateHeader(date, theme),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              child: Wrap(
                spacing: 15,
                runSpacing: 15,
                alignment: WrapAlignment.start,
                crossAxisAlignment: WrapCrossAlignment.start,
                runAlignment: WrapAlignment.start,
                children: group.map((order) {
                  return SizedBox(
                    width: 310,
                    child: OrderRow(
                      key: Key(order.id),
                      order: order,
                      supplier: expenses.supplierMap[order.supplierId],
                      justCreated: order.id == justCreatedId,
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _simpleGrid(List<Expense> orders, FluentThemeData theme) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth - 30; // 15 padding on each side
      final crossAxisCount = (width / 310).floor().clamp(1, 10);

      return GridView.builder(
        padding: const EdgeInsets.all(15),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          mainAxisExtent: 455,
          mainAxisSpacing: 15,
          crossAxisSpacing: 15,
        ),
        itemCount: orders.length,
        controller: _scrollController,
        itemBuilder: (context, index) {
          final order = orders[index];

          return OrderRow(
            key: Key(order.id),
            order: order,
            supplier: expenses.supplierMap[order.supplierId],
            justCreated: order.id == justCreatedId,
          );
        },
      );
    });
  }

  Widget _buildDateHeader(DateTime date, FluentThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      child: Row(
        children: [
          Text(
            DateFormat('MMMM d, yyyy', locale.s.$code)
                .format(date)
                .toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
              color: theme.typography.caption?.color?.withAlpha(150),
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }

  Widget _buildSummaryFooter(
      FluentThemeData theme, double totalDue, String currency) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: theme.menuColor,
        border: Border(
            top: BorderSide(color: theme.resources.dividerStrokeColorDefault)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            txt("totalDue"),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: theme.typography.caption?.color,
            ),
          ),
          const SizedBox(width: 16),
          Text(
            "${totalDue.toStringAsFixed(2)} $currency",
            style: TextStyle(
              fontSize: 18,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
              color:
                  totalDue > 0 ? Colors.orange : theme.typography.body?.color,
            ),
          ),
        ],
      ),
    );
  }

  bool isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  void _showRenameSupplierDialog(Expense supplier) {
    showDialog(
      context: context,
      builder: (context) => DialogWithTextBox(
        title: "Rename Supplier",
        initialValue: supplier.supplierName,
        onSave: (name) {
          expenses.set(supplier..supplierName = name);
        },
        icon: FluentIcons.edit,
      ),
    );
  }

  void _showAddSupplierDialog() {
    showDialog(
      context: context,
      builder: (context) => DialogWithTextBox(
        title: "Add Supplier",
        onSave: (name) {
          expenses.set(Expense.fromJson({
            "isSupplier": true,
            "supplierName": name,
          }));
        },
        icon: FluentIcons.shop,
      ),
    );
  }
}

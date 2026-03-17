import 'dart:math';
import 'package:apexo/common_widgets/no_items_found.dart';
import 'package:apexo/features/expenses/expense_model.dart';
import 'package:apexo/features/expenses/order_row.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/cupertino.dart';

class SupplierWindow extends StatefulWidget {
  const SupplierWindow({
    super.key,
    required this.supplier,
    required this.onClose,
    required this.orders,
  });

  final VoidCallback onClose;
  final Expense supplier;
  final List<Expense> orders;

  @override
  State<SupplierWindow> createState() => _SupplierWindowState();
}

class _SupplierWindowState extends State<SupplierWindow> {
  int selectedTab = 0;
  int _page = 0;
  int _rowsPerPage = 10;
  bool _sortAsc = true;
  final TextEditingController _query = TextEditingController();

  List<Expense> get _unpaidList {
    return widget.orders.where((item) => !item.processed).toList();
  }

  List<Expense> get _paidList {
    return widget.orders.where((item) => item.processed).toList();
  }

  List<Expense> get _selectedList {
    if (selectedTab == 0) return _unpaidList;
    return _paidList;
  }

  List<Expense> get _filteredList {
    return _selectedList
        .where((e) =>
            e.items.join(" ").toLowerCase().contains(_query.text.toLowerCase()))
        .toList();
  }

  List<Expense> get _sortedList {
    return _filteredList
      ..sort((a, b) =>
          _sortAsc ? a.date.compareTo(b.date) : b.date.compareTo(a.date));
  }

  List<Expense> get _pageItems {
    return _sortedList.skip(_page * _rowsPerPage).take(_rowsPerPage).toList();
  }

  double get _totalSums {
    return _sortedList.fold<double>(
        0, (s, e) => s + (selectedTab == 0 ? e.cost : e.paidAmount));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: FluentTheme.of(context).inactiveBackgroundColor,
      child: TabView(
        header: Container(
          color: Colors.grey.withAlpha(60),
          child: Text(
            widget.supplier.supplierName,
            style: FluentTheme.of(context).typography.caption,
          ),
        ),
        footer: Padding(
          padding: const EdgeInsetsGeometry.symmetric(horizontal: 5),
          child: IconButton(
            style: const ButtonStyle(
              backgroundColor: WidgetStatePropertyAll(Colors.errorPrimaryColor),
              foregroundColor: WidgetStatePropertyAll(Colors.white),
            ),
            icon: const Icon(FluentIcons.cancel),
            onPressed: widget.onClose,
          ),
        ),
        currentIndex: selectedTab,
        onChanged: (i) {
          setState(() {
            selectedTab = i;
          });
        },
        tabs: [
          _buildTab(
            icon: FluentIcons.file_request,
            title: txt("unpaidOrders"),
          ),
          _buildTab(
            icon: FluentIcons.fabric_folder_confirm,
            title: txt("paymentHistory"),
          ),
        ],
      ),
    );
  }

  Tab _buildTab({required String title, required IconData icon}) {
    return Tab(
      text: Txt(title),
      body: LayoutBuilder(builder: (context, constraints) {
        return Container(
          decoration: BoxDecoration(color: FluentTheme.of(context).cardColor),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(7, 7, 7, 0),
                child: CupertinoTextField(
                  expands: false,
                  prefix: const Text(" 🔍"),
                  placeholder: txt("filterByItems"),
                  controller: _query,
                  onChanged: (i) => setState(() {}),
                ),
              ),
              const SizedBox(height: 5),
              Expanded(
                child: HorizontalScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: _selectedList.isEmpty ? 300 : 800,
                      maxWidth: _selectedList.isEmpty
                          ? 300
                          : max(constraints.maxWidth, 800),
                    ),
                    child: _buildTable(),
                  ),
                ),
              ),
              _footer(_filteredList.length, _totalSums),
            ],
          ),
        );
      }),
      icon: Icon(icon),
    );
  }

  Column _buildTable() {
    return Column(
      children: [
        _selectedList.isEmpty ? const NoItemsFound() : _buildTableHeader(),
        Expanded(
          child: ListView.builder(
            itemCount: _pageItems.length,
            itemBuilder: (context, index) {
              final order = _pageItems[index];
              return OrderRow(
                key: Key(order.id),
                order: order,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTableHeader() {
    return Container(
      decoration: BoxDecoration(
        border: BoxBorder.fromLTRB(
          top: BorderSide(color: Colors.grey.withAlpha(20)),
          bottom: BorderSide(color: Colors.grey.withAlpha(40)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(7, 14, 7, 14),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => setState(() => _sortAsc = !_sortAsc),
            child: SizedBox(
              width: 125,
              child: _buildTableHeaderText(
                  _sortAsc ? "${txt("date")} ↑" : '${txt("date")} ↓'),
            ),
          ),
          Expanded(child: _buildTableHeaderText(txt("items"))),
          SizedBox(
              width: 85,
              child: _buildTableHeaderText(txt("cost"), centerAlign: false)),
          SizedBox(
              width: 85,
              child: _buildTableHeaderText(txt("paid"), centerAlign: false)),
          SizedBox(
              width: 85,
              child: _buildTableHeaderText(txt("photos"), centerAlign: false)),
          const SizedBox(width: 60),
        ],
      ),
    );
  }

  Widget _buildTableHeaderText(String text,
      {bool alignToRight = false, bool centerAlign = false}) {
    return Align(
      alignment: alignToRight
          ? AlignmentDirectional.centerEnd
          : centerAlign
              ? AlignmentDirectional.center
              : AlignmentDirectional.centerStart,
      child: Txt(
        text,
        style: FluentTheme.of(context).typography.bodyStrong,
      ),
    );
  }

  Widget _footer(int totalRows, double totalCost) {
    final totalPages = (totalRows / _rowsPerPage).ceil();

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
              color: FluentTheme.of(context).shadowColor.withAlpha(30)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildShowingDropdown(),
          _buildPagainationButtons(totalPages),
          _buildTotalFooter(totalCost)
        ],
      ),
    );
  }

  Txt _buildTotalFooter(double totalCost) {
    return Txt(
      '${txt("total")}: ${totalCost.toStringAsFixed(2)} ${globalSettings.get("currency_______").value}',
      style: FluentTheme.of(context).typography.bodyStrong,
    );
  }

  Row _buildPagainationButtons(int totalPages) {
    return Row(
      textDirection: TextDirection.ltr,
      children: [
        IconButton(
          icon: const Icon(FluentIcons.chevron_left),
          onPressed: _page > 0 ? () => setState(() => _page--) : null,
        ),
        Text('${_page + 1} / $totalPages'),
        IconButton(
          icon: const Icon(FluentIcons.chevron_right),
          onPressed:
              _page < totalPages - 1 ? () => setState(() => _page++) : null,
        ),
      ],
    );
  }

  Row _buildShowingDropdown() {
    return Row(
      children: [
        Txt(txt("showing")),
        const SizedBox(width: 5),
        ComboBox<int>(
          value: _rowsPerPage,
          items: [10, 20, 50]
              .map((e) => ComboBoxItem(value: e, child: Text('$e')))
              .toList(),
          onChanged: (v) => setState(() {
            _rowsPerPage = v!;
            _page = 0;
          }),
        ),
        const SizedBox(width: 5),
      ],
    );
  }
}

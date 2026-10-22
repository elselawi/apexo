import 'dart:async';
import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/widget_keys.dart';
import 'package:apexo/common_widgets/context_menu_region.dart';
import 'package:apexo/common_widgets/delete_button.dart';
import 'package:apexo/common_widgets/dialogs/dialog_with_text_box.dart';
import 'package:apexo/common_widgets/money_display.dart';
import 'package:apexo/common_widgets/screen_command_bar.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/features/expenses/expense_model.dart';
import 'package:apexo/features/expenses/expense_actions.dart';
import 'package:apexo/features/expenses/open_expense_panel.dart';
import 'package:apexo/features/expenses/scan_receipt_dialog.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/features/expenses/expenses_store.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/network.dart';
import 'package:apexo/utils/constants.dart';
import 'package:apexo/utils/flyout_focus_fix.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:image_picker/image_picker.dart';

class ExpensesScreen extends StatelessWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MStreamBuilder(
      streams: [expenses.observableMap.stream],
      // ignore: prefer_const_constructors
      builder: (context, snapshot) => SuppliersList(),
    );
  }
}

class SuppliersList extends StatefulWidget {
  const SuppliersList({super.key});

  @override
  State<SuppliersList> createState() => _SuppliersListState();
}

class _SuppliersListState extends State<SuppliersList> {
  final TextEditingController _searchController = TextEditingController();
  final FlyoutController _scanFlyout = FlyoutController();
  bool _scanning = false;

  @override
  void dispose() {
    _scanFlyout.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ScreenCommandBar(
              mainButton: IconButton(
                key: WK.btnNewSupplier,
                icon: ButtonContent(WindowsIcons.add, txt("addSupplier")),
                onPressed: _showAddSupplierDialog,
              ),
              otherButtons:
                  globalSettings.aiServicesEnabled && network.isOnline()
                      ? [_buildScanButton(context)]
                      : [],
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: _buildSearch(),
            ),
            LayoutBuilder(
              builder: (context, constraints) => Container(
                decoration: topBarDecoration(context, Colors.grey),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(8),
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minWidth: constraints.maxWidth - 16),
                    child: Row(
                      spacing: 10,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Button(
                          child: ButtonContent(
                              WindowsIcons.text_bullet_list_square,
                              txt("viewAllOrders")),
                          onPressed: () {
                            unawaited(openExpenses(
                              expenses.allOrders,
                              txt("viewAllOrders"),
                              null,
                            ));
                          },
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Txt("${txt("total")}: ",
                                style: FluentTheme.of(context)
                                    .typography
                                    .caption
                                    ?.copyWith(fontWeight: FontWeight.w500)),
                            _DuePaymentAmount(due: expenses.totalDue),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _buildSuppliersView(theme),
            ),
          ],
        ),
      ],
    );
  }

  FlyoutTarget _buildScanButton(BuildContext context) {
    return FlyoutTarget(
      controller: _scanFlyout,
      child: IconButton(
        style: _scanning
            ? ButtonStyle(
                backgroundColor: WidgetStatePropertyAll(FluentTheme.of(context)
                    .resources
                    .dividerStrokeColorDefault),
              )
            : null,
        icon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_scanning)
              const SizedBox(
                width: 16,
                height: 16,
                child: ProgressRing(strokeWidth: 2),
              )
            else
              const Icon(FluentIcons.generic_scan),
            const SizedBox(width: 8),
            Txt(txt("scanReceipt")),
          ],
        ),
        onPressed: _scanning
            ? null
            : () async {
                final suppGallery =
                    ImagePicker().supportsImageSource(ImageSource.gallery);
                final suppCamera =
                    ImagePicker().supportsImageSource(ImageSource.camera);

                if (suppGallery && !suppCamera) {
                  _scanReceipt(context, ImageSource.gallery);
                  return;
                }
                if (!suppGallery && suppCamera) {
                  _scanReceipt(context, ImageSource.camera);
                  return;
                }

                await flyoutFocusFix(context);
                unawaited(_scanFlyout.showFlyout(
                    builder: (ctx) => MenuFlyout(
                          items: [
                            if (suppGallery)
                              MenuFlyoutItem(
                                text: Txt(txt("upload")),
                                leading: const Icon(FluentIcons.upload),
                                onPressed: () =>
                                    _scanReceipt(context, ImageSource.gallery),
                              ),
                            if (suppCamera)
                              MenuFlyoutItem(
                                text: Txt(txt("camera")),
                                leading: const Icon(FluentIcons.camera),
                                onPressed: () =>
                                    _scanReceipt(context, ImageSource.camera),
                              ),
                          ],
                        )));
              },
      ),
    );
  }

  Widget _buildSuppliersView(FluentThemeData theme) {
    final searchTerm = _searchController.text.toLowerCase();
    final suppliers = expenses.suppliers
        .where((e) => e.supplierName.toLowerCase().contains(searchTerm))
        .toList();

    return ListView.builder(
      itemExtent: 80,
      itemCount: suppliers.length,
      padding: EdgeInsets.zero,
      itemBuilder: (context, index) {
        final supplier = suppliers[index];
        return SupplierListTile(
            supplier: supplier,
            onOpen: (window) {
              unawaited(openExpenses(
                expenses.ordersPerSupplier[supplier.id]!,
                supplier.supplierName,
                supplier.id,
                null,
                window,
              ));
            });
      },
    );
  }

  Widget _buildSearch() {
    return TopSearch(controller: _searchController, setState: setState);
  }

  void _showAddSupplierDialog() {
    unawaited(showDialog(
      barrierDismissible: true,
      dismissWithEsc: true,
      context: context,
      builder: (context) => DialogWithTextBox(
        title: txt("addSupplier"),
        onSave: (name) {
          expenses.set(Expense.fromJson({
            "isSupplier": true,
            "supplierName": name,
          }));
        },
        icon: FluentIcons.shop,
      ),
    ));
  }

  void _scanReceipt(BuildContext outerContext, ImageSource source) async {
    setState(() => _scanning = true);
    try {
      await showScanReceiptDialog(outerContext, source);
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }
}

class SupplierListTile extends StatefulWidget {
  const SupplierListTile({
    super.key,
    required this.supplier,
    required this.onOpen,
  });

  final Expense supplier;

  /// Opens the supplier's orders: the panel, or one of its windows when a menu
  /// item names it — [expenseWindows] is the same list the panel builds from,
  /// so the two cannot drift.
  final void Function(ExpenseWindow? window) onOpen;

  @override
  State<SupplierListTile> createState() => _SupplierListTileState();
}

class _SupplierListTileState extends State<SupplierListTile> {
  final FlyoutController menuController = FlyoutController();
  final bool canEdit = login.perm(Perm.expenses).exact(2);

  @override
  void dispose() {
    menuController.dispose();
    super.dispose();
  }

  String get df => localSettings.dateFormat.startsWith("d") == true
      ? "dd/MM/yyyy"
      : "MM/dd/yyyy";

  @override
  Widget build(BuildContext context) {
    final due = widget.supplier.duePayments;
    final orders = expenses.ordersPerSupplier[widget.supplier.id] ?? [];
    final captionStyle = FluentTheme.of(context).typography.caption;

    return ContextMenuRegion(
      items: (ctx, controller) => _menuItems(controller),
      child: ListTile(
        margin: EdgeInsets.zero,
        contentPadding: const EdgeInsetsGeometry.all(8),
        shape: listDividerBorder(context),
        tileColor: WidgetStatePropertyAll(
            FluentTheme.of(context).resources.solidBackgroundFillColorBase),
        leading: _buildContextMenuButton(context),
        trailing: _DuePaymentAmount(due: due),
        title: _buildSupplierName(orders, captionStyle),
        onPressed: () => widget.onOpen(null),
      ),
    );
  }

  Widget _buildSupplierName(List<Expense> orders, TextStyle? captionStyle) {
    return Row(spacing: 6, children: [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            spacing: 5,
            children: [
              const Icon(WindowsIcons.folder),
              Text(widget.supplier.supplierName),
            ],
          ),
          if (orders.isNotEmpty)
            Txt(
              "${txt("lastOrder")}: ${DateTime.now().difference(orders.first.date).inDays.toString()} ${txt("daysAgo")}",
              style: captionStyle,
            )
        ],
      )
    ]);
  }

  FlyoutTarget _buildContextMenuButton(BuildContext context) {
    return FlyoutTarget(
      controller: menuController,
      child: IconButton(
          icon: const Icon(WindowsIcons.more),
          onPressed: () async {
            await flyoutFocusFix(context);
            unawaited(menuController.showFlyout(builder: (context) {
              return MenuFlyout(
                items: _menuItems(menuController),
              );
            }));
          }),
    );
  }

  /// The supplier's actions, shared by the "more" button and by long press /
  /// right click on the whole row: one item per window of the orders panel,
  /// then the editing actions.
  ///
  /// [controller] is the menu's own controller, so the delete confirmation opens
  /// where the menu was.
  List<MenuFlyoutItemBase> _menuItems(FlyoutController controller) {
    final orders = expenses.ordersPerSupplier[widget.supplier.id] ?? [];
    // The same split the due and paid windows make — and the same one they
    // filter by: a count that includes an archived order says there is an
    // order in the list that is not there.
    final live = orders.where((order) => order.archived != true).toList();
    final due = live.where((order) => order.processed == false).length;
    final paid = live.where((order) => order.processed == true).length;
    return [
      MenuFlyoutItem(
        text: menuTitleSuffix(
          Txt(txt("orders")),
          menuCountSuffix(live.length),
        ),
        leading: const Icon(FluentIcons.receipt_processing),
        onPressed: () => widget.onOpen(null),
      ),
      for (final window in expenseWindows())
        MenuFlyoutItem(
          text: menuTitleSuffix(
            Txt(txt(window.titleKey)),
            menuCountSuffix(
              window == ExpenseWindow.due ? due : paid,
            ),
          ),
          leading: Icon(window.icon),
          onPressed: () => widget.onOpen(window),
        ),
      if (canEdit) const MenuFlyoutSeparator(),
      if (canEdit)
        MenuFlyoutItem(
          text: Txt(txt("rename")),
          leading: const Icon(WindowsIcons.edit),
          onPressed: () {
            controller.close<void>();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              unawaited(renameSupplierDialog(context, widget.supplier.id));
            });
          },
        ),
      if (canEdit)
        confirmDeleteMenuItem(
          controller: controller,
          preview: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 5,
            children: [
              const Icon(WindowsIcons.folder),
              Txt("${txt("supplier")}: ${widget.supplier.supplierName}")
            ],
          ),
          onConfirm: () {
            expenses.archive(widget.supplier.id);
          },
        ),
    ];
  }
}

class _DuePaymentAmount extends StatelessWidget {
  const _DuePaymentAmount({required this.due});

  final double due;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      height: 30,
      decoration: BoxDecoration(
        color: due > 0 ? Colors.orange.withAlpha(50) : null,
        borderRadius: BorderRadius.circular(5),
      ),
      child: due > 0
          ? Row(
              spacing: 5,
              children: [
                //const Icon(WindowsIcons.warning),
                MoneyDisplay(
                  "${due.toStringAsFixed(2)} ${currency()}",
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            )
          : const SizedBox.shrink(),
    );
  }
}

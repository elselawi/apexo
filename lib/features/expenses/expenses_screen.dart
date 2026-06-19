import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/delete_button.dart';
import 'package:apexo/common_widgets/dialogs/dialog_with_text_box.dart';
import 'package:apexo/common_widgets/money_display.dart';
import 'package:apexo/common_widgets/screen_command_bar.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/features/accounts/open_account_panel.dart';
import 'package:apexo/features/expenses/expense_model.dart';
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
          children: [
            ScreenCommandBar(
                mainButton: IconButton(
                  icon: ButtonContent(WindowsIcons.add, txt("addSupplier")),
                  onPressed: _showAddSupplierDialog,
                ),
                otherButtons: globalSettings.aiServicesEnabled &&
                        network.isOnline()
                    ? [
                        FlyoutTarget(
                          controller: _scanFlyout,
                          child: IconButton(
                            style: _scanning
                                ? ButtonStyle(
                                    backgroundColor: WidgetStatePropertyAll(
                                        FluentTheme.of(context)
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
                                    final suppGallery = ImagePicker()
                                        .supportsImageSource(
                                            ImageSource.gallery);
                                    final suppCamera = ImagePicker()
                                        .supportsImageSource(
                                            ImageSource.camera);

                                    if (suppGallery && !suppCamera) {
                                      _scanReceipt(
                                          context, ImageSource.gallery);
                                      return;
                                    }
                                    if (!suppGallery && suppCamera) {
                                      _scanReceipt(context, ImageSource.camera);
                                      return;
                                    }

                                    await flyoutFocusFix(context);
                                    _scanFlyout.showFlyout(
                                        builder: (ctx) => MenuFlyout(
                                              items: [
                                                if (suppGallery)
                                                  MenuFlyoutItem(
                                                    text: Txt(txt("upload")),
                                                    leading: const Icon(
                                                        FluentIcons.upload),
                                                    onPressed: () =>
                                                        _scanReceipt(
                                                            context,
                                                            ImageSource
                                                                .gallery),
                                                  ),
                                                if (suppCamera)
                                                  MenuFlyoutItem(
                                                    text: Txt(txt("camera")),
                                                    leading: const Icon(
                                                        FluentIcons.camera),
                                                    onPressed: () =>
                                                        _scanReceipt(context,
                                                            ImageSource.camera),
                                                  ),
                                              ],
                                            ));
                                  },
                          ),
                        ),
                      ]
                    : []),
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Button(
                    child: ButtonContent(WindowsIcons.text_bullet_list_square,
                        txt("viewAllOrders")),
                    onPressed: () {
                      openExpenses(
                        expenses.allOrders,
                        txt("viewAllOrders"),
                        null,
                      );
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
            Expanded(
              child: _buildSuppliersView(theme),
            ),
          ],
        ),
      ],
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
            onPressed: () {
              openExpenses(
                expenses.ordersPerSupplier[supplier.id]!,
                supplier.supplierName,
                supplier.id,
              );
            });
      },
    );
  }

  Expanded _buildSearch() {
    return Expanded(
      child: TopSearch(controller: _searchController, setState: setState),
    );
  }

  void _showAddSupplierDialog() {
    showDialog(
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
    );
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
    required this.onPressed,
  });

  final Expense supplier;
  final VoidCallback onPressed;

  @override
  State<SupplierListTile> createState() => _SupplierListTileState();
}

class _SupplierListTileState extends State<SupplierListTile> {
  final FlyoutController menuController = FlyoutController();
  final FlyoutController archiveConfirmationController = FlyoutController();
  final bool canEdit = login.permissions[PInt.expenses] == 2;

  @override
  void dispose() {
    menuController.dispose();
    archiveConfirmationController.dispose();
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

    return ListTile(
      margin: EdgeInsets.zero,
      contentPadding: const EdgeInsetsGeometry.all(8),
      shape: listDividerBorder(context),
      tileColor: WidgetStatePropertyAll(
          FluentTheme.of(context).resources.solidBackgroundFillColorBase),
      leading: _buildContextMenuButton(context),
      trailing: _DuePaymentAmount(due: due),
      title: _buildSupplierName(orders, captionStyle),
      onPressed: widget.onPressed,
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
              FlyoutTarget(
                controller: archiveConfirmationController,
                child: Text(widget.supplier.supplierName),
              ),
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

  FlyoutTarget _buildContextMenuButton(context) {
    return FlyoutTarget(
      controller: menuController,
      child: IconButton(
          icon: const Icon(WindowsIcons.more),
          onPressed: () async {
            await flyoutFocusFix(context);
            menuController.showFlyout(builder: (context) {
              return MenuFlyout(
                items: [
                  MenuFlyoutItem(
                    text: Txt(txt("open")),
                    leading: const Icon(WindowsIcons.open_in_new_window),
                    onPressed: widget.onPressed,
                  ),
                  if (canEdit)
                    MenuFlyoutItem(
                      text: Txt(txt("rename")),
                      leading: const Icon(WindowsIcons.edit),
                      onPressed: () {
                        menuController.close();
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _showRenameSupplierDialog(context, widget.supplier);
                        });
                      },
                    ),
                  if (canEdit)
                    MenuFlyoutItem(
                      text: Txt(txt("delete")),
                      leading: const Icon(WindowsIcons.delete),
                      onPressed: () {
                        menuController.close();
                        WidgetsBinding.instance.addPostFrameCallback((_) async {
                          await flyoutFocusFix(context);
                          archiveConfirmationController.showFlyout(
                              builder: (ctx) => ConfirmDeleteFlyout(
                                  restorable: true,
                                  controller: archiveConfirmationController,
                                  actionIcon: WindowsIcons.delete,
                                  actionText: txt("delete"),
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
                                  }));
                        });
                      },
                    ),
                ],
              );
            });
          }),
    );
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
                const Icon(WindowsIcons.warning),
                MoneyDisplay("${due.toStringAsFixed(2)} ${currency()}"),
              ],
            )
          : const SizedBox.shrink(),
    );
  }
}

void _showRenameSupplierDialog(BuildContext context, Expense supplier) {
  showDialog(
    context: context,
    barrierDismissible: true,
    dismissWithEsc: true,
    builder: (context) => DialogWithTextBox(
      title: txt("rename"),
      initialValue: supplier.supplierName,
      onSave: (name) {
        expenses.set(supplier..supplierName = name);
      },
      icon: FluentIcons.edit,
    ),
  );
}

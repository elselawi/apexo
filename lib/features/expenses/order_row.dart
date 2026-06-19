import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/date_time_picker.dart';
import 'package:apexo/common_widgets/delete_button.dart';
import 'package:apexo/common_widgets/error_dialog.dart';
import 'package:apexo/common_widgets/grid_gallery.dart';
import 'package:apexo/common_widgets/money_display.dart';
import 'package:apexo/common_widgets/small_label.dart';
import 'package:apexo/common_widgets/tag_input.dart';
import 'package:apexo/features/expenses/expense_model.dart';
import 'package:apexo/features/expenses/expenses_store.dart';
import 'package:apexo/services/ai_services/receipt_scanner.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/network.dart';
import 'package:apexo/utils/constants.dart';
import 'package:apexo/utils/flyout_focus_fix.dart';
import 'package:apexo/utils/imgs.dart';
import 'package:apexo/utils/logger.dart';
import 'package:apexo/utils/money_editing_controller.dart';
import 'package:apexo/utils/money_input_formatter.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:image_picker/image_picker.dart';

class OrderRow extends StatefulWidget {
  const OrderRow({
    super.key,
    required this.order,
    this.justCreated = false,
    this.editableSupplier = false,
    this.showContextMenu = true,
    this.showPhotosSection = true,
    this.strictSupplierInput = false,
    this.additionalSupplier,
    this.supplierNameError = false,
  });
  final Expense order;
  final bool justCreated;
  final bool editableSupplier;
  final bool strictSupplierInput;
  final bool showContextMenu;
  final bool showPhotosSection;
  final Expense? additionalSupplier;
  final bool supplierNameError;

  @override
  State<OrderRow> createState() => OrderRowState();
}

class OrderRowState extends State<OrderRow>
    with SingleTickerProviderStateMixin {
  final MoneyEditingController costCtrl = MoneyEditingController();
  final MoneyEditingController paidCtrl = MoneyEditingController();
  final TextEditingController notesController = TextEditingController();
  final FlyoutController moreOptionsCtrl = FlyoutController();
  final FlyoutController photoAddMenu = FlyoutController();
  final FlyoutController deleteConfirmCtrl = FlyoutController();
  final bool canEdit = login.permissions[PInt.expenses] == 2;

  bool inProgress = false;

  /// Notifier for the per-order "total due" calculation so the
  /// [MoneyDisplay] updates in real-time without rebuilding the whole card
  /// (which would cause photo flicker).
  final ValueNotifier<double> _totalDueNotifier = ValueNotifier(0);

  late AnimationController _pulseController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    costCtrl.text = moneyInputFormatter.formatDouble(widget.order.cost);
    paidCtrl.text = moneyInputFormatter.formatDouble(widget.order.paidAmount);
    notesController.text = widget.order.notes;
    _totalDueNotifier.value = widget.order.cost - widget.order.paidAmount;
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.04), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.04, end: 1.0), weight: 80),
    ]).animate(
        CurvedAnimation(parent: _pulseController, curve: Curves.easeOut));

    super.initState();

    if (widget.justCreated) {
      _pulseController.forward();
    }
  }

  @override
  void dispose() {
    _totalDueNotifier.dispose();
    _pulseController.dispose();
    costCtrl.dispose();
    paidCtrl.dispose();
    notesController.dispose();
    moreOptionsCtrl.dispose();
    photoAddMenu.dispose();
    deleteConfirmCtrl.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final supplier = expenses.suppliers.firstWhere(
        (s) => s.id == widget.order.supplierId,
        orElse: () => Expense.fromJson({"supplierName": "Unknown"}));

    final card = Container(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(5)),
        color: FluentTheme.of(context).micaBackgroundColor,
        boxShadow: const [
          BoxShadow(
            offset: Offset(0.0, 8.0),
            blurRadius: 17.0,
            spreadRadius: 2.0,
            color: Color.fromARGB(14, 0, 0, 0),
          ),
          BoxShadow(
            offset: Offset(0.0, 5.0),
            blurRadius: 22.0,
            spreadRadius: 4.0,
            color: Color(0x1F000000),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          children: [
            Positioned(
              top: 5,
              right: 5,
              child: Row(
                spacing: 5,
                children: [
                  if (widget.justCreated)
                    SmallLabel(
                      label: txt("new"),
                      textColor: Colors.black,
                      bgColor: Colors.yellow,
                      icon: FluentIcons.clock,
                    ),
                  if (widget.order.date.month == DateTime.now().month &&
                      widget.order.date.year == DateTime.now().year)
                    SmallLabel(
                      label: txt("thisMonth"),
                      textColor: theme.inactiveColor,
                      bgColor: Colors.green.withValues(alpha: 0.1),
                      icon: FluentIcons.clock,
                    ),
                  if (widget.order.archived == true)
                    SmallLabel(
                      label: txt("deleted"),
                      textColor: Colors.white,
                      bgColor: Colors.grey,
                      icon: WindowsIcons.delete,
                    ),
                ],
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              mainAxisSize: MainAxisSize.max,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildReceiptHeader(supplier),
                    const DashedLine(),
                    _buildReceiptBody(),
                    const DashedLine(),
                    _buildReceiptFooter(),
                  ],
                ),
              ],
            ),
            if (widget.order.processed) _buildPaidStamp(),
          ],
        ),
      ),
    );

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        if (!widget.justCreated || _pulseController.value == 0) {
          return Center(child: card);
        }

        final flashColor = Color.lerp(
          theme.accentColor,
          theme.accentColor.withValues(alpha: 0),
          _pulseController.value,
        )!;

        return Center(
          child: Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: flashColor, width: 2),
                boxShadow: [
                  if (_pulseController.value < 1.0)
                    BoxShadow(
                      color: flashColor.withValues(alpha: 0.3),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                ],
              ),
              child: card,
            ),
          ),
        );
      },
    );
  }

  Widget _buildReceiptHeader(Expense supplier) {
    final theme = FluentTheme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 15),
          Row(
            spacing: 8,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: widget.editableSupplier
                    ? _buildEditableSupplier()
                    : _buildSupplierName(supplier, theme),
              ),
              if (canEdit && widget.showContextMenu) _buildMoreButton(),
            ],
          ),
          const SizedBox(height: 8),
          DateTimePicker(
            initValue: widget.order.date,
            onChange: (v) {
              widget.order.date = v;
            },
            enabled: canEdit,
            showButton: true,
            buttonText: txt("change"),
            buttonIcon: WindowsIcons.calendar,
            pickTime: false,
            textStyle: theme.typography.bodyStrong?.copyWith(
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditableSupplier() {
    if (widget.strictSupplierInput) {
      return _comboBoxSupplier();
    } else {
      return Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: widget.supplierNameError ? Colors.red : Colors.transparent,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: TagInputWidget(
          limit: 1,
          multiline: false,
          enabled: !inProgress && canEdit,
          strict: false,
          initialValue: [
            ...expenses.suppliers,
            if (widget.additionalSupplier != null) widget.additionalSupplier!
          ]
              .where((s) => s.id == widget.order.supplierId)
              .map((s) => TagInputItem(value: s.id, label: s.supplierName))
              .toList(),
          onChanged: (suppliers) {
            setState(() {
              if (suppliers.isEmpty) {
                widget.order.supplierId = '';
              } else {
                widget.order.supplierId = suppliers.first.value ?? "";
              }
            });
          },
          placeholder: txt("supplier"),
          suggestions: _supplierSuggestions(),
        ),
      );
    }
  }

  List<TagInputItem> _supplierSuggestions() {
    final existingIds = expenses.suppliers.map((s) => s.id).toSet();
    final items = expenses.suppliers
        .map((s) => TagInputItem(value: s.id, label: s.supplierName))
        .toList();

    if (widget.additionalSupplier != null &&
        !existingIds.contains(widget.additionalSupplier!.id)) {
      items.insert(
          0,
          TagInputItem(
              value: widget.additionalSupplier!.id,
              label: widget.additionalSupplier!.supplierName));
    }

    return items;
  }

  Widget _comboBoxSupplier() {
    return ComboBox<String>(
      value: widget.order.supplierId,
      onChanged: (newValue) {
        setState(() {
          widget.order.supplierId = newValue ?? '';
        });
      },
      items: expenses.suppliers
          .map((s) => ComboBoxItem(
                value: s.id,
                child: Text(s.supplierName),
              ))
          .toList(),
    );
  }

  Text _buildSupplierName(Expense supplier, FluentThemeData theme) {
    return Text(
      supplier.supplierName.toUpperCase(),
      style: TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 14,
        letterSpacing: 1.2,
        color: theme.typography.body?.color,
      ),
    );
  }

  TextStyle _sectionTitleTextStyle(FluentThemeData theme) => TextStyle(
        fontSize: 9,
        letterSpacing: 0.5,
        fontWeight: FontWeight.bold,
        color: theme.typography.caption?.color?.withAlpha(120),
      );

  Widget _buildReceiptBody() {
    final theme = FluentTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                txt("items").toUpperCase(),
                style: _sectionTitleTextStyle(theme).copyWith(
                  fontSize: 14,
                ),
              ),
              if (widget.order.items.isEmpty)
                SmallLabel(
                  label: txt("empty"),
                  textColor: Colors.white,
                  bgColor: Colors.warningPrimaryColor,
                  icon: FluentIcons.warning,
                ),
            ],
          ),
          const SizedBox(height: 8),
          _buildItemsInput(),
          if ((canEdit && !inProgress) &&
              network.isOnline() &&
              globalSettings.aiServicesEnabled &&
              widget.order.photos.isNotEmpty &&
              widget.order.items.isEmpty) ...[
            const SizedBox(height: 3),
            Button(
              onPressed: _readFromPhoto,
              child: ButtonContent(
                WindowsIcons.lightbulb,
                txt("readFromPhoto"),
              ),
            )
          ],
          const SizedBox(height: 8),
          Text(
            txt("notes").toUpperCase(),
            style: _sectionTitleTextStyle(theme).copyWith(
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 3),
          CupertinoTextField(
            placeholder: txt("notes"),
            enabled: canEdit && !inProgress,
            controller: notesController,
            maxLines: null,
            onChanged: (value) {
              widget.order.notes = value;
            },
          ),
          if (widget.showPhotosSection) ...[
            const SizedBox(height: 12),
            _buildPhotosSection(),
          ]
        ],
      ),
    );
  }

  Widget _buildReceiptFooter() {
    final theme = FluentTheme.of(context);
    final curr = currency();
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildReceiptRow(
                  "due",
                  widget.order.cost,
                  curr,
                  isEditable: true,
                  controller: costCtrl,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildReceiptRow(
                  "paid",
                  widget.order.paidAmount,
                  curr,
                  isEditable: true,
                  controller: paidCtrl,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const DashedLine(thickness: 0.5),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Text(
                txt("totalDue").toUpperCase(),
                style: _sectionTitleTextStyle(theme),
              ),
              ValueListenableBuilder<double>(
                valueListenable: _totalDueNotifier,
                builder: (context, totalDue, _) {
                  return MoneyDisplay(
                    "${totalDue.toStringAsFixed(2)} $curr",
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: theme.typography.body?.color,
                    ),
                  );
                },
              ),
              if (widget.order.cost == 0)
                SmallLabel(
                  label: txt("notSet"),
                  textColor: Colors.white,
                  bgColor: Colors.warningPrimaryColor,
                  icon: FluentIcons.warning,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReceiptRow(String label, double amount, String currency,
      {bool isEditable = false, TextEditingController? controller}) {
    final theme = FluentTheme.of(context);

    return CupertinoTextField(
      prefix: Row(
        spacing: 5,
        children: [
          const SizedBox.shrink(),
          Txt(
            txt(label).toUpperCase(),
            style: _sectionTitleTextStyle(theme),
          ),
          Txt(
            currency,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: theme.typography.body?.color,
            ),
          ),
        ],
      ),
      enabled: canEdit && isEditable && !inProgress,
      controller: controller,
      textAlign: TextAlign.end,
      placeholder: "0.00",
      readOnly: !canEdit,
      keyboardType: TextInputType.number,
      inputFormatters: [moneyInputFormatter],
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: 14,
        color: theme.typography.body?.color,
      ),
      onChanged: (v) {
        final val = moneyInputFormatter.parse(v);
        if (label == "due") {
          widget.order.cost = val;
        } else {
          widget.order.paidAmount = val;
        }
        _totalDueNotifier.value = widget.order.cost - widget.order.paidAmount;
      },
    );
  }

  Widget _buildPaidStamp() {
    return Positioned(
      right: 15,
      bottom: 20,
      child: Transform.rotate(
        angle: -0.2,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.green.withAlpha(180), width: 1.5),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Text(
            "PAID",
            style: TextStyle(
              color: Colors.green.withAlpha(180),
              fontWeight: FontWeight.bold,
              fontSize: 18,
              letterSpacing: 2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildItemsInput() {
    return TagInputWidget(
      initialValue: widget.order.items
          .map((e) => TagInputItem(value: e, label: e))
          .toList(),
      limit: 999,
      multiline: false,
      enabled: !inProgress && canEdit,
      onChanged: (newItems) {
        setState(() {
          widget.order.items = newItems.map((e) => e.label).toList();
        });
      },
      strict: false,
      suggestions: expenses.allItems
          .map((e) => TagInputItem(value: e, label: e))
          .toList(),
      inactiveColor: Colors.transparent,
    );
  }

  Widget _buildPhotosSection() {
    final theme = FluentTheme.of(context);
    return SizedBox(
      child: Column(
        crossAxisAlignment: widget.order.photos.isEmpty
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                txt("photos").toUpperCase(),
                style: _sectionTitleTextStyle(theme).copyWith(
                  fontSize: 14,
                ),
              ),
              if (canEdit && !inProgress) ...[
                _buildAddPhotoButton(),
              ]
            ],
          ),
          const SizedBox(height: 8),
          if (widget.order.photos.isEmpty)
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 5,
              children: [
                const SizedBox(height: 0),
                const Icon(FluentIcons.photo2_remove, size: 20),
                SmallLabel(
                  label: txt("noPhotos"),
                  textColor: Colors.white,
                  bgColor: Colors.warningPrimaryColor,
                  icon: FluentIcons.warning,
                ),
              ],
            )
          else
            GridGallery(
              rowId: widget.order.id,
              imgs: widget.order.photos,
              progress: inProgress,
              onPressDelete: (img) async {
                try {
                  await expenses.deleteImg(
                    widget.order.id,
                    img,
                  );
                  widget.order.photos.remove(img);
                } catch (e, s) {
                  showErrorMessage(e, "deletingOrderImageFromServer");
                  login.askForLoginAgain(e);
                  logger("Error during deleting image: $e", s);
                }
              },
              canDelete: canEdit,
              size: 60,
              showPlayIcon: false,
              clipCount: 99999,
            )
        ],
      ),
    );
  }

  Widget _buildAddPhotoButton() {
    return FlyoutTarget(
      controller: photoAddMenu,
      child: Button(
        child: ButtonContent(WindowsIcons.photo, txt("add")),
        onPressed: () async {
          if (inProgress) return;
          final bool suppGallery =
              ImagePicker().supportsImageSource(ImageSource.gallery);
          final bool suppCamera =
              ImagePicker().supportsImageSource(ImageSource.camera);

          if (suppGallery && !suppCamera) {
            uploadFromGallery();
            return;
          }
          if (!suppGallery && suppCamera) {
            uploadFromCamera();
            return;
          }

          await flyoutFocusFix(context);
          photoAddMenu.showFlyout(builder: (context) {
            return MenuFlyout(
              items: [
                if (suppGallery)
                  MenuFlyoutItem(
                    text: Txt(txt("upload")),
                    leading: const Icon(FluentIcons.upload),
                    onPressed: uploadFromGallery,
                  ),
                if (suppCamera)
                  MenuFlyoutItem(
                    text: Txt(txt("camera")),
                    leading: const Icon(FluentIcons.camera),
                    onPressed: uploadFromCamera,
                  ),
              ],
            );
          });
        },
      ),
    );
  }

  void uploadFromGallery() async {
    List<XFile> res = await ImagePicker().pickMultiImage(limit: 10);
    if (!mounted) return;
    setState(() => inProgress = true);
    try {
      for (var img in res) {
        final imgName = await handleNewImage(
          rowID: widget.order.id,
          sourcePath: img.path,
          sourceFile: img,
          targetStore: expenses,
        );
        if (!widget.order.photos.contains(imgName)) {
          widget.order.photos.add(imgName);
        }
      }
    } catch (e, s) {
      showErrorMessage(e, "uploadingOrderImageFromGallery");
      login.askForLoginAgain(e);
      logger("Error during file upload: $e", s);
    }
    if (mounted) setState(() => inProgress = false);
  }

  void uploadFromCamera() async {
    final XFile? res =
        await ImagePicker().pickImage(source: ImageSource.camera);
    if (res == null) return;
    if (!mounted) return;
    setState(() => inProgress = true);
    try {
      final imgName = await handleNewImage(
        rowID: widget.order.id,
        sourcePath: res.path,
        sourceFile: res,
        targetStore: expenses,
      );
      if (!widget.order.photos.contains(imgName)) {
        widget.order.photos.add(imgName);
      }
    } catch (e, s) {
      showErrorMessage(e, "uploadingOrderImageFromCamera");
      login.askForLoginAgain(e);
      logger("Error during camera upload: $e", s);
    }
    if (mounted) setState(() => inProgress = false);
  }

  void _readFromPhoto() async {
    if (widget.order.photos.isEmpty || !mounted) return;
    setState(() => inProgress = true);
    try {
      final imgName = widget.order.photos.first;
      final imgUrl =
          await expenses.remote?.getImageLink(widget.order.id, imgName);
      if (imgUrl == null) throw Exception("Could not retrieve image URL");
      final items = await ReceiptScanner.extractItemsFromUrl(imgUrl);
      if (items.isNotEmpty && mounted) {
        setState(() {
          widget.order.items = items;
        });
      }
    } catch (e, s) {
      showErrorMessage(e, "readingItemsFromPhoto");
      logger("Error reading items from photo: $e", s);
    }
    if (mounted) setState(() => inProgress = false);
  }

  Widget _buildMoreButton() {
    return FlyoutTarget(
      controller: deleteConfirmCtrl,
      child: FlyoutTarget(
        controller: moreOptionsCtrl,
        child: IconButton(
          icon: inProgress
              ? const SizedBox(
                  width: 15,
                  height: 15,
                  child: ProgressRing(
                    strokeWidth: 2,
                  ))
              : const Icon(WindowsIcons.more),
          onPressed: () async {
            if (inProgress) return;
            await flyoutFocusFix(context);
            moreOptionsCtrl.showFlyout(builder: (context) {
              return MenuFlyout(
                items: [
                  MenuFlyoutItem(
                    text: Txt(widget.order.processed
                        ? txt("markAsDue")
                        : txt("markAsPaid")),
                    leading: Icon(widget.order.processed
                        ? FluentIcons.warning
                        : FluentIcons.accept),
                    onPressed: () {
                      widget.order.processed = !widget.order.processed;
                      setState(() {});
                    },
                  ),
                  MenuFlyoutItem(
                    text: Txt(widget.order.archived == true
                        ? txt("restore")
                        : txt("delete")),
                    leading: Icon(widget.order.archived == true
                        ? FluentIcons.undo
                        : WindowsIcons.delete),
                    onPressed: () {
                      moreOptionsCtrl.close();
                      WidgetsBinding.instance.addPostFrameCallback((_) async {
                        await flyoutFocusFix(context);
                        final supplierName = expenses.suppliers
                            .firstWhere((s) => s.id == widget.order.supplierId,
                                orElse: () => Expense.fromJson(
                                    {"supplierName": "Unknown"}))
                            .supplierName;
                        deleteConfirmCtrl.showFlyout(
                            builder: (ctx) => ConfirmDeleteFlyout(
                                restorable: true,
                                controller: deleteConfirmCtrl,
                                actionIcon: widget.order.archived == true
                                    ? FluentIcons.undo
                                    : WindowsIcons.delete,
                                actionText: widget.order.archived == true
                                    ? txt("restore")
                                    : txt("delete"),
                                preview: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  spacing: 5,
                                  children: [
                                    const Icon(FluentIcons.receipt_processing),
                                    Txt(supplierName),
                                    Txt(DF.allNumbers(widget.order.date))
                                  ],
                                ),
                                onConfirm: () {
                                  widget.order.archived =
                                      widget.order.archived == true
                                          ? null
                                          : true;
                                  expenses.set(widget.order);
                                }));
                      });
                    },
                  ),
                ],
              );
            });
          },
        ),
      ),
    );
  }
}

class DashedLine extends StatelessWidget {
  final double thickness;
  final double dashWidth;
  final double dashGap;
  final Color? color;

  const DashedLine({
    super.key,
    this.thickness = 1,
    this.dashWidth = 5,
    this.dashGap = 3,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final color = FluentTheme.of(context).resources.surfaceStrokeColorDefault;
    return CustomPaint(
      size: Size(double.infinity, thickness),
      painter: _DashedLinePainter(
        color: color,
        thickness: thickness,
        dashWidth: dashWidth,
        dashGap: dashGap,
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  final Color color;
  final double thickness;
  final double dashWidth;
  final double dashGap;

  _DashedLinePainter({
    required this.color,
    required this.thickness,
    required this.dashWidth,
    required this.dashGap,
  });

  @override
  void paint(Canvas canvas, Size size) {
    double startX = 0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness;

    while (startX < size.width) {
      canvas.drawLine(Offset(startX, 0), Offset(startX + dashWidth, 0), paint);
      startX += dashWidth + dashGap;
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter oldDelegate) =>
      color != oldDelegate.color ||
      thickness != oldDelegate.thickness ||
      dashWidth != oldDelegate.dashWidth ||
      dashGap != oldDelegate.dashGap;
}

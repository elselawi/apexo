import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/date_time_picker.dart';
import 'package:apexo/common_widgets/dialogs/loading_blocking.dart';
import 'package:apexo/common_widgets/money_display.dart';
import 'package:apexo/common_widgets/slideshow/slideshow.dart';
import 'package:apexo/common_widgets/small_label.dart';
import 'package:apexo/common_widgets/tag_input.dart';
import 'package:apexo/features/expenses/expense_model.dart';
import 'package:apexo/features/expenses/expenses_store.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/utils/constants.dart';
import 'package:apexo/utils/flyout_focus_fix.dart';
import 'package:apexo/utils/imgs.dart';
import 'package:apexo/utils/logger.dart';
import 'package:apexo/utils/money_editing_controller.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

class OrderRow extends StatefulWidget {
  const OrderRow({
    super.key,
    required this.order,
    this.supplier,
    this.justCreated = false,
  });
  final Expense order;
  final Expense? supplier;
  final bool justCreated;

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
  final bool canEdit = login.permissions[PInt.expenses] == 2;

  bool inProgress = false;
  late AnimationController _pulseController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    costCtrl.text = widget.order.cost.toStringAsFixed(2);
    paidCtrl.text = widget.order.paidAmount.toStringAsFixed(2);
    notesController.text = widget.order.notes;
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
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final supplier = widget.supplier ??
        expenses.suppliers.firstWhere((s) => s.id == widget.order.supplierId,
            orElse: () => Expense.fromJson({"supplierName": "Unknown"}));

    final card = Container(
      height: 508,
      width: 310,
      decoration: BoxDecoration(
        color: theme.brightness.isLight ? Colors.white : theme.cardColor,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: theme.brightness.isLight
                ? Colors.black.withAlpha(20)
                : Colors.black.withAlpha(80),
            blurRadius: 12,
            offset: const Offset(0, 4),
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
                      label: txt("archived"),
                      textColor: Colors.white,
                      bgColor: Colors.grey,
                      icon: FluentIcons.archive,
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
    final df = localSettings.dateFormat.startsWith("d") == true
        ? "dd / MM / yyyy"
        : "MM / dd / yyyy";
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
                child: Text(
                  supplier.supplierName.toUpperCase(),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    letterSpacing: 1.2,
                    color: theme.typography.body?.color,
                  ),
                ),
              ),
              _buildMoreButton(),
            ],
          ),
          const SizedBox(height: 8),
          DateTimePicker(
            initValue: widget.order.date,
            onChange: (v) => expenses.set(widget.order..date = v),
            enabled: canEdit,
            showButton: true,
            buttonText: txt("change"),
            buttonIcon: WindowsIcons.calendar,
            pickTime: false,
            textStyle: theme.typography.bodyStrong?.copyWith(
              fontSize: 13,
            ),
            format: df,
          ),
        ],
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
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: Colors.grey.withAlpha(40)),
            ),
            enabled: canEdit && !inProgress,
            controller: notesController,
            maxLines: null,
            onChanged: (value) => expenses.set(widget.order..notes = value),
          ),
          const SizedBox(height: 12),
          _buildPhotosSection(),
        ],
      ),
    );
  }

  Widget _buildReceiptFooter() {
    final theme = FluentTheme.of(context);
    final currency = globalSettings.get("currency_______").value;
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
                  currency,
                  isEditable: true,
                  controller: costCtrl,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildReceiptRow(
                  "paid",
                  widget.order.paidAmount,
                  currency,
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
              MoneyDisplay(
                "${(widget.order.cost - widget.order.paidAmount).toStringAsFixed(2)} $currency",
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: theme.typography.body?.color,
                ),
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
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ],
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: 14,
        color: theme.typography.body?.color,
      ),
      onChanged: (v) {
        setState(() {
          final val = double.tryParse(v) ?? 0;
          if (label == "due") {
            expenses.set(widget.order..cost = val);
          } else {
            expenses.set(widget.order..paidAmount = val);
          }
        });
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
          expenses.set(
            widget.order..items = newItems.map((e) => e.label).toList(),
          );
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
      height: 120,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
              if (canEdit && !inProgress) _buildAddPhotoButton(),
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
            Wrap(
              spacing: 3,
              runSpacing: 3,
              children: List.generate(widget.order.photos.length, (index) {
                return Button(
                    child: Column(
                      spacing: 3,
                      children: [
                        const Icon(FluentIcons.photo2, size: 16),
                        Text(
                          "${txt("photo")} ${index + 1}",
                          style: _sectionTitleTextStyle(theme),
                        ),
                      ],
                    ),
                    onPressed: () async {
                      final closeDialog = showLoadingBlockingDialog(
                          context, txt("gettingImages"));
                      MultiImageProvider multiImageProvider;
                      try {
                        final List<ImageProvider<Object>> list = (await Future
                                .wait(widget.order.photos
                                    .map((img) =>
                                        getImage(widget.order.id, img, false))
                                    .toList()))
                            .map((el) =>
                                el ??
                                const AssetImage("assets/images/missing.png"))
                            .toList();
                        multiImageProvider =
                            MultiImageProvider(list, initialIndex: index);
                      } finally {
                        closeDialog();
                      }
                      showImageViewerPager(
                        // ignore: use_build_context_synchronously
                        context,
                        multiImageProvider,
                        backgroundColor: Colors.black.withValues(alpha: 0.9),
                        doubleTapZoomable: true,
                        immersive: false,
                        swipeDismissible: true,
                        infinitelyScrollable: true,
                        canDelete: canEdit,
                        drawings: null,
                        imageIds: widget.order.photos,
                        onSaveDrawing: null,
                        onPressDelete: (int index) async {
                          inProgress = true;
                          setState(() {});
                          try {
                            await expenses.deleteImg(
                              widget.order.id,
                              widget.order.photos[index],
                            );
                          } catch (e) {
                            if (context.mounted) {
                              showDialog(
                                  // ignore: use_build_context_synchronously
                                  context: context,
                                  builder: (context) => ContentDialog(
                                        title: const Text("Error"),
                                        content: Text(e.toString()),
                                        actions: [
                                          Button(
                                            child: const Text("Close"),
                                            onPressed: () =>
                                                Navigator.pop(context),
                                          ),
                                        ],
                                      ));
                            }
                          }
                          widget.order.photos.removeAt(index);
                          expenses.set(widget.order);
                          inProgress = false;
                          setState(() {});
                        },
                      );
                    });
              }),
            ),
        ],
      ),
    );
  }

  Widget _buildAddPhotoButton() {
    return FlyoutTarget(
      controller: photoAddMenu,
      child: Button(
        child: ButtonContent(FluentIcons.photo2_add, txt("addPhoto")),
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
        );
        if (!widget.order.photos.contains(imgName)) {
          expenses.set(widget.order..photos.add(imgName));
        }
      }
    } catch (e, s) {
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
      );
      if (!widget.order.photos.contains(imgName)) {
        expenses.set(widget.order..photos.add(imgName));
      }
    } catch (e, s) {
      login.askForLoginAgain(e);
      logger("Error during camera upload: $e", s);
    }
    if (mounted) setState(() => inProgress = false);
  }

  Widget _buildMoreButton() {
    return FlyoutTarget(
      controller: moreOptionsCtrl,
      child: IconButton(
        icon: inProgress
            ? const SizedBox(
                width: 15,
                height: 15,
                child: ProgressRing(
                  strokeWidth: 2,
                ))
            : const Icon(FluentIcons.more),
        onPressed: () {
          if (inProgress) return;
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
                    expenses
                        .set(widget.order..processed = !widget.order.processed);
                  },
                ),
                MenuFlyoutItem(
                  text: Txt(widget.order.archived == true
                      ? txt("restore")
                      : txt("archive")),
                  leading: Icon(widget.order.archived == true
                      ? FluentIcons.archive_undo
                      : FluentIcons.archive),
                  onPressed: () {
                    expenses.set(widget.order
                      ..archived = widget.order.archived == true ? null : true);
                  },
                ),
              ],
            );
          });
        },
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
    final color = this.color ?? Colors.grey.withAlpha(100);
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

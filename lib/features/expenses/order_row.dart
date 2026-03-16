import 'package:apexo/common_widgets/date_time_picker.dart';
import 'package:apexo/common_widgets/grid_gallery.dart';
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
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:image_picker/image_picker.dart';

class OrderRow extends StatefulWidget {
  const OrderRow({super.key, required this.order});
  final Expense order;

  @override
  State<OrderRow> createState() => OrderRowState();
}

class OrderRowState extends State<OrderRow> {
  final TextEditingController costCtrl = TextEditingController();
  final TextEditingController paidCtrl = TextEditingController();
  final FlyoutController moreOptionsCtrl = FlyoutController();
  final FlyoutController photoAddMenu = FlyoutController();
  final bool canEdit = login.permissions[PInt.expenses] == 2;

  bool inProgress = false;

  @override
  void initState() {
    costCtrl.text = widget.order.cost.toString();
    paidCtrl.text = widget.order.paidAmount.toString();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = widget.order.archived == true
        ? Colors.grey
        : inProgress
            ? Colors.blue
            : Colors.grey.withAlpha(20);
    return Container(
      decoration: BoxDecoration(
        border: BorderDirectional(
          start: BorderSide(color: borderColor, width: 5),
          bottom: BorderSide(color: borderColor, width: 1),
        ),
        gradient: widget.order.archived == true
            ? LinearGradient(
                colors: [Colors.grey.withAlpha(100), Colors.transparent],
                begin: AlignmentGeometry.bottomLeft,
                end: AlignmentGeometry.topRight)
            : null,
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        children: [
          Icon(
            color: FluentTheme.of(context).shadowColor,
            widget.order.archived == true
                ? FluentIcons.archive
                : widget.order.processed
                    ? FluentIcons.fabric_folder_confirm
                    : FluentIcons.file_request,
          ),
          const SizedBox(width: 5),
          _buildDatePickerCell(),
          _buildItemsCell(),
          _buildCostCell(context),
          const SizedBox(width: 5),
          _buildPayCell(context),
          _buildPhotosCell(context),
          if (canEdit)
            _buildMoreButton()
          else
            const SizedBox(
              width: 55,
            ),
        ],
      ),
    );
  }

  SizedBox _buildPhotosCell(BuildContext context) {
    return SizedBox(
      width: 90,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GridGallery(
            canDelete: canEdit,
            rowId: widget.order.id,
            imgs: widget.order.photos,
            countPerLine: 4,
            clipCount: 1,
            rowWidth: 50,
            size: 40,
            progress: false,
            showPlayIcon: false,
            showDeleteMiniButton: false,
            onPressDelete: (img) async {
              setState(() {
                inProgress = true;
              });
              try {
                await expenses.deleteImg(widget.order.id, img);
                expenses.set(widget.order..photos.remove(img));
              } catch (e, s) {
                logger("Error during deleting image: $e", s);
              }
              setState(() {
                inProgress = false;
              });
            },
          ),
          if (widget.order.archived != true && !inProgress && canEdit)
            _buildAddPhotoButton()
        ],
      ),
    );
  }

  Widget _buildAddPhotoButton() {
    return FlyoutTarget(
      controller: photoAddMenu,
      child: IconButton(
        icon: const Icon(FluentIcons.photo2_add, size: 20),
        onPressed: () async {
          await flyoutFocusFix();
          final bool suppGallery =
              ImagePicker().supportsImageSource(ImageSource.gallery);
          final bool suppCamera =
              ImagePicker().supportsImageSource(ImageSource.camera);

          // if it supports only one methood
          // there's no need to show a menu
          if (suppCamera && !suppGallery) {
            return uploadFromCamera();
          } else if (suppGallery && !suppCamera) {
            return uploadFromGallery();
          }

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
    setState(() {
      inProgress = true;
    });
    try {
      for (var img in res) {
        final imgName = await handleNewImage(
          rowID: widget.order.id,
          sourcePath: img.path,
          sourceFile: img,
        );
        if (widget.order.photos.contains(imgName) == false) {
          expenses.set(widget.order..photos.add(imgName));
        }
      }
    } catch (e, s) {
      logger("Error during file upload: $e", s);
    }
    setState(() {
      inProgress = false;
    });
  }

  void uploadFromCamera() async {
    final XFile? res =
        await ImagePicker().pickImage(source: ImageSource.camera);
    if (res == null) return;
    setState(() {
      inProgress = true;
    });
    try {
      final imgName = await handleNewImage(
        rowID: widget.order.id,
        sourcePath: res.path,
        sourceFile: res,
      );
      if (widget.order.photos.contains(imgName) == false) {
        expenses.set(widget.order..photos.add(imgName));
      }
    } catch (e, s) {
      logger("Error during uploading camera capture: $e", s);
    }
    setState(() {
      inProgress = false;
    });
  }

  SizedBox _buildPayCell(BuildContext context) {
    return SizedBox(
      width: 90,
      child: Column(
        children: [
          CupertinoTextField(
            readOnly: !canEdit,
            textAlign: TextAlign.end,
            style: FluentTheme.of(context).typography.body,
            padding:
                const EdgeInsetsGeometry.symmetric(horizontal: 6, vertical: 10),
            suffix: Text(
              "${globalSettings.get("currency_______").value} ",
              style: const TextStyle(fontSize: 11),
            ),
            controller: paidCtrl,
            enabled: inProgress == false,
            onChanged: (v) {
              setState(() {
                expenses.set(widget.order..paidAmount = double.parse(v));
              });
            },
          ),
        ],
      ),
    );
  }

  SizedBox _buildCostCell(BuildContext context) {
    return SizedBox(
      width: 90,
      child: Column(
        children: [
          CupertinoTextField(
            readOnly: !canEdit,
            textAlign: TextAlign.end,
            style: FluentTheme.of(context).typography.body,
            padding:
                const EdgeInsetsGeometry.symmetric(horizontal: 6, vertical: 10),
            suffix: Text(
              "${globalSettings.get("currency_______").value} ",
              style: const TextStyle(fontSize: 11),
            ),
            controller: costCtrl,
            enabled: inProgress == false,
            onChanged: (v) {
              setState(() {
                expenses.set(widget.order..cost = double.parse(v));
              });
            },
          ),
        ],
      ),
    );
  }

  Expanded _buildItemsCell() {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: TagInputWidget(
          initialValue: widget.order.items
              .map((e) => TagInputItem(value: e, label: e))
              .toList(),
          limit: 9999,
          enabled: !inProgress && canEdit,
          onChanged: (newItems) {
            setState(() {
              expenses.set(
                  widget.order..items = newItems.map((e) => e.label).toList());
            });
          },
          strict: false,
          suggestions: expenses.allItems
              .map((e) => TagInputItem(value: e, label: e))
              .toList(),
          inactiveColor: Colors.transparent,
        ),
      ),
    );
  }

  SizedBox _buildDatePickerCell() {
    return SizedBox(
      width: 90,
      child: Align(
        alignment: AlignmentGeometry.center,
        child: DateTimePicker(
          enabled: !inProgress && canEdit,
          initValue: widget.order.date,
          onChange: (newDate) {
            setState(() {
              expenses.set(widget.order..date = newDate);
            });
          },
          pickTime: false,
          showButton: false,
        ),
      ),
    );
  }

  SizedBox _buildMoreButton() {
    return SizedBox(
      width: 60,
      child: inProgress
          ? const Center(
              child: SizedBox(width: 20, height: 20, child: ProgressRing()))
          : FlyoutTarget(
              controller: moreOptionsCtrl,
              child: IconButton(
                  icon: const Icon(FluentIcons.more, size: 20),
                  onPressed: () {
                    moreOptionsCtrl.showFlyout(builder: (context) {
                      return MenuFlyout(
                        items: [
                          if (!widget.order.processed)
                            MenuFlyoutItem(
                              text: Txt(txt("markAsPaid")),
                              onPressed: () {
                                expenses.set(widget.order..processed = true);
                              },
                              leading: const Icon(FluentIcons.accept),
                            )
                          else
                            MenuFlyoutItem(
                              text: Txt(txt("markAsDue")),
                              onPressed: () {
                                expenses.set(widget.order..processed = false);
                              },
                              leading: const Icon(FluentIcons.warning),
                            ),
                          if (widget.order.archived == true)
                            MenuFlyoutItem(
                              text: Txt(txt("restore")),
                              onPressed: () {
                                expenses.set(widget.order..archived = null);
                              },
                              leading: const Icon(FluentIcons.archive_undo),
                            )
                          else
                            MenuFlyoutItem(
                              text: Txt(txt("archive")),
                              onPressed: () {
                                expenses.set(widget.order..archived = true);
                              },
                              leading: const Icon(FluentIcons.archive),
                            )
                        ],
                      );
                    });
                  }),
            ),
    );
  }
}

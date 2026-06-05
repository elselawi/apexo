import 'package:apexo/common_widgets/dialogs/dialog_styling.dart';
import 'package:apexo/common_widgets/error_dialog.dart';
import 'package:apexo/features/expenses/expense_model.dart';
import 'package:apexo/features/expenses/expenses_store.dart';
import 'package:apexo/features/expenses/order_row.dart';
import 'package:apexo/services/ai_services/receipt_scanner.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/utils/imgs.dart';
import 'package:apexo/utils/logger.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:image_picker/image_picker.dart';

/// Shows a dialog with the scanned receipt data pre-filled and editable.
/// Returns a [Future] that completes with the created [Expense] if saved,
/// or `null` if cancelled.
Future<Expense?> showScanReceiptDialog(
    BuildContext context, ImageSource source) async {
  // 1. Take/Capture photo
  final picked = await ImagePicker().pickImage(source: source);
  if (picked == null) return null;

  // 2. Scan the receipt
  final photo = picked;
  ReceiptData receipt;
  try {
    receipt = await ReceiptScanner.readReceiptFromXFile(photo);
  } catch (e) {
    if (context.mounted) {
      showDialog(
        context: context,
        builder: (ctx) => ContentDialog(
          style: dialogStyling(context, true, true),
          title: Txt(txt("receiptScanFailed")),
          content: Txt("$e"),
          actions: [
            Button(
              onPressed: () => Navigator.pop(ctx),
              child: Txt(txt("close")),
            ),
          ],
        ),
      );
    }
    return null;
  }

  if (!context.mounted) return null;

  // 3. Show editable dialog
  return showDialog<Expense>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _ScanReceiptDialogContent(
      receipt: receipt,
      photo: photo,
    ),
  );
}

class _ScanReceiptDialogContent extends StatefulWidget {
  final ReceiptData receipt;
  final XFile photo;

  const _ScanReceiptDialogContent({
    required this.receipt,
    required this.photo,
  });

  @override
  State<_ScanReceiptDialogContent> createState() =>
      _ScanReceiptDialogContentState();
}

class _ScanReceiptDialogContentState extends State<_ScanReceiptDialogContent> {
  bool _saving = false;
  bool _supplierNameError = false;
  Expense transientOrder = Expense.fromJson({});
  Expense? transientSupplier;

  @override
  void initState() {
    super.initState();

    transientOrder.date =
        DateTime.tryParse(widget.receipt.orderDate) ?? DateTime.now();

    final detectedName = widget.receipt.supplierName.trim().isEmpty
        ? "unknown"
        : widget.receipt.supplierName.trim();

    final matchedSuppliers =
        expenses.suppliers.where((x) => x.supplierName == detectedName);
    final matchedSupplier = matchedSuppliers.firstOrNull;
    if (matchedSupplier == null) {
      transientSupplier = Expense.fromJson({
        "isSupplier": true,
        "supplierName": detectedName,
      });
      transientOrder.supplierId = transientSupplier!.id;
    } else {
      transientOrder.supplierId = matchedSupplier.id;
    }

    transientOrder.items = widget.receipt.orderItems
        .map((e) => "${e.name} ${e.quantity == 1 ? '' : "(${e.quantity})"}")
        .toList();
    transientOrder.cost = widget.receipt.totalPrice;
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      style: dialogStyling(context, false, true),
      title: Txt(txt("scanReceipt")),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: OrderRow(
            order: transientOrder,
            additionalSupplier: transientSupplier,
            editableSupplier: true,
            strictSupplierInput: false,
            justCreated: false,
            showContextMenu: false,
            showPhotosSection: false,
            supplierNameError: _supplierNameError,
          ),
        ),
      ),
      actions: [
        Button(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Txt(txt("cancel")),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 14, height: 14, child: ProgressRing(strokeWidth: 2))
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(WindowsIcons.save),
                    const SizedBox(width: 8),
                    Txt(txt("save")),
                  ],
                ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (transientOrder.supplierId.isEmpty) {
      setState(() => _supplierNameError = true);
      return;
    }
    setState(() => _saving = true);

    try {
      // 1. If supplier is new, save it first
      if (transientSupplier != null &&
          transientOrder.supplierId == transientSupplier!.id) {
        expenses.set(transientSupplier!);
      }

      // 2. save the order
      expenses.set(transientOrder);

      // wait for the order to be saved and have an ID before uploading the image
      await Future.delayed(const Duration(milliseconds: 500));

      // 3. upload the receipt photo to the order
      final imgName = await handleNewImage(
        rowID: transientOrder.id,
        sourcePath: widget.photo.path,
        sourceFile: widget.photo,
        targetStore: expenses,
      );

      // 4. add to photos list
      if (!transientOrder.photos.contains(imgName)) {
        transientOrder.photos.add(imgName);
      }

      // 5. save the order again with the photo
      expenses.set(transientOrder);
    } catch (e, s) {
      if (mounted) Navigator.pop(context);
      showErrorMessage(e, "uploadingOrderImageFromCamera");
      logger("Error during camera upload: $e", s);
      return;
    }
    if (mounted) Navigator.pop(context, transientOrder);
  }
}

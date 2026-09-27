import 'package:apexo/utils/print/print.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:pdf/widgets.dart' as pw;

Future<void> printingQRCode(
    BuildContext context, String link, String title, String description) async {
  // Generate QR code image for PDF
  final qrImage = await QrPainter(
    data: link,
    version: QrVersions.auto,
    errorCorrectionLevel: QrErrorCorrectLevel.H,
  ).toImageData(190);

  if (context.mounted) {
    return printing(
        context,
        title,
        pw.Image(
          pw.MemoryImage(qrImage!.buffer.asUint8List()),
          width: 200,
          height: 200,
          fit: pw.BoxFit.cover,
        ),
        description);
  }
}

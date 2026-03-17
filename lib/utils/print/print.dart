import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

Future<void> printing(BuildContext context, String header, pw.Widget content,
    String footer) async {
  var myTheme = pw.ThemeData.withFont(
    base: pw.Font.ttf(await rootBundle.load("assets/fonts/readex.ttf")),
    bold: pw.Font.ttf(await rootBundle.load("assets/fonts/readex-bold.ttf")),
  );

  final pdf = pw.Document(theme: myTheme);

  // Create PDF page
  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a5,
      build: (pw.Context context) {
        return pw.Center(
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              // Title
              pw.Text(
                header,
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 5),
              pw.Divider(),
              pw.SizedBox(height: 10),
              pw.Expanded(child: content),
              pw.SizedBox(height: 10),
              pw.Divider(),
              pw.SizedBox(height: 5),
              // Description
              pw.Text(
                footer,
                style: const pw.TextStyle(fontSize: 12),
                textAlign: pw.TextAlign.center,
              ),
            ],
          ),
        );
      },
    ),
  );

  // Show print preview
  await Printing.layoutPdf(
    onLayout: (PdfPageFormat format) async => pdf.save(),
    name: 'QR Code - $header',
    format: PdfPageFormat.a4,
  );
}

import 'package:apexo/app/app.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';

Future<String?> saveFileUtility({
  required String fileName,
  required Uint8List bytes,
}) async {
  String? outputFilePath;
  try {
    outputFilePath = await FilePicker.saveFile(
      dialogTitle: 'Save Photo',
      fileName: fileName,
      bytes: bytes,
      lockParentWindow: true,
    );
    if (bContext.mounted && outputFilePath != null) {
      displayInfoBar(
        bContext,
        builder: (context, close) => InfoBar(
          title: const Text('Saved!'),
          content: Text('file saved to $outputFilePath'),
          severity: InfoBarSeverity.success,
          onClose: close,
        ),
      );
    }
  } catch (e) {
    if (bContext.mounted) {
      displayInfoBar(
        bContext,
        builder: (context, close) => InfoBar(
          title: const Text('file saving photo'),
          content: Text(e.toString()),
          severity: InfoBarSeverity.error,
          onClose: close,
        ),
      );
    }
  }

  return outputFilePath;
}

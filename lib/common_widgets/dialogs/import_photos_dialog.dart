import 'dart:convert';

import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/dialogs/close_dialog_button.dart';
import 'package:apexo/common_widgets/dialogs/dialog_styling.dart';
import 'package:apexo/common_widgets/keyboard_aware.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart';

class ImportDialog extends StatefulWidget {
  const ImportDialog({super.key});

  @override
  State<ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<ImportDialog> {
  final _linkCtrl = TextEditingController();
  String _error = "";

  @override
  void dispose() {
    _linkCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardAwareView(
      child: ContentDialog(
        title: const SizedBox(),
        style: dialogStyling(context, false, true),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InfoBar(
              title: Txt(txt("importingPhotosFromLink")),
              content: Txt(txt("useThisForm")),
            ),
            const SizedBox(height: 10),
            if (_error.isNotEmpty)
              InfoBar(
                title: Txt(txt("error")),
                content: Txt(_error),
                severity: InfoBarSeverity.error,
              ),
            const SizedBox(height: 10),
            InfoLabel(
              label: txt("link"),
              child: CupertinoTextField(
                controller: _linkCtrl,
                placeholder: txt("enterLink"),
              ),
            ),
          ],
        ),
        actions: [
          const CloseButtonInDialog(),
          FilledButton(
            style: filledButtonStyle(Colors.blue),
            onPressed: _import,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(WindowsIcons.save),
                const SizedBox(width: 5),
                Txt(txt("import")),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _import() async {
    setState(() => _error = "");
    try {
      final url = Uri.parse(
          'https://imgs.apexo.app/?url=${Uri.encodeComponent(_linkCtrl.text)}');
      final response = await get(url);
      if (response.statusCode != 200) {
        throw Exception(response.body);
      }
      if (!mounted) return;
      final res = List<String>.from(jsonDecode(response.body));
      if (mounted) Navigator.pop(context, res);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }
}

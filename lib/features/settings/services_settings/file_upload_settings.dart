import 'package:apexo/common_widgets/dialogs/dialog_styling.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/cupertino.dart';
import 'responsive_row.dart';
import '../applies_to_indicator.dart';

class FileUploadSettings extends StatefulWidget {
  const FileUploadSettings({super.key});

  @override
  State<FileUploadSettings> createState() => _FileUploadSettingsState();
}

class _FileUploadSettingsState extends State<FileUploadSettings> {
  final TextEditingController _maxSizeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final collection = await login.pb!.collections.getOne("data");
      final imgsField = collection.fields.firstWhere((f) => f.name == "imgs");
      final maxSizeBytes = imgsField.data["maxSize"] as int? ?? 0;
      _maxSizeController.text = maxSizeBytes > 0
          ? (maxSizeBytes / (1024 * 1024)).toStringAsFixed(0)
          : "";
    } catch (e) {
      // Controller remains empty on error
    }
    if (mounted) setState(() {});
  }

  Future<void> _saveSettings() async {
    try {
      final mb = (int.tryParse(_maxSizeController.text) ?? 15).clamp(1, 1024);
      final maxSizeBytes = mb * 1024 * 1024;

      final collection = await login.pb!.collections.getOne("data");
      final imgsField = collection.fields.firstWhere((f) => f.name == "imgs");
      imgsField.data["maxSize"] = maxSizeBytes;

      await login.pb!.collections.update("data", body: {
        "fields": collection.fields.map((f) => f.toJson()).toList(),
      });

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: true,
          dismissWithEsc: true,
          builder: (context) => ContentDialog(
            style: dialogStyling(context, false, true),
            title: Txt(txt("success")),
            content: Txt(txt("file_upload_save_success")),
            actions: [
              Button(
                onPressed: () => Navigator.pop(context),
                child: Txt(txt("close")),
              )
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: true,
          dismissWithEsc: true,
          builder: (context) => ContentDialog(
            style: dialogStyling(context, true, true),
            title: Txt(txt("fail")),
            content: Txt("${txt("file_upload_save_fail")}: $e"),
            actions: [
              Button(
                onPressed: () => Navigator.pop(context),
                child: Txt(txt("close")),
              )
            ],
          ),
        );
      }
    }
  }

  Widget _buildSuffix() {
    final mb = int.tryParse(_maxSizeController.text) ?? 0;
    return Padding(
      padding: const EdgeInsets.all(5),
      child: Text(
        mb == 1 ? "MB" : "MB",
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.grey,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _maxSizeController.dispose();
    super.dispose();
  }

  Widget _hint(String key) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        txt(key),
        style: TextStyle(fontSize: 11, color: Colors.grey.withAlpha(180)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: Expander(
        leading: const Icon(FluentIcons.upload),
        header: Txt(txt("file_upload_settings")),
        trailing: const AppliesToIndicator(scope: Scope.system),
        contentPadding: const EdgeInsets.all(10),
        content: SizedBox(
          width: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InfoBar(
                title: Txt(txt("file_upload_info_title")),
                severity: InfoBarSeverity.info,
                content: Txt(txt("file_upload_info_desc")),
              ),
              const SizedBox(height: 15),
              ResponsiveRow(children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Txt(txt("file_upload_max_size")),
                    const SizedBox(height: 5),
                    CupertinoTextField(
                      controller: _maxSizeController,
                      placeholder: "15",
                      keyboardType: TextInputType.number,
                      suffix: _buildSuffix(),
                    ),
                    _hint("file_upload_max_size_hint"),
                  ],
                ),
              ]),
              const SizedBox(height: 20),
              Row(
                children: [
                  FilledButton(
                    onPressed: _saveSettings,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(WindowsIcons.save),
                        const SizedBox(width: 8),
                        Txt(txt("save")),
                      ],
                    ),
                  ),
                ],
              ),
            ]
                .map((e) => [e, const SizedBox(height: 5)])
                .expand((e) => e)
                .toList(),
          ),
        ),
      ),
    );
  }
}

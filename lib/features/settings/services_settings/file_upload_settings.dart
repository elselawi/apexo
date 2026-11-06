import 'dart:async';
import 'package:apexo/common_widgets/dialogs/dialog_styling.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/widget_keys.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/utils/logger.dart';
import 'package:fluent_ui/fluent_ui.dart';
import '../applies_to_indicator.dart';
import '../settings_card.dart';

class FileUploadSettings extends StatefulWidget {
  const FileUploadSettings({super.key});

  @override
  State<FileUploadSettings> createState() => _FileUploadSettingsState();
}

class _FileUploadSettingsState extends State<FileUploadSettings> {
  final TextEditingController _maxSizeController = TextEditingController();
  bool _settingsLoaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSettings());
  }

  Future<void> _loadSettings() async {
    try {
      final collection = await login.pb!.collections.getOne("data");
      if (!mounted) return;
      final imgsField = collection.fields.firstWhere((f) => f.name == "imgs");
      final maxSizeBytes = imgsField.data["maxSize"] as int? ?? 0;
      _maxSizeController.text = maxSizeBytes > 0
          ? (maxSizeBytes / (1024 * 1024)).toStringAsFixed(0)
          : "";
      _settingsLoaded = true;
    } catch (e, s) {
      logger('Could not load file upload settings: $e', s);
    }
    if (mounted) setState(() {});
  }

  Future<void> _saveSettings() async {
    if (!_settingsLoaded) return;
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
        unawaited(showDialog(
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
        ));
      }
    } catch (e) {
      if (mounted) {
        unawaited(showDialog(
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
        ));
      }
    }
  }

  Widget _buildSuffix() {
    final mb = int.tryParse(_maxSizeController.text) ?? 0;
    return Padding(
      padding: const EdgeInsets.all(5),
      child: Txt(
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

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      key: WK.serviceSection('file_upload_settings'),
      leading: const Icon(FluentIcons.upload),
      header: Txt(txt("file_upload_info_title")),
      description: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Txt(txt("file_upload_info_desc")),
          const SizedBox(height: 4),
          Txt(txt("file_upload_max_size_hint")),
        ],
      ),
      trailing: const AppliesToIndicator(scope: Scope.system),
      control: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            label: txt("file_upload_max_size"),
            child: TextBox(
              key: WK.serviceField('file_upload_maxSize'),
              controller: _maxSizeController,
              placeholder: "15",
              keyboardType: TextInputType.number,
              suffix: _buildSuffix(),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton(
              onPressed: _settingsLoaded ? _saveSettings : null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(WindowsIcons.save, size: 16),
                  const SizedBox(width: 8),
                  Flexible(child: Txt(txt("save"))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

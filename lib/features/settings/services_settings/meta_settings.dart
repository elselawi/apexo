import 'dart:async';
import 'package:apexo/common_widgets/dialogs/dialog_styling.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/widget_keys.dart';
import 'package:apexo/services/login.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'responsive_row.dart';
import '../applies_to_indicator.dart';
import '../settings_card.dart';

class MetaSettings extends StatefulWidget {
  const MetaSettings({super.key});

  @override
  State<MetaSettings> createState() => _MetaSettingsState();
}

class _MetaSettingsState extends State<MetaSettings> {
  final TextEditingController _appNameController = TextEditingController();
  final TextEditingController _appUrlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(_loadSettings());
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await login.pb!.settings.getAll();
      if (!mounted) return;
      final meta = settings['meta'] as Map<String, dynamic>? ?? {};
      _appNameController.text = meta['appName'] as String? ?? '';
      _appUrlController.text = meta['appURL'] as String? ?? '';
    } catch (e) {
      return;
    }
    if (!mounted) return;
    bool emptyFields = false;
    if (_appNameController.text.isEmpty) {
      _appNameController.text = "Apexo";
      emptyFields = true;
    }
    if (_appUrlController.text.isEmpty) {
      _appUrlController.text = "https://apexo.app";
      emptyFields = true;
    }
    if (emptyFields) await _saveSettings(false);
    if (mounted) setState(() {});
  }

  Future<void> _saveSettings(bool dialog) async {
    try {
      await login.pb!.settings.update(body: {
        "meta": {
          "appName": _appNameController.text,
          "appURL": _appUrlController.text,
        }
      });
      if (mounted && dialog) {
        unawaited(showDialog(
          context: context,
          barrierDismissible: true,
          dismissWithEsc: true,
          builder: (context) => ContentDialog(
            style: dialogStyling(context, false, true),
            title: Txt(txt("success")),
            content: Txt(txt("meta_save_success")),
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
      if (mounted && dialog) {
        unawaited(showDialog(
          context: context,
          barrierDismissible: true,
          dismissWithEsc: true,
          builder: (context) => ContentDialog(
            style: dialogStyling(context, true, true),
            title: Txt(txt("fail")),
            content: Txt("${txt("meta_save_fail")}: $e"),
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

  @override
  void dispose() {
    _appNameController.dispose();
    _appUrlController.dispose();
    super.dispose();
  }

  Widget _hint(String key) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Txt(
        txt(key),
        style: TextStyle(
            fontSize: 12,
            color: FluentTheme.of(context).resources.textFillColorSecondary),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.zero,
      child: SettingsCard(
        key: WK.serviceSection('meta_settings'),
        leading: const Icon(FluentIcons.settings),
        header: Txt(txt("meta_settings")),
        trailing: const AppliesToIndicator(scope: Scope.system),
        contentPadding: const EdgeInsets.only(top: 20),
        content: SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InfoBar(
                title: Txt(txt("meta_info_title")),
                severity: InfoBarSeverity.info,
                content: Txt(txt("meta_info_desc")),
              ),
              const SizedBox(height: 15),
              ResponsiveRow(children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Txt(txt("meta_appName")),
                    const SizedBox(height: 5),
                    TextBox(
                      controller: _appNameController,
                      placeholder: "My Clinic",
                    ),
                    _hint("meta_appName_hint"),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Txt(txt("meta_appUrl")),
                    const SizedBox(height: 5),
                    TextBox(
                      controller: _appUrlController,
                      placeholder: "https://mine.apexo.app",
                    ),
                    _hint("meta_appUrl_hint"),
                  ],
                ),
              ]),
              const SizedBox(height: 20),
              Row(
                children: [
                  FilledButton(
                    onPressed: () => _saveSettings(true),
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

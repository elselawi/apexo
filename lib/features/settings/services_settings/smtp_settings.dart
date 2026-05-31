import 'package:apexo/common_widgets/dialogs/dialog_styling.dart';
import 'package:apexo/core/observable.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:url_launcher/url_launcher.dart';
import 'responsive_row.dart';
import '../applies_to_indicator.dart';

final _smtpTestResult = ObservableState("");

class SmtpSettings extends StatefulWidget {
  const SmtpSettings({super.key});

  @override
  State<SmtpSettings> createState() => _SmtpSettingsState();
}

class _SmtpSettingsState extends State<SmtpSettings> {
  final TextEditingController hostController = TextEditingController();
  final TextEditingController portController = TextEditingController();
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController senderNameController = TextEditingController();
  final TextEditingController senderEmailController = TextEditingController();
  final TextEditingController localNameController = TextEditingController();
  final ValueNotifier<bool> tlsEnabled = ValueNotifier(false);
  final ValueNotifier<bool> smtpEnabled = ValueNotifier(false);
  final ValueNotifier<bool> showPassword = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _loadSmtpSettings();
  }

  Future<void> _loadSmtpSettings() async {
    try {
      final settings = await login.pb!.settings.getAll();

      final smtp = settings['smtp'] ?? {};
      final meta = settings['meta'] ?? {};

      hostController.text = smtp['host'] ?? '';
      portController.text = (smtp['port'] ?? '').toString();
      usernameController.text = smtp['username'] ?? '';
      passwordController.text = smtp['password'] ?? '';
      senderNameController.text = meta['senderName'] ?? '';
      senderEmailController.text = meta['senderAddress'] ?? '';
      localNameController.text = smtp['localName'] ?? '';
      tlsEnabled.value = smtp['tls'] ?? false;
      smtpEnabled.value = smtp['enabled'] ?? false;
    } catch (e) {
      // Controllers remain empty on error
    }
    if (mounted) setState(() {});
  }

  Future<void> _saveSmtpSettings() async {
    try {
      await login.pb!.settings.update(body: {
        "smtp": {
          "enabled": smtpEnabled.value,
          "host": hostController.text,
          "port": int.tryParse(portController.text) ?? 587,
          "username": usernameController.text,
          if (passwordController.text.isNotEmpty)
            "password": passwordController.text,
          "tls": tlsEnabled.value,
          "localName": localNameController.text,
        },
        "meta": {
          "senderName": senderNameController.text,
          "senderAddress": senderEmailController.text,
        }
      });

      if (mounted) {
        showDialog(
          barrierDismissible: true,
          dismissWithEsc: true,
          context: context,
          builder: (context) => ContentDialog(
            style: dialogStyling(context, false, true),
            title: Txt(txt("success")),
            content: Txt(txt("smtp_save_success")),
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
            content: Txt("${txt("smtp_save_fail")}: $e"),
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

  @override
  void dispose() {
    hostController.dispose();
    portController.dispose();
    usernameController.dispose();
    passwordController.dispose();
    senderNameController.dispose();
    senderEmailController.dispose();
    localNameController.dispose();
    tlsEnabled.dispose();
    smtpEnabled.dispose();
    showPassword.dispose();
    super.dispose();
  }

  void _applyGmailPreset() {
    hostController.text = "smtp.gmail.com";
    portController.text = "587";
    tlsEnabled.value = false;
    setState(() {});
  }

  void _applyOutlookPreset() {
    hostController.text = "smtp-mail.outlook.com";
    portController.text = "587";
    tlsEnabled.value = false;
    setState(() {});
  }

  Widget _presetChip(String label, VoidCallback onTap) {
    return Button(
      onPressed: onTap,
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
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

  Widget _appPasswordLink(String provider, String url) {
    return GestureDetector(
      onTap: () => launchUrl(Uri.parse(url)),
      child: Text(
        "${txt("smtp_app_passwords")} ($provider)",
        style: TextStyle(
          fontSize: 11,
          color: FluentTheme.of(context).accentColor,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: Expander(
        leading: const Icon(FluentIcons.mail),
        header: Txt(txt("smtp_settings")),
        trailing: const AppliesToIndicator(scope: Scope.system),
        contentPadding: const EdgeInsets.all(10),
        content: SizedBox(
          width: 400,
          child: MStreamBuilder(
              streams: [_smtpTestResult.stream],
              builder: (context, _) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InfoBar(
                      title: Txt(txt("smtp_info_title")),
                      severity: InfoBarSeverity.info,
                      content: Txt(txt("smtp_info_desc")),
                    ),
                    const SizedBox(height: 15),
                    ValueListenableBuilder<bool>(
                      valueListenable: smtpEnabled,
                      builder: (context, value, _) {
                        return Row(
                          children: [
                            ToggleSwitch(
                              checked: value,
                              onChanged: (v) => smtpEnabled.value = v,
                            ),
                            const SizedBox(width: 10),
                            Txt(txt("smtp_enabled")),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 15),
                    Row(
                      children: [
                        Txt("${txt("smtp_presets")}:"),
                        const SizedBox(width: 8),
                        _presetChip("Gmail", _applyGmailPreset),
                        const SizedBox(width: 5),
                        _presetChip("Outlook", _applyOutlookPreset),
                      ],
                    ),
                    const SizedBox(height: 10),
                    InfoBar(
                      title: Txt(txt("smtp_port_blocked_warning")),
                      severity: InfoBarSeverity.warning,
                    ),
                    const SizedBox(height: 10),
                    ResponsiveRow(
                      breakpoint: 525,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Txt(txt("smtp_host")),
                            const SizedBox(height: 5),
                            CupertinoTextField(
                              controller: hostController,
                              placeholder: "smtp.example.com",
                            ),
                            _hint("smtp_host_hint"),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Txt(txt("smtp_port")),
                            const SizedBox(height: 5),
                            CupertinoTextField(
                              controller: portController,
                              placeholder: "587",
                              keyboardType: TextInputType.number,
                            ),
                            _hint("smtp_port_hint"),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Txt(txt("smtp_tls")),
                            const SizedBox(height: 5),
                            ValueListenableBuilder<bool>(
                              valueListenable: tlsEnabled,
                              builder: (context, value, _) {
                                return ComboBox<String>(
                                  value: value ? "always" : "auto",
                                  items: [
                                    ComboBoxItem(
                                      value: "auto",
                                      child: Txt(txt("smtp_tls_auto")),
                                    ),
                                    ComboBoxItem(
                                      value: "always",
                                      child: Txt(txt("smtp_tls_always")),
                                    ),
                                  ],
                                  onChanged: (v) =>
                                      tlsEnabled.value = v == "always",
                                );
                              },
                            ),
                            _hint("smtp_tls_hint")
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),
                    ResponsiveRow(children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Txt(txt("smtp_username")),
                          const SizedBox(height: 5),
                          CupertinoTextField(
                            controller: usernameController,
                            placeholder: "user@example.com",
                          ),
                          _hint("smtp_username_hint"),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Txt(txt("smtp_password")),
                          const SizedBox(height: 5),
                          ValueListenableBuilder<bool>(
                            valueListenable: showPassword,
                            builder: (context, show, _) {
                              return CupertinoTextField(
                                controller: passwordController,
                                placeholder: txt("leaveBlankToKeepUnchanged"),
                                obscureText: !show,
                                suffix: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 4),
                                  child: IconButton(
                                    onPressed: () => showPassword.value = !show,
                                    icon: Icon(
                                      show
                                          ? FluentIcons.red_eye
                                          : FluentIcons.hide,
                                      size: 18,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          _hint("smtp_password_hint"),
                          Row(
                            children: [
                              _appPasswordLink(
                                "Gmail",
                                "https://myaccount.google.com/apppasswords",
                              ),
                              const SizedBox(width: 8),
                              _appPasswordLink(
                                "Outlook",
                                "https://account.live.com/proofs/Manage/additional",
                              ),
                            ],
                          ),
                        ],
                      ),
                    ]),
                    const SizedBox(height: 15),
                    ResponsiveRow(children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Txt(txt("smtp_senderName")),
                          const SizedBox(height: 5),
                          CupertinoTextField(
                            controller: senderNameController,
                            placeholder: "My Clinic",
                          ),
                          _hint("smtp_senderName_hint"),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Txt(txt("smtp_senderEmail")),
                          const SizedBox(height: 5),
                          CupertinoTextField(
                            controller: senderEmailController,
                            placeholder: "noreply@example.com",
                          ),
                          _hint("smtp_senderEmail_hint"),
                        ],
                      ),
                    ]),
                    const SizedBox(height: 15),
                    Txt(txt("smtp_localName")),
                    const SizedBox(height: 5),
                    CupertinoTextField(
                      controller: localNameController,
                      placeholder: "mine.apexo.app",
                    ),
                    _hint("smtp_localName_hint"),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        FilledButton(
                          onPressed: _saveSmtpSettings,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(WindowsIcons.save),
                              const SizedBox(width: 8),
                              Txt(txt("save")),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(FluentIcons.test_case),
                              const SizedBox(width: 8),
                              Txt(txt("test")),
                            ],
                          ),
                          onPressed: () async {
                            _smtpTestResult(".");
                            try {
                              await login.pb!.settings
                                  .testEmail(login.email, "password-reset");
                              _smtpTestResult(txt("smtp_test_success"));
                            } catch (e) {
                              _smtpTestResult(
                                  "ERROR: ${txt("smtp_test_fail")}: ${e.toString()}");
                            }
                          },
                        ),
                        const SizedBox(width: 10),
                        if (_smtpTestResult().length == 1) const ProgressBar()
                      ],
                    ),
                    if (_smtpTestResult().length > 1)
                      Padding(
                        padding: const EdgeInsets.only(top: 15),
                        child: InfoBar(
                          title: _smtpTestResult().startsWith("ERROR")
                              ? Txt(txt("fail"))
                              : Txt(txt("success")),
                          content: Txt(_smtpTestResult()),
                          severity: _smtpTestResult().startsWith("ERROR")
                              ? InfoBarSeverity.error
                              : InfoBarSeverity.success,
                        ),
                      ),
                  ]
                      .map((e) => [e, const SizedBox(height: 5)])
                      .expand((e) => e)
                      .toList(),
                );
              }),
        ),
      ),
    );
  }
}

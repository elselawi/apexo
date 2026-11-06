import 'dart:async';
import 'package:apexo/common_widgets/dialogs/dialog_styling.dart';
import 'package:apexo/core/reactive/observable.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/utils/logger.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'responsive_row.dart';
import '../applies_to_indicator.dart';
import '../settings_card.dart';

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
  bool _settingsLoaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSmtpSettings());
  }

  Future<void> _loadSmtpSettings() async {
    try {
      final settings = await login.pb!.settings.getAll();
      if (!mounted) return;

      final smtp = settings['smtp'] as Map<String, dynamic>? ?? {};
      final meta = settings['meta'] as Map<String, dynamic>? ?? {};

      hostController.text = smtp['host'] as String? ?? '';
      portController.text = (smtp['port'] ?? '').toString();
      usernameController.text = smtp['username'] as String? ?? '';
      passwordController.text = smtp['password'] as String? ?? '';
      senderNameController.text = meta['senderName'] as String? ?? '';
      senderEmailController.text = meta['senderAddress'] as String? ?? '';
      localNameController.text = smtp['localName'] as String? ?? '';
      tlsEnabled.value = smtp['tls'] as bool? ?? false;
      smtpEnabled.value = smtp['enabled'] as bool? ?? false;
      _settingsLoaded = true;
    } catch (e, s) {
      logger('Could not load SMTP settings: $e', s);
    }
    if (mounted) setState(() {});
  }

  Future<void> _saveSmtpSettings() async {
    if (!_settingsLoaded) return;
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
        unawaited(showDialog(
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
            content: Txt("${txt("smtp_save_fail")}: $e"),
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
      child: Txt(label, style: const TextStyle(fontSize: 12)),
    );
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

  Widget _appPasswordLink(String provider, String url) {
    return GestureDetector(
      onTap: () {
        unawaited(launchUrl(Uri.parse(url)));
      },
      child: Txt(
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
      padding: EdgeInsets.zero,
      child: SettingsCard(
        key: WK.serviceSection('smtp_settings'),
        leading: const Icon(FluentIcons.mail),
        header: Txt(txt("smtp_settings")),
        trailing: const AppliesToIndicator(scope: Scope.system),
        contentPadding: const EdgeInsets.only(top: 20),
        content: SizedBox(
          width: double.infinity,
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
                            Expanded(child: Txt(txt("smtp_enabled"))),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 15),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Txt("${txt("smtp_presets")}:"),
                        _presetChip("Gmail", _applyGmailPreset),
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
                            TextBox(
                              key: WK.serviceField('smtp_host'),
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
                            TextBox(
                              key: WK.serviceField('smtp_port'),
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
                                  isExpanded: true,
                                  items: [
                                    ComboBoxItem(
                                      value: "auto",
                                      child: Txt(txt("smtp_tls_auto"),
                                          overflow: TextOverflow.ellipsis),
                                    ),
                                    ComboBoxItem(
                                      value: "always",
                                      child: Txt(txt("smtp_tls_always"),
                                          overflow: TextOverflow.ellipsis),
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
                          TextBox(
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
                              return TextBox(
                                key: WK.serviceField('smtp_password'),
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
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              _appPasswordLink(
                                "Gmail",
                                "https://myaccount.google.com/apppasswords",
                              ),
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
                          TextBox(
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
                          TextBox(
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
                    TextBox(
                      controller: localNameController,
                      placeholder: "mine.apexo.app",
                    ),
                    _hint("smtp_localName_hint"),
                    const SizedBox(height: 20),
                    Wrap(
                      runSpacing: 8,
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton(
                          onPressed: _settingsLoaded ? _saveSmtpSettings : null,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(WindowsIcons.save),
                              const SizedBox(width: 8),
                              Txt(txt("save")),
                            ],
                          ),
                        ),
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
                        if (_smtpTestResult().length == 1)
                          const SizedBox(
                              width: 20,
                              height: 20,
                              child: ProgressRing(strokeWidth: 2))
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

import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/dialogs/close_dialog_button.dart';
import 'package:apexo/common_widgets/dialogs/dialog_styling.dart';
import 'package:apexo/common_widgets/dialogs/export_patients_dialog.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/core/observable.dart';
import 'package:apexo/utils/get_deterministic_item.dart';
import 'package:apexo/common_widgets/transitions/border.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/features/settings/services_settings/services_list_item.dart';
import 'package:apexo/services/backups.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/login.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/cupertino.dart';
import 'responsive_row.dart';
import '../applies_to_indicator.dart';

final _backupS3TestResult = ObservableState("");

class BackupsSettings extends StatefulWidget {
  const BackupsSettings({super.key});

  @override
  State<BackupsSettings> createState() => _BackupsSettingsState();
}

class _BackupsSettingsState extends State<BackupsSettings> {
  final TextEditingController _cronController = TextEditingController();
  final TextEditingController _maxKeepController = TextEditingController();
  final TextEditingController _endpointController = TextEditingController();
  final TextEditingController _bucketController = TextEditingController();
  final TextEditingController _regionController = TextEditingController();
  final TextEditingController _accessKeyController = TextEditingController();
  final TextEditingController _secretKeyController = TextEditingController();
  final ValueNotifier<bool> _autoBackupEnabled = ValueNotifier(false);
  final ValueNotifier<bool> _s3Enabled = ValueNotifier(false);
  final ValueNotifier<bool> _forcePathStyle = ValueNotifier(false);
  final ValueNotifier<bool> _showSecretKey = ValueNotifier(false);

  static const _presets = [
    ("backups_cron_hourly", "0 * * * *"),
    ("backups_cron_6hours", "0 */6 * * *"),
    ("backups_cron_12hours", "0 */12 * * *"),
    ("backups_cron_daily", "0 0 * * *"),
    ("backups_cron_daily3am", "0 3 * * *"),
    ("backups_cron_weekly", "0 0 * * 0"),
    ("backups_cron_monthly", "0 0 1 * *"),
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await login.pb!.settings.getAll();
      final backups = settings['backups'] ?? {};
      _cronController.text = backups['cron'] ?? '';
      _maxKeepController.text = (backups['cronMaxKeep'] ?? '5').toString();
      _autoBackupEnabled.value = (backups['cron'] ?? '').isNotEmpty;

      final s3 = backups['s3'] ?? {};
      _s3Enabled.value = s3['enabled'] ?? false;
      _endpointController.text = s3['endpoint'] ?? '';
      _bucketController.text = s3['bucket'] ?? '';
      _regionController.text = s3['region'] ?? '';
      _accessKeyController.text = s3['accessKey'] ?? '';
      _secretKeyController.text = s3['secret'] ?? '';
      _forcePathStyle.value = s3['forcePathStyle'] ?? false;
    } catch (e) {
      // Controllers remain empty on error
    }
    if (mounted) setState(() {});
  }

  Future<void> _saveSettings() async {
    try {
      await login.pb!.settings.update(body: {
        "backups": {
          "cron": _autoBackupEnabled.value ? _cronController.text : "",
          "cronMaxKeep": int.tryParse(_maxKeepController.text) ?? 5,
          "s3": {
            "enabled": _s3Enabled.value,
            "bucket": _bucketController.text,
            "region": _regionController.text,
            "endpoint": _endpointController.text,
            "accessKey": _accessKeyController.text,
            if (_secretKeyController.text.isNotEmpty)
              "secret": _secretKeyController.text,
            "forcePathStyle": _forcePathStyle.value,
          },
        }
      });
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: true,
          dismissWithEsc: true,
          builder: (context) => ContentDialog(
            style: dialogStyling(context, false, true),
            title: Txt(txt("success")),
            content: Txt(txt("backups_save_success")),
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
            content: Txt("${txt("backups_save_fail")}: $e"),
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
    _cronController.dispose();
    _maxKeepController.dispose();
    _endpointController.dispose();
    _bucketController.dispose();
    _regionController.dispose();
    _accessKeyController.dispose();
    _secretKeyController.dispose();
    _autoBackupEnabled.dispose();
    _s3Enabled.dispose();
    _forcePathStyle.dispose();
    _showSecretKey.dispose();
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

  String formatFileSize(int bytes) {
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB', 'PB', 'EB', 'ZB', 'YB'];
    var i = 0;
    var value = bytes.toDouble();
    while (value >= 1024 && i < suffixes.length - 1) {
      value /= 1024;
      i++;
    }
    return '${value.toStringAsPrecision(3)} ${suffixes[i]}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: Expander(
        leading: const Icon(FluentIcons.folder),
        header: Txt(txt("backups")),
        trailing: const AppliesToIndicator(scope: Scope.system),
        contentPadding: const EdgeInsets.all(10),
        content: SizedBox(
          width: 400,
          child: MStreamBuilder(
              streams: [
                backups.list.stream,
                backups.loaded.stream,
                backups.loading.stream,
                backups.creating.stream,
                backups.uploading.stream,
                backups.downloading.stream,
                backups.deleting.stream,
                backups.restoring.stream,
                _backupS3TestResult.stream,
              ],
              builder: (context, _) {
                return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: List<Widget>.from(backups.list().map(
                            (element) => buildBackupTile(element, context)))
                        .followedBy([
                      const SizedBox(height: 10),
                      buildBottomControls(),
                      const SizedBox(height: 15),
                      _buildBackupConfig(),
                    ]).toList());
              }),
        ),
      ),
    );
  }

  Widget _buildBackupConfig() {
    return MStreamBuilder(
      streams: [_backupS3TestResult.stream],
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InfoBar(
              title: Txt(txt("backups_config_title")),
              severity: InfoBarSeverity.info,
              content: Txt(txt("backups_config_desc")),
            ),
            const SizedBox(height: 15),
            ValueListenableBuilder<bool>(
              valueListenable: _autoBackupEnabled,
              builder: (context, value, _) {
                return Row(
                  children: [
                    ToggleSwitch(
                      checked: value,
                      onChanged: (v) => _autoBackupEnabled.value = v,
                    ),
                    const SizedBox(width: 10),
                    Txt(txt("backups_auto_enabled")),
                  ],
                );
              },
            ),
            const SizedBox(height: 15),
            Txt(txt("backups_cron")),
            const SizedBox(height: 5),
            Row(
              spacing: 5,
              children: [
                ComboBox<String>(
                  value: _cronController.text.isEmpty
                      ? null
                      : _cronController.text,
                  placeholder: Txt(txt("backups_cron_presets")),
                  items: _presets
                      .map((p) => ComboBoxItem(
                            value: p.$2,
                            child: Txt(txt(p.$1),
                                style: const TextStyle(fontSize: 12)),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) _cronController.text = v;
                    setState(() {});
                  },
                ),
                Expanded(
                  child: CupertinoTextField(
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: FluentTheme.of(context)
                              .inactiveColor
                              .withValues(alpha: 0.1)),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    controller: _cronController,
                    enabled: false,
                    placeholder: "0 0 * * *",
                    style: const TextStyle(color: Colors.grey),
                  ),
                ),
              ],
            ),
            _hint("backups_cron_hint"),
            const SizedBox(height: 15),
            ResponsiveRow(children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Txt(txt("backups_max_keep")),
                  const SizedBox(height: 5),
                  CupertinoTextField(
                    controller: _maxKeepController,
                    placeholder: "5",
                    keyboardType: TextInputType.number,
                  ),
                  _hint("backups_max_keep_hint"),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  ValueListenableBuilder<bool>(
                    valueListenable: _s3Enabled,
                    builder: (context, value, _) {
                      return Row(
                        children: [
                          ToggleSwitch(
                            checked: value,
                            onChanged: (v) => _s3Enabled.value = v,
                          ),
                          const SizedBox(width: 10),
                          Txt(txt("backups_s3_enabled")),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ]),
            if (_s3Enabled.value) ...[
              const SizedBox(height: 15),
              Txt(txt("s3_endpoint")),
              const SizedBox(height: 5),
              CupertinoTextField(
                controller: _endpointController,
                placeholder: "https://s3.amazonaws.com",
              ),
              _hint("s3_endpoint_hint"),
              const SizedBox(height: 15),
              ResponsiveRow(children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Txt(txt("s3_bucket")),
                    const SizedBox(height: 5),
                    CupertinoTextField(
                      controller: _bucketController,
                      placeholder: "my-backups",
                    ),
                    _hint("s3_bucket_hint"),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Txt(txt("s3_region")),
                    const SizedBox(height: 5),
                    CupertinoTextField(
                      controller: _regionController,
                      placeholder: "auto",
                    ),
                    _hint("s3_region_hint"),
                  ],
                ),
              ]),
              const SizedBox(height: 15),
              ResponsiveRow(children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Txt(txt("s3_accessKey")),
                    const SizedBox(height: 5),
                    CupertinoTextField(
                      controller: _accessKeyController,
                      placeholder: "AKIA...",
                    ),
                    _hint("s3_accessKey_hint"),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Txt(txt("s3_secretKey")),
                    const SizedBox(height: 5),
                    ValueListenableBuilder<bool>(
                      valueListenable: _showSecretKey,
                      builder: (context, show, _) {
                        return CupertinoTextField(
                          controller: _secretKeyController,
                          placeholder: txt("leaveBlankToKeepUnchanged"),
                          obscureText: !show,
                          suffix: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: IconButton(
                              onPressed: () => _showSecretKey.value = !show,
                              icon: Icon(
                                show ? FluentIcons.red_eye : FluentIcons.hide,
                                size: 18,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    _hint("s3_secretKey_hint"),
                  ],
                ),
              ]),
              const SizedBox(height: 15),
              ValueListenableBuilder<bool>(
                valueListenable: _forcePathStyle,
                builder: (context, value, _) {
                  return Row(
                    children: [
                      ToggleSwitch(
                        checked: value,
                        onChanged: (v) => _forcePathStyle.value = v,
                      ),
                      const SizedBox(width: 10),
                      Txt(txt("s3_forcePathStyle")),
                    ],
                  );
                },
              ),
              _hint("s3_forcePathStyle_hint"),
            ],
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
                    _backupS3TestResult(".");
                    try {
                      await login.pb!.settings.testS3();
                      _backupS3TestResult(txt("s3_test_success"));
                    } catch (e) {
                      _backupS3TestResult(
                          "ERROR: ${txt("s3_test_fail")}: ${e.toString()}");
                    }
                  },
                ),
                const SizedBox(width: 10),
                if (_backupS3TestResult().length == 1) const ProgressBar()
              ],
            ),
            if (_backupS3TestResult().length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 15),
                child: InfoBar(
                  title: _backupS3TestResult().startsWith("ERROR")
                      ? Txt(txt("fail"))
                      : Txt(txt("success")),
                  content: Txt(_backupS3TestResult()),
                  severity: _backupS3TestResult().startsWith("ERROR")
                      ? InfoBarSeverity.error
                      : InfoBarSeverity.success,
                ),
              ),
          ]
              .map((e) => [e, const SizedBox(height: 5)])
              .expand((e) => e)
              .toList(),
        );
      },
    );
  }

  Widget buildBackupTile(BackupFile element, BuildContext context) {
    return ServicesListItem(
      title: DF.fullCompact(element.date),
      subtitle: element.key,
      actions: [
        buildDownloadButton(element, context),
        buildDeleteButton(element, context),
        buildRestoreButton(element, context)
      ],
      trailingText: buildFileSize(element),
    );
  }

  Row buildBottomControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            buildCreateNewBackupButton(),
            const SizedBox(width: 10),
            buildUploadBackupButton(),
          ],
        ),
        buildRefreshButton()
      ],
    );
  }

  Tooltip buildRefreshButton() {
    return Tooltip(
      message: txt("refresh"),
      child: BorderColorTransition(
        animate: backups.loading(),
        child: IconButton(
          icon: const Icon(FluentIcons.sync, size: 17),
          iconButtonMode: IconButtonMode.large,
          onPressed: backups.reloadFromRemote,
        ),
      ),
    );
  }

  BorderColorTransition buildUploadBackupButton() {
    return BorderColorTransition(
      animate: backups.uploading(),
      child: Button(
        style: backups.uploading()
            ? ButtonStyle(
                backgroundColor:
                    WidgetStatePropertyAll(Colors.grey.withValues(alpha: 0.1)))
            : null,
        child: ButtonContent(FluentIcons.upload, txt("upload")),
        onPressed: () {
          if (backups.uploading()) return;
          backups.pickAndUpload();
        },
      ),
    );
  }

  BorderColorTransition buildCreateNewBackupButton() {
    return BorderColorTransition(
      animate: backups.creating(),
      child: Button(
        style: backups.creating()
            ? ButtonStyle(
                backgroundColor:
                    WidgetStatePropertyAll(Colors.grey.withValues(alpha: 0.1)))
            : null,
        child: ButtonContent(FluentIcons.add, txt("createNew")),
        onPressed: () {
          if (backups.creating()) return;
          backups.newBackup();
        },
      ),
    );
  }

  Container buildFileSize(BackupFile element) {
    return Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          color: getDeterministicItem(Colors.accentColors, element.key)
              .withValues(alpha: 0.1)),
      child: Txt(formatFileSize(element.size),
          style: const TextStyle(fontSize: 12)),
    );
  }

  Tooltip buildRestoreButton(BackupFile element, BuildContext context) {
    return Tooltip(
      message: txt("restoreBackup"),
      child: BorderColorTransition(
        animate: backups.restoring().containsKey(element.key),
        child: IconButton(
          icon: const Icon(FluentIcons.update_restore),
          onPressed: () {
            if (backups.restoring().containsKey(element.key)) return;
            showRestoreDialog(context, element);
          },
        ),
      ),
    );
  }

  showRestoreDialog(BuildContext context, BackupFile element) {
    return showDialog(
        barrierDismissible: true,
        dismissWithEsc: true,
        context: context,
        builder: (BuildContext context) {
          return ContentDialog(
            title: Txt(txt("restoreBackup")),
            style: dialogStyling(context, true, true),
            content: Txt(
                "${txt("restoreBackupWarning1")} (${DF.full(element.date)}) ${txt("restoreBackupWarning2")}"),
            actions: [
              const CloseButtonInDialog(),
              FilledButton(
                style: ButtonStyle(
                    backgroundColor: WidgetStatePropertyAll(Colors.red)),
                child: Txt(txt("restore")),
                onPressed: () async {
                  Navigator.pop(context);
                  await backups.restore(element.key);
                },
              ),
            ],
          );
        });
  }

  Tooltip buildDeleteButton(BackupFile element, BuildContext context) {
    return Tooltip(
      message: txt("delete"),
      child: BorderColorTransition(
        animate: backups.deleting().containsKey(element.key),
        child: IconButton(
          icon: const Icon(FluentIcons.delete),
          onPressed: () {
            if (backups.deleting().containsKey(element.key)) return;
            showDeleteDialog(context, element);
          },
        ),
      ),
    );
  }

  showDeleteDialog(BuildContext context, BackupFile element) {
    return showDialog(
        barrierDismissible: true,
        dismissWithEsc: true,
        context: context,
        builder: (BuildContext context) {
          return ContentDialog(
            title: Txt(txt("delete")),
            style: dialogStyling(context, true, true),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Txt("${txt("sureDeleteBackup")}: '${element.key}'?"),
                Txt("${txt("backupDate")}: ${DF.full(element.date)}"),
              ],
            ),
            actions: [
              const CloseButtonInDialog(),
              FilledButton(
                style: ButtonStyle(
                    backgroundColor: WidgetStatePropertyAll(Colors.red)),
                child: Txt(txt("delete")),
                onPressed: () async {
                  Navigator.pop(context);
                  await backups.delete(element.key);
                },
              ),
            ],
          );
        });
  }

  Tooltip buildDownloadButton(BackupFile element, BuildContext context) {
    return Tooltip(
      message: txt("download"),
      child: BorderColorTransition(
        animate: backups.downloading().containsKey(element.key),
        child: IconButton(
          icon: const Icon(FluentIcons.download),
          onPressed: () async {
            if (backups.downloading().containsKey(element.key)) return;
            final uri = await backups.downloadUri(element.key);
            if (context.mounted) {
              showDownloadDialog(context, uri);
            }
          },
        ),
      ),
    );
  }

  showDownloadDialog(BuildContext context, Uri uri) {
    return showDialog(
        barrierDismissible: true,
        dismissWithEsc: true,
        context: context,
        builder: (BuildContext context) {
          return ContentDialog(
            title: Txt(txt("download")),
            style: dialogStyling(context, false, true),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Txt("${txt("useTheFollowingLinkToDownloadTheBackup")}:"),
                const SizedBox(height: 10),
                StyledSelectableText(text: uri.toString()),
              ],
            ),
            actions: const [
              SizedBox(),
              SizedBox(),
              CloseButtonInDialog(),
            ],
          );
        });
  }
}

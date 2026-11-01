import 'dart:async';
import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/delete_button.dart';
import 'package:apexo/common_widgets/dialogs/close_dialog_button.dart';
import 'package:apexo/common_widgets/dialogs/dialog_styling.dart';
import 'package:apexo/common_widgets/dialogs/export_patients_dialog.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/core/reactive/observable.dart';
import 'backup_file_tile.dart';
import 'package:apexo/common_widgets/transitions/border.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/widget_keys.dart';
import 'package:apexo/services/backups.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/login.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'responsive_row.dart';
import '../applies_to_indicator.dart';
import '../settings_card.dart';

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
    unawaited(_loadSettings());
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await login.pb!.settings.getAll();
      if (!mounted) return;
      final backups = settings['backups'] as Map<String, dynamic>? ?? {};
      _cronController.text = backups['cron'] as String? ?? '';
      _maxKeepController.text = (backups['cronMaxKeep'] ?? '5').toString();
      _autoBackupEnabled.value = (backups['cron'] as String? ?? '').isNotEmpty;

      final s3 = backups['s3'] as Map<String, dynamic>? ?? {};
      _s3Enabled.value = s3['enabled'] as bool? ?? false;
      _endpointController.text = s3['endpoint'] as String? ?? '';
      _bucketController.text = s3['bucket'] as String? ?? '';
      _regionController.text = s3['region'] as String? ?? '';
      _accessKeyController.text = s3['accessKey'] as String? ?? '';
      _secretKeyController.text = s3['secret'] as String? ?? '';
      _forcePathStyle.value = s3['forcePathStyle'] as bool? ?? false;
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
        unawaited(showDialog(
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
            content: Txt("${txt("backups_save_fail")}: $e"),
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
      child: Txt(
        txt(key),
        style: TextStyle(
            fontSize: 12,
            color: FluentTheme.of(context).resources.textFillColorSecondary),
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
      padding: EdgeInsets.zero,
      child: SettingsCard(
        key: WK.serviceSection('backups'),
        leading: const Icon(FluentIcons.folder),
        header: Txt(txt("backups")),
        trailing: const AppliesToIndicator(scope: Scope.system),
        contentPadding: const EdgeInsets.only(top: 20),
        content: SizedBox(
          width: double.infinity,
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
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    buildBottomControls(),
                    const SizedBox(height: 16),
                    _buildBackupGrid(context),
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 24),
                    _buildBackupConfig(),
                  ],
                );
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
                    Expanded(child: Txt(txt("backups_auto_enabled"))),
                  ],
                );
              },
            ),
            const SizedBox(height: 15),
            Txt(txt("backups_cron")),
            const SizedBox(height: 5),
            ResponsiveRow(
              children: [
                ComboBox<String>(
                  key: WK.serviceField('backups_cron'),
                  isExpanded: true,
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
                TextBox(
                  controller: _cronController,
                  enabled: false,
                  placeholder: "0 0 * * *",
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
                  TextBox(
                    key: WK.serviceField('backups_maxKeep'),
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
                          Expanded(child: Txt(txt("backups_s3_enabled"))),
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
              TextBox(
                key: WK.serviceField('backups_s3_endpoint'),
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
                    TextBox(
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
                    TextBox(
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
                    TextBox(
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
                        return TextBox(
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
                      Expanded(child: Txt(txt("s3_forcePathStyle"))),
                    ],
                  );
                },
              ),
              _hint("s3_forcePathStyle_hint"),
            ],
            const SizedBox(height: 20),
            Wrap(
              runSpacing: 8,
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
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
                if (_backupS3TestResult().length == 1)
                  const SizedBox(
                      width: 20,
                      height: 20,
                      child: ProgressRing(strokeWidth: 2))
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

  Widget _buildBackupGrid(BuildContext context) {
    final files = backups.list();
    if (files.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: backups.loading()
              ? const ProgressRing()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(WindowsIcons.zip_folder,
                        size: 36,
                        color: FluentTheme.of(context)
                            .resources
                            .textFillColorSecondary),
                    const SizedBox(height: 12),
                    Txt(txt('noFiles')),
                  ],
                ),
        ),
      );
    }
    return LayoutBuilder(builder: (context, constraints) {
      const gap = 12.0;
      final textScale = MediaQuery.textScalerOf(context).scale(13) / 13;
      final columns = ((constraints.maxWidth + gap) / (220 * textScale + gap))
          .floor()
          .clamp(1, 4);
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final file in files)
            SizedBox(width: width, child: buildBackupTile(file, context)),
        ],
      );
    });
  }

  Widget buildBackupTile(BackupFile element, BuildContext context) {
    return BackupFileTile(
      key: WK.backupRow(element.key),
      fileName: element.key,
      modifiedLabel: DF.fullCompact(element.date),
      sizeLabel: formatFileSize(element.size),
      actions: [
        buildDownloadButton(element, context),
        buildRestoreButton(element, context),
        buildDeleteButton(element, context),
      ],
    );
  }

  Widget buildBottomControls() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        buildCreateNewBackupButton(),
        buildUploadBackupButton(),
        buildRefreshButton(),
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
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(FluentIcons.upload, size: 16),
          const SizedBox(width: 8),
          Flexible(child: Txt(txt("upload"))),
        ]),
        onPressed: () {
          if (backups.uploading()) return;
          unawaited(backups.pickAndUpload());
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
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(FluentIcons.add, size: 16),
          const SizedBox(width: 8),
          Flexible(child: Txt(txt("createNew"))),
        ]),
        onPressed: () {
          if (backups.creating()) return;
          unawaited(backups.newBackup());
        },
      ),
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
            unawaited(showRestoreDialog(context, element));
          },
        ),
      ),
    );
  }

  Future<Object?> showRestoreDialog(BuildContext context, BackupFile element) {
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
              Button(
                onPressed: () => Navigator.pop(context),
                child: Txt(txt("cancel")),
              ),
              FilledButton(
                style: filledButtonStyle(Colors.red),
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
        child: DeleteButton(
          actionIcon: WindowsIcons.delete,
          actionText: txt("delete"),
          preview: Txt("${txt("backup")}: ${DF.full(element.date)}"),
          restorable: false,
          onConfirm: () {
            unawaited(backups.delete(element.key));
          },
          child: const Icon(WindowsIcons.delete),
        ),
      ),
    );
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
              unawaited(showDownloadDialog(context, uri));
            }
          },
        ),
      ),
    );
  }

  Future<Object?> showDownloadDialog(BuildContext context, Uri uri) {
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

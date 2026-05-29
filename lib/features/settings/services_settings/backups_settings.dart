import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/dialogs/close_dialog_button.dart';
import 'package:apexo/common_widgets/dialogs/dialog_styling.dart';
import 'package:apexo/common_widgets/dialogs/export_patients_dialog.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/utils/get_deterministic_item.dart';
import 'package:apexo/common_widgets/transitions/border.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/features/settings/services_settings/services_list_item.dart';
import 'package:apexo/services/backups.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:fluent_ui/fluent_ui.dart';

class BackupsSettings extends StatelessWidget {
  const BackupsSettings({
    super.key,
  });

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
              ],
              builder: (context, _) {
                return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: List<Widget>.from(backups.list().map(
                            (element) => buildBackupTile(element, context)))
                        .followedBy([
                      const SizedBox(height: 10),
                      buildBottomControls()
                    ]).toList());
              }),
        ),
      ),
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

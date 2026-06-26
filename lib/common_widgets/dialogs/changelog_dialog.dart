import 'package:apexo/common_widgets/dialogs/close_dialog_button.dart';
import 'package:apexo/common_widgets/dialogs/dialog_styling.dart';
import 'package:apexo/services/changelog.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// Shows the changelog for a given version. If [version] is omitted,
/// the latest version's changelog is shown.
Future<void> showChangelogDialog(
  BuildContext context, {
  ChangelogVersion? entry,
}) async {
  entry ??= await changelog.latest();
  if (entry == null || entry.changes.isEmpty) return;

  if (!context.mounted) return;

  showDialog(
    barrierDismissible: true,
    dismissWithEsc: true,
    context: context,
    builder: (ctx) => _ChangelogDialog(entry: entry!),
  );
}

class _ChangelogDialog extends StatefulWidget {
  const _ChangelogDialog({required this.entry});

  final ChangelogVersion entry;

  @override
  State<_ChangelogDialog> createState() => _ChangelogDialogState();
}

class _ChangelogDialogState extends State<_ChangelogDialog> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 350, maxHeight: 440),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '${txt("changelogDialogTitle")}  v${widget.entry.version}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          IconButton(
            icon: const Icon(WindowsIcons.cancel),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      content: SingleChildScrollView(
        controller: _scrollController,
        child: Txt(
          widget.entry.changes.join('\n'),
          maxLines: 99999,
          style: TextStyle(
            fontSize: 13,
            height: 1.6,
            color: FluentTheme.of(context)
                .typography
                .body
                ?.color
                ?.withValues(alpha: 0.85),
          ),
        ),
      ),
      style: dialogStyling(context, false),
      actions: const [CloseButtonInDialog(buttonText: "close")],
    );
  }
}

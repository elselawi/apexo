import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';

class BackupFileTile extends StatelessWidget {
  const BackupFileTile({
    super.key,
    required this.fileName,
    required this.modifiedLabel,
    required this.sizeLabel,
    required this.actions,
  });

  final String fileName;
  final String modifiedLabel;
  final String sizeLabel;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final secondary = TextStyle(
      fontSize: 12,
      color: theme.resources.textFillColorSecondary,
    );
    return Container(
      decoration: BoxDecoration(
        color: theme.resources.cardBackgroundFillColorDefault,
        border: Border.all(color: theme.resources.cardStrokeColorDefault),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 80,
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.accentColor.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(WindowsIcons.zip_folder,
                size: 40, color: theme.accentColor),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Tooltip(
                  message: fileName,
                  child: SizedBox(
                    height: MediaQuery.textScalerOf(context).scale(13) * 2.8,
                    child: Txt(
                      fileName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Tooltip(
                  message: modifiedLabel,
                  child: Txt(modifiedLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: secondary),
                ),
                const SizedBox(height: 4),
                Txt(sizeLabel, style: secondary),
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Wrap(spacing: 4, runSpacing: 4, children: actions),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

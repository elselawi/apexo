import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/error_dialog.dart';
import 'package:apexo/utils/imgs.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// Saves the file on screen to the device.
class FileDownloadButton extends StatefulWidget {
  const FileDownloadButton({
    super.key,
    this.rowId,
    this.buttonLabel,
    required this.name,
  });

  final String? rowId;
  final String name;
  final String? buttonLabel;

  @override
  State<FileDownloadButton> createState() => _FileDownloadButtonState();
}

class _FileDownloadButtonState extends State<FileDownloadButton> {
  bool _isDownloading = false;

  Future<void> _download() async {
    setState(() => _isDownloading = true);
    try {
      await downloadFile(widget.rowId, widget.name);
    } catch (e) {
      if (mounted) showErrorMessage(e, "downloadingFile");
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: _isDownloading
          ? const SizedBox(
              width: 18, height: 18, child: ProgressRing(strokeWidth: 2))
          : ButtonContent(WindowsIcons.download, widget.buttonLabel ?? "",
              size: 18),
      onPressed: _isDownloading ? null : _download,
      style: const ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(Colors.white),
      ),
    );
  }
}

/// The photo a delete prompt shows, taken from what is already on screen rather
/// than fetched again.

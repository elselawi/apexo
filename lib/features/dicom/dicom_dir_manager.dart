import 'package:apexo/services/localization/locale.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';

class DicomDirectoryManager extends StatefulWidget {
  const DicomDirectoryManager({
    super.key,
    required this.dirs,
    required this.onChanged,
  });

  final List<String> dirs;
  final Function(List<String> dirs) onChanged;

  @override
  State<DicomDirectoryManager> createState() => _DicomDirectoryManagerState();
}

class _DicomDirectoryManagerState extends State<DicomDirectoryManager> {
  Future<void> pickAndAdd() async {
    final result = await FilePicker.getDirectoryPath(
      dialogTitle: txt("dicomWatchDir"),
    );
    if (result != null && !widget.dirs.contains(result)) {
      widget.onChanged([...widget.dirs, result]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.dirs.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
              txt("dicomWatchDir_notSet"),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontStyle: FontStyle.italic,
                color: FluentTheme.of(context).resources.textFillColorDisabled,
              ),
            ),
          )
        else
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: widget.dirs.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(FluentIcons.folder_open,
                        size: 16,
                        color: FluentTheme.of(context)
                            .resources
                            .textFillColorTertiary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.dirs[i],
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(FluentIcons.delete, size: 16),
                      onPressed: () {
                        setState(() {
                          widget.onChanged([...widget.dirs]..removeAt(i));
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 12),
        Align(
          alignment: AlignmentDirectional.topStart,
          child: Button(
            onPressed: () async {
              await pickAndAdd();
              setState(() {});
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(FluentIcons.add, size: 16),
                const SizedBox(width: 6),
                Txt(txt("dicomAddFolder")),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

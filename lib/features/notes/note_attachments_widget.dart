import 'package:apexo/features/notes/notes_model.dart';
import 'package:apexo/features/notes/notes_store.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:http/http.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:url_launcher/url_launcher.dart';

class NoteAttachmentsWidget extends StatefulWidget {
  final Note note;
  final bool canUpload;

  const NoteAttachmentsWidget({super.key, required this.note, this.canUpload = true});

  @override
  State<NoteAttachmentsWidget> createState() => _NoteAttachmentsWidgetState();
}

class _NoteAttachmentsWidgetState extends State<NoteAttachmentsWidget> {
  bool _uploadingAttachment = false;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 5,
      children: [
        Wrap(
          children: List.generate(
            widget.note.attachments.length,
            (index) {
              final attachment = widget.note.attachments[index];
              return _buildSingleFileDownloadButton(theme, attachment);
            },
          ),
        ),
        if(widget.canUpload) Button(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _uploadingAttachment
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: ProgressRing(),
                    )
                  : const Icon(WindowsIcons.attach),
              const SizedBox(width: 5),
              Txt(txt("addAttachment")),
            ],
          ),
          onPressed: () async {
            final file = await pickAndUpload();
            if (file != null) {
              notes.set(widget.note..attachments.add(file));
            }
          },
        )
      ],
    );
  }

  Widget _buildSingleFileDownloadButton(
    FluentThemeData theme,
    String attachment,
  ) {
    return Tooltip(
      message: txt("tapToDownload"),
      child: IconButton(
        icon: Container(
          width: 80,
          height: 80,
          padding: const EdgeInsets.all(1),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: theme.inactiveColor.withValues(alpha: 0.6)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              const Icon(FluentIcons.download_document, size: 36),
              Text(
                Uri.parse(attachment).pathSegments.last,
                style: theme.typography.caption?.copyWith(
                    backgroundColor:
                        theme.inactiveBackgroundColor.withValues(alpha: 0.7)),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        onPressed: () {
          launchUrl(Uri.parse(attachment));
        },
      ),
    );
  }

  Future<String?> pickAndUpload() async {
    try {
      final filePickerRes = await FilePicker.pickFiles(
        allowMultiple: false,
        withReadStream: true,
        type: FileType.any,
      );
      if (filePickerRes == null) {
        return null;
      }
      if (filePickerRes.files.isEmpty) {
        return null;
      }
      final file = filePickerRes.files.first;
      setState(() {
        _uploadingAttachment = true;
      });
      final uploadRes = await notes.remote!.remoteRows.update(
        widget.note.id,
        files: [
          await MultipartFile.fromPath("imgs+", file.path!, filename: file.name)
        ],
        fields: "imgs",
      );
      final url = login.pb!.files
          .getURL(
            RecordModel({"id": widget.note.id, "collectionId": "data"}),
            uploadRes.data["imgs"].last,
          )
          .toString();
      return url;
    } finally {
      setState(() {
        _uploadingAttachment = false;
      });
    }
  }
}

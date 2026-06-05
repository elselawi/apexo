import 'dart:convert';
import 'package:apexo/app/routes.dart';
import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/dialogs/close_dialog_button.dart';
import 'package:apexo/common_widgets/dialogs/dialog_styling.dart';
import 'package:apexo/common_widgets/error_dialog.dart';
import 'package:apexo/common_widgets/keyboard_aware.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/utils/imgs.dart';
import 'package:apexo/utils/logger.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart';

class ImportDialog extends StatefulWidget {
  final Panel<Appointment> panel;

  const ImportDialog({super.key, required this.panel});

  @override
  State<ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<ImportDialog> {
  final importPhotosFromLinkController = TextEditingController();

  // empty means ready
  // . means loading
  // any other string means error
  String status = "";

  @override
  void dispose() {
    importPhotosFromLinkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardAwareView(
      child: ContentDialog(
        title: const SizedBox(),
        style: dialogStyling(context, false, true),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InfoBar(
              title: Txt(txt("importingPhotosFromLink")),
              content: Txt(txt("useThisForm")),
            ),
            const SizedBox(height: 10),
            if (status.length > 1)
              InfoBar(
                title: Txt(txt("error")),
                content: Txt(status),
                severity: InfoBarSeverity.error,
              ),
            const SizedBox(height: 10),
            InfoLabel(
              label: txt("link"),
              child: CupertinoTextField(
                  controller: importPhotosFromLinkController,
                  placeholder: txt("enterLink")),
            ),
          ],
        ),
        actions: [
          if (status.length == 1) const ProgressBar(),
          const CloseButtonInDialog(),
          FilledButton(
            style: filledButtonStyle(Colors.blue),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(WindowsIcons.save),
              const SizedBox(width: 5),
              Txt(txt("import"))
            ]),
            onPressed: () async {
              // cache the id so that if the user opens another appointment
              // the photos would go to the correct appointment
              final id = widget.panel.item.id;
              setState(() {
                status = ".";
              });
              widget.panel.selectedTab(widget.panel.selectedTab());
              List<String> res;
              try {
                final url = Uri.parse(
                    'https://imgs.apexo.app/?url=${Uri.encodeComponent(importPhotosFromLinkController.text)}');
                final response = await get(url);
                if (response.statusCode != 200) {
                  throw Exception(response.body);
                } else {
                  setState(() {
                    status = "";
                  });
                  res = List<String>.from(jsonDecode(response.body));
                }
              } catch (e) {
                setState(() {
                  status = e.toString();
                });
                widget.panel.selectedTab(widget.panel.selectedTab());
                return;
              }
              if (context.mounted) Navigator.pop(context);
              widget.panel.inProgress(true);
              try {
                for (var imgLink in res) {
                  final imgName =
                      await handleNewImage(rowID: id, sourcePath: imgLink);
                  if (widget.panel.item.imgs.contains(imgName) == false) {
                    widget.panel.item.imgs.add(imgName);
                    appointments.set(widget.panel.item);
                    widget.panel.savedJson =
                        jsonEncode(widget.panel.item.toJson());
                  }
                  widget.panel.selectedTab(widget.panel.selectedTab());
                }
              } catch (e, s) {
                showErrorMessage(e, "importingRemoteImages");
                login.askForLoginAgain(e);
                logger("Error during images importing: $e", s);
              }
              widget.panel.inProgress(false);
              widget.panel.selectedTab(widget.panel.selectedTab());
            },
          ),
        ],
      ),
    );
  }
}

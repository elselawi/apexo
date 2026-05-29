import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/dialogs/close_dialog_button.dart';
import 'package:apexo/common_widgets/dialogs/dialog_styling.dart';
import 'package:apexo/core/store.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/utils/json_to_csv.dart';
import 'package:apexo/utils/csv_to_json.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

class ImportPatientsDialog extends StatefulWidget {
  const ImportPatientsDialog({super.key});

  @override
  State<ImportPatientsDialog> createState() => _ImportPatientsDialogState();
}

class _ImportPatientsDialogState extends State<ImportPatientsDialog> {
  final controller = FlyoutController();
  final patientsController = TextEditingController();
  final aptsController = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    patientsController.dispose();
    aptsController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    patientsController.addListener(() {
      setState(() {});
    });
    aptsController.addListener(() {
      setState(() {});
    });
  }

  import() {
    final patientsJson = csvToJsonList(patientsController.text);
    final aptsJson = csvToJsonList(aptsController.text);

    patients.setAll(patientsJson.map((p) => Patient.fromJson(p)).toList());
    appointments.setAll(aptsJson.map((p) => Appointment.fromJson(p)).toList());

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      style: dialogStyling(context, false, true),
      actions: [
        FilledButton(
          style:
              (patientsController.text.isEmpty && aptsController.text.isEmpty)
                  ? filledButtonStyle(Colors.grey.withAlpha(100))
                  : null,
          onPressed: import,
          child: ButtonContent(WindowsIcons.copy, txt("import")),
        ),
        const CloseButtonInDialog(buttonText: "close")
      ],
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Txt(txt("import")),
          FlyoutTarget(
            controller: controller,
            child: Button(
                child: ButtonContent(WindowsIcons.info, txt("howToUse")),
                onPressed: () {
                  showHowTo(controller);
                }),
          ),
          IconButton(
              icon: const Icon(FluentIcons.cancel),
              onPressed: () => Navigator.pop(context))
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 5,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            spacing: 5,
            children: [
              const Icon(FluentIcons.medication_admin),
              Txt("${txt("patients")}:"),
            ],
          ),
          CupertinoTextField(
            maxLines: 3,
            controller: patientsController,
            placeholder: txt("patients"),
          ),
          const SizedBox.shrink(),
          Row(
            spacing: 5,
            children: [
              const Icon(WindowsIcons.calendar),
              Txt("${txt("appointments")}:"),
            ],
          ),
          CupertinoTextField(
            maxLines: 3,
            controller: aptsController,
            placeholder: txt("appointments"),
          )
        ],
      ),
    );
  }
}

class ExportPatientsDialog extends StatefulWidget {
  final Set<String> ids;
  const ExportPatientsDialog({
    super.key,
    required this.ids,
  });

  @override
  State<ExportPatientsDialog> createState() => _ExportPatientsDialogState();
}

class _ExportPatientsDialogState extends State<ExportPatientsDialog> {
  int _currentIndex = 0;

  late List<Map<String, dynamic>> sPatientsD;
  late List<Map<String, dynamic>> sAptsD;

  final controller = FlyoutController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final sPatients = widget.ids
        .map((id) => patients.get(id))
        .where((e) => e != null)
        .toList();
    sPatientsD = sPatients.map((e) => e!.toJson()).toList();
    final sApts =
        sPatients.map((p) => p!.allAppointments).expand((e) => e).toList();
    sAptsD = sApts.map((e) => e.toJson()).toList();
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      style: dialogStyling(context, false, true),
      actions: const [CloseButtonInDialog(buttonText: "close")],
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Txt(txt("exportSelected")),
          FlyoutTarget(
            controller: controller,
            child: Button(
                child: ButtonContent(WindowsIcons.info, txt("howToUse")),
                onPressed: () {
                  showHowTo(controller);
                }),
          ),
          IconButton(
              icon: const Icon(FluentIcons.cancel),
              onPressed: () => Navigator.pop(context))
        ],
      ),
      content: SizedBox(
        height: 295,
        child: TabView(
          currentIndex: _currentIndex,
          tabs: [
            _createExporterTab(
              context: context,
              data: sPatientsD,
              store: patients,
              isSelected: _currentIndex == 0,
              icon: FluentIcons.medication_admin,
            ),
            _createExporterTab(
              context: context,
              data: sAptsD,
              store: appointments,
              isSelected: _currentIndex == 1,
              icon: WindowsIcons.calendar,
            )
          ],
          onChanged: (i) {
            _currentIndex = i;
            setState(() {});
          },
        ),
      ),
    );
  }
}

showHowTo(FlyoutController controller) {
  controller.showFlyout(
    builder: (ctx) {
      return SizedBox(
        child: TeachingTip(
          title: Txt("${txt("import")} / ${txt("export")}"),
          subtitle: Txt(txt("exportImportFeatureExplanation")),
        ),
      );
    },
  );
}

Tab _createExporterTab(
    {required List<Map<String, dynamic>> data,
    required Store store,
    required bool isSelected,
    required IconData icon,
    required BuildContext context}) {
  final theme = FluentTheme.of(context);
  return Tab(
    backgroundColor:
        WidgetStatePropertyAll(isSelected ? Colors.black : Colors.transparent),
    outlineColor: WidgetStatePropertyAll(
        isSelected ? theme.resources.cardStrokeColorDefault : Colors.red),
    icon: Icon(icon),
    text: Txt(txt(store.local!.name)),
    body: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: theme.menuColor,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: theme.resources.cardStrokeColorDefault,
          )),
      child: _Exporter(
        data: data,
        store: store,
      ),
    ),
  );
}

class _Exporter extends StatefulWidget {
  final List<Map<String, dynamic>> data;
  final Store store;
  const _Exporter({
    required this.data,
    required this.store,
  });

  @override
  State<_Exporter> createState() => _ExporterState();
}

class _ExporterState extends State<_Exporter> {
  final List<String> availableFields = [];
  final List<int> selectedFields = [1, 4];
  bool exportAllFields = false;
  bool exportHeader = true;

  @override
  void initState() {
    super.initState();

    final fields = jsonListToCsv(widget.data);
    availableFields.addAll(fields.split("\n")[0].split(","));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 5,
      children: [
        Txt("${txt(widget.store.local!.name)} (${widget.data.length}):"),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color:
                  FluentTheme.of(context).inactiveColor.withValues(alpha: .2),
            ),
            color: FluentTheme.of(context).resources.subtleFillColorDisabled,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(5),
            scrollDirection: Axis.horizontal,
            child: Row(
              spacing: 10,
              children: [
                Checkbox(
                    checked: exportHeader,
                    onChanged: (v) {
                      exportHeader = v ?? false;
                      setState(() {});
                    },
                    content: Text(txt("title"))),
                Checkbox(
                    checked: exportAllFields,
                    onChanged: (v) {
                      exportAllFields = v ?? false;
                      setState(() {});
                    },
                    content: Text(txt("all"))),
                if (!exportAllFields)
                  ...List.generate(availableFields.length, (index) {
                    final f = availableFields[index];
                    return Checkbox(
                      checked: selectedFields.contains(index),
                      onChanged: (v) {
                        if (v == true) {
                          selectedFields.add(index);
                        } else {
                          selectedFields.remove(index);
                        }
                        setState(() {});
                      },
                      content: Text(f,
                          style: FluentTheme.of(context).typography.bodyStrong),
                    );
                  })
              ],
            ),
          ),
        ),
        StyledSelectableText(
            text: jsonListToCsv(
          widget.data,
          includeColumns: exportAllFields ? null : selectedFields,
          withHeader: exportHeader,
        )),
      ],
    );
  }
}

class StyledSelectableText extends StatefulWidget {
  final String text;
  final double height;
  final double width;
  const StyledSelectableText({
    super.key,
    required this.text,
    this.height = 150,
    this.width = double.infinity,
  });

  @override
  State<StyledSelectableText> createState() => _StyledSelectableTextState();
}

class _StyledSelectableTextState extends State<StyledSelectableText> {
  bool didCopy = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: FluentTheme.of(context).inactiveColor.withValues(alpha: .2),
        ),
        color: FluentTheme.of(context).resources.cardStrokeColorDefault,
      ),
      margin: const EdgeInsets.only(top: 10),
      height: widget.height,
      width: widget.width,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Stack(
          fit: StackFit.expand,
          children: [
            SelectableText(widget.text, textDirection: TextDirection.ltr),
            PositionedDirectional(
              end: 0,
              bottom: 0,
              child: IconButton(
                style: filledButtonStyle(Colors.grey),
                icon: Row(
                  children: [
                    const Icon(WindowsIcons.copy),
                    if (didCopy) ...[
                      const SizedBox(width: 5),
                      const Icon(WindowsIcons.check_mark),
                    ],
                  ],
                ),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: widget.text));
                  setState(() => didCopy = true);
                  Future.delayed(const Duration(seconds: 2), () {
                    if (context.mounted) setState(() => didCopy = false);
                  });
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

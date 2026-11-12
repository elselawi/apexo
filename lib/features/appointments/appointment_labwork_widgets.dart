import 'package:apexo/features/appointments/appointment_commands.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// The visit's labwork body, shared by the panel and the labwork window.
class AppointmentLabworkSection extends StatefulWidget {
  const AppointmentLabworkSection({
    super.key,
    required this.appointment,
    this.hasOrder,
    this.onEdited,
  });

  final Appointment appointment;

  /// Whether an order exists; this body and the window's footer sync both ways.
  final ValueNotifier<bool>? hasOrder;

  /// Reports a draft change; starting an order is saved like a typed field.
  final VoidCallback? onEdited;

  @override
  State<AppointmentLabworkSection> createState() =>
      _AppointmentLabworkSectionState();
}

class _AppointmentLabworkSectionState extends State<AppointmentLabworkSection> {
  @override
  void initState() {
    super.initState();
    widget.hasOrder?.addListener(_orderChangedElsewhere);
    widget.hasOrder?.value = widget.appointment.hasLabwork;
  }

  @override
  void didUpdateWidget(covariant AppointmentLabworkSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.hasOrder, widget.hasOrder)) {
      oldWidget.hasOrder?.removeListener(_orderChangedElsewhere);
      widget.hasOrder?.addListener(_orderChangedElsewhere);
    }
    if (!identical(oldWidget.hasOrder, widget.hasOrder) ||
        !identical(oldWidget.appointment, widget.appointment)) {
      widget.hasOrder?.value = widget.appointment.hasLabwork;
    }
  }

  @override
  void dispose() {
    widget.hasOrder?.removeListener(_orderChangedElsewhere);
    super.dispose();
  }

  /// The window's footer took the order away: the body shows what it says.
  void _orderChangedElsewhere() {
    final hasOrder = widget.hasOrder?.value ?? widget.appointment.hasLabwork;
    // Redraw even when the draft already carries the new state: the footer's
    // removal writes through instead of passing through `_setHasLabwork`.
    setState(() => widget.appointment.hasLabwork = hasOrder);
    widget.onEdited?.call();
  }

  void _setHasLabwork(bool hasLabwork) {
    setState(() => widget.appointment.hasLabwork = hasLabwork);
    widget.hasOrder?.value = hasLabwork;
    widget.onEdited?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.appointment.hasLabwork) {
      return LabWorkEditor(
        appointment: widget.appointment,
        onEdited: widget.onEdited,
      );
    }
    return Button(
      key: WK.btnAddLabwork,
      onPressed: () => _setHasLabwork(true),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(FluentIcons.manufacturing),
          const SizedBox(width: 15),
          // The label is long in most locales: let it wrap instead of overflowing.
          Flexible(child: Txt(txt("addLabwork"), softWrap: true)),
        ],
      ),
    );
  }
}

class LabWorkEditor extends StatefulWidget {
  const LabWorkEditor({super.key, required this.appointment, this.onEdited});
  final Appointment appointment;
  final VoidCallback? onEdited;
  @override
  State<LabWorkEditor> createState() => _LabWorkEditorState();
}

class _LabWorkEditorState extends State<LabWorkEditor> {
  final labNameController = TextEditingController();
  final labOrderNotesController = TextEditingController();

  @override
  void dispose() {
    labNameController.dispose();
    labOrderNotesController.dispose();
    transcriptionEditCounter.unObserve(_updateWhenTranscriptionOccurs);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant LabWorkEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.appointment, widget.appointment)) {
      _fillControllers();
    }
  }

  void _fillControllers() {
    labNameController.text = widget.appointment.labName;
    labOrderNotesController.text = widget.appointment.labworkNotes;
  }

  void _updateWhenTranscriptionOccurs(Object? _) {
    if (mounted) {
      setState(_fillControllers);
    }
  }

  @override
  void initState() {
    super.initState();
    _fillControllers();
    transcriptionEditCounter.observe(_updateWhenTranscriptionOccurs);
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    final color = widget.appointment.labworkReceived
        ? theme.accentColor
        : Colors.warningPrimaryColor;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: color, width: 4),
          bottom: BorderSide(color: color),
          left: BorderSide(color: color),
          right: BorderSide(color: color),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Txt(
            txt("labworks"),
            style: theme.typography.bodyStrong,
          ),
          const SizedBox(height: 5),
          const Divider(),
          const SizedBox(height: 5),
          Row(
            children: [
              Row(
                children: [
                  const Icon(FluentIcons.manufacturing, size: 20),
                  const SizedBox(width: 5),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    child: Txt(
                      txt("laboratory"),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 5),
              Expanded(
                child: AutoSuggestBox<String>(
                  key: WK.fieldLabworkLabName,
                  decoration: WidgetStatePropertyAll(BoxDecoration(
                      color: Colors.transparent,
                      border: Border.all(color: Colors.transparent))),
                  clearButtonEnabled: false,
                  placeholder: "${txt("laboratory")}...",
                  noResultsFoundBuilder: (context) => Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Txt(txt("noSuggestions")),
                  ),
                  onChanged: (text, reason) {
                    if (reason == TextChangedReason.userInput) {
                      widget.appointment.labName = text;
                      widget.onEdited?.call();
                    }
                  },
                  onSelected: (item) {
                    widget.appointment.labName = item.value ?? item.label;
                    widget.onEdited?.call();
                  },
                  controller: labNameController,
                  items: appointments.labs
                      .map((name) =>
                          AutoSuggestBoxItem<String>(value: name, label: name))
                      .toList(),
                ),
              )
            ],
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormBox(
                  prefix: const Icon(WindowsIcons.quick_note),
                  // Separate key from `fieldLabworkLabName`; duplicates make this
                  // field unaddressable.
                  key: WK.fieldLabworkOrderNotes,
                  decoration: WidgetStatePropertyAll(BoxDecoration(
                      color: Colors.transparent,
                      border: Border.all(color: Colors.transparent))),
                  placeholder: "${txt("orderNotes")}...",
                  maxLines: null,
                  controller: labOrderNotesController,
                  onChanged: (value) {
                    widget.appointment.labworkNotes = value;
                    widget.onEdited?.call();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Checkbox(
            key: WK.fieldLabworkReceived,
            checked: widget.appointment.labworkReceived,
            onChanged: (v) => setState(() {
              widget.appointment.labworkReceived = v ?? false;
              widget.onEdited?.call();
            }),
            content: Txt(txt("received")),
          ),
        ],
      ),
    );
  }
}

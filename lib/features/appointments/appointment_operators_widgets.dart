import 'package:apexo/features/accounts/accounts_controller.dart';
import 'package:apexo/features/appointments/appointment_commands.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// The operators checklist shared by every surface. It reads the live visit each
/// build: a tick writes through [appointmentCommand], not the trigger's copy.
class AppointmentOperatorsFlyout extends StatefulWidget {
  const AppointmentOperatorsFlyout({
    super.key,
    required this.appointmentId,
    this.onChanged,
  });

  final String appointmentId;

  final VoidCallback? onChanged;

  @override
  State<AppointmentOperatorsFlyout> createState() =>
      _AppointmentOperatorsFlyoutState();
}

class _AppointmentOperatorsFlyoutState
    extends State<AppointmentOperatorsFlyout> {
  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final selected =
        liveAppointment(widget.appointmentId)?.operatorsIDs.toSet();
    final operators = accounts.operators;
    return Container(
      constraints: const BoxConstraints(maxHeight: 300, maxWidth: 220),
      decoration: BoxDecoration(
        color: theme.resources.solidBackgroundFillColorBase,
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 4),
            child: Row(children: [
              Icon(FluentIcons.people, size: 14, color: theme.inactiveColor),
              const SizedBox(width: 8),
              Txt(txt("selectDoctors"),
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 12)),
            ]),
          ),
          const Divider(size: 1),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final operator in operators)
                  _operatorRow(
                    operator.id,
                    accounts.name(operator),
                    selected?.contains(operator.id) ?? false,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// One operator, with the box that says whether they are on the visit.
  Widget _operatorRow(String operatorId, String name, bool checked) {
    return GestureDetector(
      onTap: () => _toggle(operatorId, checked),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(children: [
          Checkbox(
            checked: checked,
            onChanged: (_) => _toggle(operatorId, checked),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: checked ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ]),
      ),
    );
  }

  void _toggle(String operatorId, bool selected) {
    appointmentCommand(widget.appointmentId, (draft) {
      if (selected) {
        draft.operatorsIDs.remove(operatorId);
      } else {
        draft.operatorsIDs.add(operatorId);
      }
    });
    // Re-read the visit rather than trust the frame the tick was drawn in.
    setState(() {});
    widget.onChanged?.call();
  }
}

import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/appointments/follow_up_field.dart';
import 'package:apexo/features/appointments/follow_up_scheduling.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/features/settings/settings_stores.dart'
    show DF, globalSettings;
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// The patient's next follow-up. The visit's operative row and this row edit
/// the same stored field, so it belongs to the patient, not to a visit.
class PatientFollowUpBar extends StatefulWidget {
  const PatientFollowUpBar({super.key, required this.patientID});

  final String patientID;

  @override
  State<PatientFollowUpBar> createState() => _PatientFollowUpBarState();
}

class _PatientFollowUpBarState extends State<PatientFollowUpBar> {
  bool _expanded = false;

  void _onChanged() {
    if (!mounted) return;
    if (patientFollowUpDay(widget.patientID) == null && _expanded) {
      setState(() => _expanded = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MStreamBuilder<Object?>(
      streams: [
        patients.observableMap.stream,
        appointments.observableMap.stream,
        followUpRevision.stream,
        globalSettings.observableMap.stream,
        locale.selected.stream,
      ],
      builder: (context, _) {
        if (!followUpsEnabled) return const SizedBox.shrink();
        final patient = patients.get(widget.patientID);
        // A patient that is not stored yet has nowhere to keep a promise.
        if (patient == null) return const SizedBox.shrink();
        // A follow-up needs a visit behind it, so unseen patients get no row.
        if (patient.doneAppointments.isEmpty) return const SizedBox.shrink();
        final followUp = patient.followUpDay;
        final editable = login.perm(Perm.appointments).some;
        final open = editable && (followUp != null || _expanded);

        return AnimatedSize(
          key: WK.patientFollowUpBar,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.topCenter,
              children: [...previous, if (current != null) current],
            ),
            child: open
                ? FollowUpField(
                    key: const ValueKey('patient-follow-up-open'),
                    patientID: widget.patientID,
                    // No visit to count from here, so the promise runs from today.
                    anchor: DateTime.now(),
                    enabled: editable,
                    // With nothing stored the row came from the folded button, so it
                    // can close without a day.
                    onCollapse: followUp == null
                        ? () => setState(() => _expanded = false)
                        : null,
                    onChanged: _onChanged,
                  )
                : KeyedSubtree(
                    key: const ValueKey('patient-follow-up-folded'),
                    child: _folded(context, followUp, editable),
                  ),
          ),
        );
      },
    );
  }

  /// Folded: what the patient has, or the button that gives them one.
  Widget _folded(BuildContext context, DateTime? followUp, bool editable) {
    final theme = FluentTheme.of(context);
    final dark = theme.brightness == Brightness.dark;
    const accent = kFollowUpAccent;
    final canSet = editable && followUp == null;

    return HoverButton(
      key: WK.patientFollowUpSet,
      onPressed: canSet ? () => setState(() => _expanded = true) : null,
      builder: (context, states) {
        final hovered = states.contains(WidgetState.hovered) && canSet;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          height: 34,
          padding: const EdgeInsetsDirectional.fromSTEB(7, 0, 9, 0),
          decoration: BoxDecoration(
            color: accent.withValues(
              alpha: hovered ? (dark ? 0.16 : 0.10) : 0.05,
            ),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: accent.withValues(alpha: hovered ? 0.45 : 0.22),
            ),
          ),
          child: Row(
            children: [
              const Icon(WindowsIcons.walk_solid, size: 16, color: accent),
              const SizedBox(width: 6),
              Txt(
                txt('nextFollowUp'),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
              const Spacer(),
              Text(
                followUp == null ? txt('notSet') : DF.allNumbers(followUp),
                style: theme.typography.bodyStrong?.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: followUp == null ? theme.inactiveColor : accent,
                ),
              ),
              if (canSet) ...[
                const SizedBox(width: 4),
                Icon(
                  FluentIcons.chevron_down,
                  size: 12,
                  color: accent.withValues(alpha: 0.8),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

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

/// The patient's next follow-up, on the patient's own page — under the band of
/// the visit that may be open beside them.
///
/// A follow-up belongs to the patient, not to the visit that recorded it, but
/// the dentist decides it with the notes in front of them. So the same promise is
/// editable from both places, and both are views of one record: the visit's
/// operative row writes here through `setFollowUp`, and this row writes to the
/// very same field, live.
///
/// It is **folded while there is no promise**: a single tinted button in the
/// band's own colour, so a patient without a follow-up does not carry an empty
/// form. Clicking it opens the row on the intervals, with **no day chosen** — the
/// dentist decides, the row does not decide for them — and saving stores the
/// day and its note. Taking the promise back folds the row again.
class PatientFollowUpBar extends StatefulWidget {
  const PatientFollowUpBar({super.key, required this.patientID});

  final String patientID;

  @override
  State<PatientFollowUpBar> createState() => _PatientFollowUpBarState();
}

class _PatientFollowUpBarState extends State<PatientFollowUpBar> {
  /// Whether the dentist opened an empty row to write a new promise in. The row
  /// is otherwise open exactly while the patient has a follow-up.
  bool _expanded = false;

  /// A draft dropped with nothing behind it folds the row; a saved promise keeps
  /// it open, so the day and its note stay in sight.
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
        // An optional feature: a clinic that does not chase recalls is not
        // shown a row about one.
        if (!followUpsEnabled) return const SizedBox.shrink();
        final patient = patients.get(widget.patientID);
        // A patient that is not stored yet has nowhere to keep a promise.
        if (patient == null) return const SizedBox.shrink();
        // A follow-up is something a dentist says at the end of a visit: a
        // patient who has never been seen has nothing to come back from, so the
        // row is not offered at all.
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
                    // There is no visit to count from here: a promise made on
                    // the patient's page is made from today.
                    anchor: DateTime.now(),
                    enabled: editable,
                    // Nothing stored means the row was opened from the folded
                    // button, and that button is the way back out: a row opened
                    // by mistake must be closable without choosing a day.
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
      // Opening the row is what promises the usual week: the day it suggests is
      // a draft, there to accept, change or abandon — never a booking made
      // behind the dentist's back.
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
              const Icon(WindowsIcons.walk_solid, size: 11, color: accent),
              const SizedBox(width: 6),
              Txt(
                txt('nextFollowUp'),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                  color: accent,
                ),
              ),
              const Spacer(),
              Text(
                followUp == null ? txt('notSet') : DF.allNumbers(followUp),
                style: theme.typography.caption?.copyWith(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                  color: followUp == null ? theme.inactiveColor : accent,
                ),
              ),
              if (canSet) ...[
                const SizedBox(width: 4),
                Icon(
                  FluentIcons.chevron_down,
                  size: 9,
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

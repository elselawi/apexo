import 'dart:async';

import 'package:apexo/common_widgets/contact_buttons.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/appointments/follow_up_scheduling.dart';
import 'package:apexo/features/patients/open_patient_panel.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/features/settings/settings_stores.dart'
    show DF, globalSettings;
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:apexo/utils/flyout_focus_fix.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// The follow-up badge every surface shows: its glyph, its name, and how far off
/// the day is.
class FollowUpBadge extends StatelessWidget {
  const FollowUpBadge({super.key, required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final dark = theme.brightness == Brightness.dark;
    const accent = kFollowUpAccent;
    final overdue = calendarDaysBetween(DateTime.now(), date) < 0;
    final tint = overdue ? Colors.red : accent;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: tint.withValues(alpha: dark ? 0.24 : 0.12),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(WindowsIcons.walk_solid, size: 10, color: tint),
              const SizedBox(width: 4),
              Txt(
                txt('followUp'),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: tint,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 5),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: theme.resources.controlAltFillColorTertiary,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            followUpRelativeLabel(date),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: overdue ? Colors.red : theme.typography.body?.color,
            ),
          ),
        ),
      ],
    );
  }
}

/// The follow-up **card**: the day, whose promise it is, and what the clinic
/// does about it — calls the patient, books the visit that keeps it.
///
/// One card for every surface that offers a follow-up (the scope bar's phone dot
/// and the day's band), so a promise looks and acts the same wherever it is met.
class FollowUpCard extends StatelessWidget {
  const FollowUpCard({
    super.key,
    required this.patient,
    required this.date,
    this.onBook,
    this.onOpenPatient,
  });

  final Patient patient;
  final DateTime date;

  /// Books the visit that keeps the promise; null while the account may not
  /// create visits, and the card then keeps the contact details alone.
  final VoidCallback? onBook;

  /// Opens the patient's record — the name is a link, because the record is the
  /// thing the promise hangs off.
  final VoidCallback? onOpenPatient;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final dark = theme.brightness == Brightness.dark;
    const accent = kFollowUpAccent;
    final hasContact = patient.phone.isNotEmpty || patient.email.isNotEmpty;

    return Container(
      width: 268,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.menuColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: accent.withValues(alpha: dark ? 0.55 : 0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.5 : 0.18),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FollowUpBadge(date: date),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: dark ? 0.22 : 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  WindowsIcons.walk_solid,
                  size: 16,
                  color: accent,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DF.commonDate(date).replaceAll('📅 ', ''),
                      style:
                          theme.typography.bodyStrong?.copyWith(fontSize: 13.5),
                    ),
                    const SizedBox(height: 1),
                    if (onOpenPatient == null)
                      Text(
                        patient.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.typography.caption?.copyWith(
                          fontSize: 10.5,
                          color: theme.inactiveColor,
                        ),
                      )
                    else
                      HyperlinkButton(
                        key: WK.followUpPatientLink,
                        onPressed: onOpenPatient,
                        style: const ButtonStyle(
                          padding: WidgetStatePropertyAll(EdgeInsets.zero),
                        ),
                        child: Text(
                          patient.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.typography.caption?.copyWith(
                            fontSize: 10.5,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          // What the visit is for, in the dentist's own words: the reason the
          // clinic is calling, and the thing to have ready.
          if (patient.followUpNote.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsetsDirectional.fromSTEB(8, 6, 8, 6),
              decoration: BoxDecoration(
                color: theme.resources.controlAltFillColorSecondary,
                borderRadius: BorderRadius.circular(6),
                border: BorderDirectional(
                  start: BorderSide(
                    color: accent.withValues(alpha: 0.55),
                    width: 2,
                  ),
                ),
              ),
              child: Text(
                patient.followUpNote,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.typography.caption?.copyWith(
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
            ),
          ],
          if (hasContact) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (patient.phone.isNotEmpty)
                  PhoneNumberButton(
                    phoneNumbers: patient.phone,
                    onlyIcon: false,
                  ),
                if (patient.phone.isNotEmpty && patient.email.isNotEmpty)
                  const SizedBox(width: 6),
                if (patient.email.isNotEmpty) EmailButton(email: patient.email),
              ],
            ),
          ],
          if (onBook != null) ...[
            const SizedBox(height: 10),
            FilledButton(
              key: WK.bookFollowUp,
              onPressed: onBook,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(WindowsIcons.subscription_add, size: 13),
                    const SizedBox(width: 6),
                    Txt(
                      txt('bookFollowUp'),
                      style: const TextStyle(fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Wraps a control so tapping it opens [FollowUpCard] in a bubble anchored on it.
///
/// [builder] receives the opener instead of the wrapper drawing its own gesture,
/// because the control underneath already has one — a phone dot that hovers, an
/// avatar that can be dragged — and a second recognizer above it would fight it.
class FollowUpCardTarget extends StatefulWidget {
  const FollowUpCardTarget({
    super.key,
    required this.patient,
    required this.date,
    this.onBook,
    this.onOpened,
    required this.builder,
  });

  final Patient patient;
  final DateTime date;
  final VoidCallback? onBook;

  /// Called just before the bubble opens — a caller with a hover card of its own
  /// puts it away first.
  final VoidCallback? onOpened;

  final Widget Function(BuildContext context, VoidCallback open) builder;

  @override
  State<FollowUpCardTarget> createState() => _FollowUpCardTargetState();
}

class _FollowUpCardTargetState extends State<FollowUpCardTarget> {
  final FlyoutController _flyout = FlyoutController();

  @override
  void dispose() {
    _flyout.dispose();
    super.dispose();
  }

  Future<void> _show() async {
    widget.onOpened?.call();
    await flyoutFocusFix(context);
    if (!mounted) return;
    unawaited(_flyout.showFlyout<void>(
      barrierDismissible: true,
      dismissOnPointerMoveAway: false,
      dismissWithEsc: true,
      placementMode: FlyoutPlacementMode.bottomCenter,
      builder: (context) => FollowUpCard(
        patient: widget.patient,
        date: widget.date,
        onBook: widget.onBook == null
            ? null
            : () {
                _flyout.close<void>();
                widget.onBook!();
              },
        onOpenPatient: () {
          _flyout.close<void>();
          unawaited(openPatient(
            patients.get(widget.patient.id) ?? widget.patient,
          ));
        },
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return FlyoutTarget(
      controller: _flyout,
      child: widget.builder(context, _show),
    );
  }
}

/// The follow-up as a **card for a list**.
///
/// The patient's history heads with it, because it is the one thing in that list
/// that has not happened yet. It carries the same two acts as the card on the
/// day's band — book the visit that keeps the promise, or take the promise back
/// — and stays a plain tinted row while nothing is planned: a follow-up nobody
/// set is not an empty form, it is a button.
class FollowUpSummaryCard extends StatelessWidget {
  const FollowUpSummaryCard({
    super.key,
    required this.patientID,
    this.onBook,
  });

  final String patientID;

  /// Supplies the booking action. This widget checks scheduling permission for
  /// booking, setting and clearing; a supplied callback does not grant access.
  final VoidCallback? onBook;

  @override
  Widget build(BuildContext context) {
    final dark = FluentTheme.of(context).brightness == Brightness.dark;
    return MStreamBuilder<Object?>(
      streams: [
        patients.observableMap.stream,
        appointments.observableMap.stream,
        followUpRevision.stream,
        globalSettings.observableMap.stream,
        locale.selected.stream,
      ],
      builder: (context, _) {
        // An optional feature: no promise, no card.
        if (!followUpsEnabled) return const SizedBox.shrink();
        final patient = patients.get(patientID);
        if (patient == null) return const SizedBox.shrink();
        // Nothing done yet, nothing to come back from: the card is the patient's
        // own promise, and a patient who has never been seen has none.
        if (patient.doneAppointments.isEmpty) return const SizedBox.shrink();
        final date = patient.followUpDay;
        return Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(10, 10, 12, 0),
          child: Container(
            key: WK.followUpSummaryCard,
            padding: const EdgeInsetsDirectional.fromSTEB(8, 7, 6, 7),
            decoration: BoxDecoration(
              color: kFollowUpAccent.withValues(alpha: dark ? 0.13 : 0.055),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: kFollowUpAccent.withValues(
                  alpha: date == null ? 0.20 : 0.40,
                ),
              ),
            ),
            child: date == null
                ? _notPlanned(context, patient)
                : _planned(context, patient, date),
          ),
        );
      },
    );
  }

  /// Nothing planned: the row says so, and offers the usual week in one click.
  Widget _notPlanned(BuildContext context, Patient patient) {
    final theme = FluentTheme.of(context);
    const accent = kFollowUpAccent;
    return HoverButton(
      key: WK.followUpSummarySet,
      onPressed: login.perm(Perm.appointments).some
          ? () => setFollowUp(
                patientID,
                kFollowUpPresets.first.from(DateTime.now()),
              )
          : null,
      builder: (context, states) {
        final hovered = states.contains(WidgetState.hovered);
        return Row(
          children: [
            const Icon(WindowsIcons.walk_solid, size: 12, color: accent),
            const SizedBox(width: 7),
            Txt(
              txt('nextFollowUp'),
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
            const Spacer(),
            Text(
              txt('notSelected'),
              style: theme.typography.caption?.copyWith(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: hovered ? accent : theme.inactiveColor,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              WindowsIcons.add,
              size: 10,
              color: accent.withValues(alpha: hovered ? 1 : 0.7),
            ),
          ],
        );
      },
    );
  }

  Widget _planned(BuildContext context, Patient patient, DateTime date) {
    final theme = FluentTheme.of(context);
    final onBook = login.perm(Perm.appointments).some ? this.onBook : null;
    const accent = kFollowUpAccent;
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(WindowsIcons.walk_solid, size: 13, color: accent),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              FollowUpBadge(date: date),
              const SizedBox(height: 3),
              Text(
                DF.commonDate(date).replaceAll('📅 ', ''),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.typography.caption?.copyWith(fontSize: 10),
              ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        if (patient.phone.isNotEmpty)
          PhoneNumberButton(phoneNumbers: patient.phone),
        if (patient.email.isNotEmpty) ...[
          const SizedBox(width: 4),
          EmailButton(email: patient.email),
        ],
        if (onBook != null) ...[
          const SizedBox(width: 4),
          Tooltip(
            message: txt('bookFollowUp'),
            child: IconButton(
              key: WK.bookFollowUp,
              style: darkIconButtonStyle(context),
              onPressed: onBook,
              icon: const Icon(WindowsIcons.subscription_add, size: 15),
            ),
          ),
        ],
        const SizedBox(width: 4),
        Tooltip(
          message: txt('clearFollowUp'),
          child: IconButton(
            key: WK.followUpRemove,
            style: darkIconButtonStyle(context),
            onPressed: login.perm(Perm.appointments).some
                ? () => setFollowUp(patientID, null)
                : null,
            icon: const Icon(WindowsIcons.delete, size: 13),
          ),
        ),
      ],
    );
  }
}

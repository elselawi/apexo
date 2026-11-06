import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/dialogs/close_dialog_button.dart';
import 'package:apexo/common_widgets/dialogs/dialog_styling.dart';
import 'package:apexo/common_widgets/keyboard_aware.dart';
import 'package:apexo/common_widgets/patient_picker.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/appointments/new_appointment_dialog.dart';
import 'package:apexo/features/booking/booking_api.dart';
import 'package:apexo/features/booking/booking_models.dart';
import 'package:apexo/features/booking/booking_session.dart';
import 'package:apexo/features/booking/booking_time.dart';
import 'package:apexo/features/patients/new_patient_dialog.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/features/settings/settings_stores.dart' show DF;
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/utils/constants.dart';
import 'package:fluent_ui/fluent_ui.dart';

bool get canScheduleBooking =>
    login.perm(Perm.patients).some && login.perm(Perm.appointments).some;

/// Schedules one booking request through the *existing* patient and appointment
/// sheets, then acknowledges the inbox only after clinic PocketBase has the
/// appointment.
///
/// Cancelling a sheet creates no record for that sheet; a confirmed new patient
/// remains if the appointment sheet is later cancelled. A Worker failure leaves
/// the saved appointment intact and its inbox link pending.
Future<bool> scheduleBookingRequest(
  BuildContext context,
  BookingRequest request,
) async {
  final generation = booking.requests.generation;
  if (!canScheduleBooking ||
      !booking.requests.beginScheduling(request.requestId)) {
    return false;
  }
  try {
    return await _scheduleBookingRequest(context, request);
  } finally {
    booking.requests.finishScheduling(request.requestId, generation);
  }
}

Future<bool> _scheduleBookingRequest(
  BuildContext context,
  BookingRequest request,
) async {
  final service = booking.service;
  final clinic = booking.clinic();
  if (service == null || clinic == null) return false;

  final generation = booking.requests.generation;
  bool isCurrent() => generation == booking.requests.generation;

  // Never trust an old dialog after another device has handled the request.
  await booking.requests.refresh(status: "pending");
  if (!context.mounted || !isCurrent()) return false;
  BookingRequest? current;
  for (final entry in booking.requests.cache.forFilter("pending")) {
    if (entry.requestId == request.requestId) current = entry;
  }
  if (!booking.requests.connected()) {
    await _message(
        context, txt("bookingRefreshFailed"), txt("bookingRefreshFailedBody"));
    return false;
  }
  if (current == null || !current.isPending || current.isExpired) {
    await _message(
        context, txt("bookingRequestGone"), txt("bookingRequestGoneBody"));
    return false;
  }

  for (final link in booking.requests.pendingLinks()) {
    if (link.requestId != current.requestId) continue;
    final durable = await _confirmedByClinic(link.appointmentId);
    if (!context.mounted || !isCurrent()) return false;
    if (!durable) {
      await _message(context, txt("bookingSaveNotConfirmed"),
          txt("bookingSaveNotConfirmedBody"));
      return false;
    }
    return _acknowledge(context, current, link.appointmentId, generation);
  }

  // 2. Suggest the first future intersection of the stored candidates, the
  //    requested window and the *current* hours.
  BookingMoment? suggestion;
  List<String> closedDates = const [];
  try {
    final publicConfig = await service.api.publicClinic(clinic.handle);
    final hours = BookingWeeklyHours.fromJson(publicConfig["hours"]) ??
        BookingWeeklyHours.empty();
    closedDates = (publicConfig["closedDates"] as List? ?? const [])
        .map((value) => value.toString())
        .toList();
    if (publicConfig["timeZone"] == current.timeZone) {
      suggestion = suggestedBookingMoment(
        current,
        hours,
        closedDates: closedDates,
      );
    }
  } catch (_) {
    suggestion = null;
  }
  if (!context.mounted || !isCurrent()) return false;

  // 3. Whose visit is it? Existing patient or an explicitly created one.
  final patientId = await chooseBookingPatient(context, current, suggestion);
  if (patientId == null || !context.mounted || !isCurrent()) return false;

  // 4. The normal appointment sheet, seeded with the exact instant.
  final appointment = await addAppointment(
    context,
    patientID: patientId,
    initialMoment:
        suggestion?.needsManualConfirmation == true ? null : suggestion?.local,
  );
  if (appointment == null || !isCurrent()) return false;
  booking.requests
      .rememberPendingLink(current, appointment.id, confirmed: false);

  // A failed read-back must not allow the same session to create a second visit.
  final durable = await _confirmedByClinic(appointment.id, patientId);
  if (!context.mounted || !isCurrent()) return false;
  if (!durable) {
    await _message(context, txt("bookingSaveNotConfirmed"),
        txt("bookingSaveNotConfirmedBody"));
    return false;
  }

  return _acknowledge(context, current, appointment.id, generation);
}

Future<bool> _acknowledge(BuildContext context, BookingRequest current,
    String appointmentId, int generation) async {
  bool isCurrent() => generation == booking.requests.generation;
  try {
    await booking.requests.markHandled(current, appointmentId);
    if (!isCurrent()) return false;
    if (!context.mounted) return true;
    await _message(
        context, txt("bookingAppointmentSaved"), txt("bookingHandledBody"));
    return true;
  } on BookingApiException catch (error) {
    if (!isCurrent()) return false;
    if (error.conflict || error.notFound) {
      booking.requests.forgetPendingLink(current.requestId);
      // A colleague decided first: show both sides, never duplicate or delete.
      await booking.requests.refresh();
      if (!context.mounted) return false;
      await _message(context, txt("bookingStateConflict"),
          txt("bookingStateConflictBody"));
      return false;
    }
    booking.requests.rememberPendingLink(current, appointmentId);
    if (!context.mounted) return true;
    await _message(context, txt("bookingAppointmentSaved"),
        txt("bookingInboxUpdatePending"));
    return true;
  } catch (_) {
    if (!isCurrent()) return false;
    booking.requests.rememberPendingLink(current, appointmentId);
    if (!context.mounted) return true;
    await _message(context, txt("bookingAppointmentSaved"),
        txt("bookingInboxUpdatePending"));
    return true;
  }
}

Future<bool> _confirmedByClinic(String appointmentId,
    [String? patientId]) async {
  final pb = login.pb;
  if (pb == null) return false;
  try {
    final results = await appointments.synchronize();
    if (!identical(pb, login.pb) ||
        results.any((result) => result.exception != null)) {
      return false;
    }
    final record =
        await pb.collection(dataCollectionName).getOne(appointmentId);
    if ((record.getStringValue("store")) != "appointments") return false;
    final data = record.data["data"];
    if (data is! Map) return false;
    if (data["archived"] == true) return false;
    return patientId == null
        ? (data["patientID"] is String &&
            (data["patientID"] as String).isNotEmpty)
        : data["patientID"] == patientId;
  } catch (_) {
    return false;
  }
}

/// The patient step of [scheduleBookingRequest], exposed so the dialog itself
/// can be exercised without a live Worker.
@visibleForTesting
Future<String?> chooseBookingPatient(
  BuildContext context,
  BookingRequest request, [
  BookingMoment? suggestion,
]) {
  return showDialog<String>(
    context: context,
    barrierDismissible: true,
    dismissWithEsc: true,
    builder: (_) =>
        _PatientChoiceDialog(request: request, suggestion: suggestion),
  );
}

/// Whose visit is it?
///
/// Existing patients whose number matches the request are *offered*, never
/// preselected: the receptionist still taps the person they recognise.
class _PatientChoiceDialog extends StatefulWidget {
  const _PatientChoiceDialog({required this.request, required this.suggestion});

  final BookingRequest request;
  final BookingMoment? suggestion;

  @override
  State<_PatientChoiceDialog> createState() => _PatientChoiceDialogState();
}

class _PatientChoiceDialogState extends State<_PatientChoiceDialog> {
  String? _selected;
  late final List<Patient> _matches = _patientsWithNumber(widget.request.phone);

  /// Patients whose stored number ends where the request's number ends, so a
  /// national-only entry still finds an international request. Exact matches
  /// come first; the list stays short and is only a hint.
  static List<Patient> _patientsWithNumber(String phone) {
    final needle = _digitsOnly(phone);
    if (needle.length < 6) return const [];
    final tail =
        needle.substring(needle.length - 9 < 0 ? 0 : needle.length - 9);
    final exact = <Patient>[];
    final fuzzy = <Patient>[];
    for (final patient in patients.present.values) {
      final numbers = patient.phone.map((entry) => _digitsOnly(entry.e164));
      if (numbers.contains(needle)) {
        exact.add(patient);
      } else if (numbers.any((number) => number.endsWith(tail))) {
        fuzzy.add(patient);
      }
      if (exact.length + fuzzy.length >= 5) break;
    }
    return [...exact, ...fuzzy].take(3).toList();
  }

  static String _digitsOnly(String value) =>
      value.replaceAll(RegExp(r"[^0-9]"), "");

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final suggestion = widget.suggestion;
    final local = suggestion?.local;
    final showSuggestion = suggestion != null &&
        !suggestion.needsManualConfirmation &&
        local != null;
    final clinicWall = showSuggestion
        ? "${bookingClinicDate(local.millisecondsSinceEpoch, widget.request.timeZone)} "
            "${bookingClinicTimeLabel(local.millisecondsSinceEpoch, widget.request.timeZone)}"
        : "";
    final request = widget.request;

    void pick(String? id) => setState(() => _selected = id);

    return KeyboardAwareView(
      child: ContentDialog(
        constraints: const BoxConstraints(maxWidth: 430),
        style: dialogStyling(context, false, true),
        title: Row(children: [
          const Icon(WindowsIcons.contact),
          const SizedBox(width: 5),
          Expanded(child: Txt(txt("bookingSchedulePatientTitle"))),
        ]),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 10,
            children: [
              Txt(txt("bookingScheduleHint")),
              if (showSuggestion) ...[
                Text(
                  "${txt("bookingSuggestedTime")}: $clinicWall (${request.timeZone})",
                  style: theme.typography.bodyStrong,
                ),
                Text("${txt("bookingDeviceTime")}: ${DF.full(local)}",
                    style: theme.typography.caption),
              ] else
                Text(txt("bookingManualTimeRequired"),
                    style: const TextStyle(color: Colors.warningPrimaryColor)),
              Text("${request.name} · ${request.phone}",
                  style: theme.typography.caption),
              if (_matches.isNotEmpty) ...[
                Text(txt("bookingSuggestedPatient"),
                    style: theme.typography.bodyStrong),
                for (final patient in _matches)
                  Button(
                    style: ButtonStyle(
                      padding: const WidgetStatePropertyAll(
                          EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                      backgroundColor: WidgetStateProperty.resolveWith(
                          (states) => _selected == patient.id
                              ? theme.accentColor.withValues(alpha: 0.12)
                              : (states.contains(WidgetState.hovered)
                                  ? theme.resources.subtleFillColorSecondary
                                  : Colors.transparent)),
                      shape: WidgetStatePropertyAll(RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      )),
                    ),
                    onPressed: () => pick(patient.id),
                    child: Row(children: [
                      Icon(
                        _selected == patient.id
                            ? FluentIcons.check_mark
                            : WindowsIcons.contact,
                        size: 14,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(patient.title,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            if (patient.phonesString.isNotEmpty)
                              Text(patient.phonesString,
                                  style: theme.typography.caption),
                          ],
                        ),
                      ),
                    ]),
                  ),
              ],
              PatientPicker(
                value: _selected,
                tapOpensRecord: false,
                onChanged: pick,
              ),
            ],
          ),
        ),
        actions: [
          Button(
            child: ButtonContent(FluentIcons.add, txt("newPatient")),
            onPressed: () async {
              final patient = await addPatient(
                context,
                initialName: request.name,
                initialPhone: request.phone,
              );
              if (patient != null && context.mounted) {
                Navigator.of(context).pop(patient.id);
              }
            },
          ),
          FilledButton(
            onPressed: _selected == null
                ? null
                : () => Navigator.of(context).pop(_selected),
            child: ButtonContent(FluentIcons.accept, txt("bookingContinue")),
          ),
          const CloseButtonInDialog(),
        ],
      ),
    );
  }
}

Future<void> _message(
  BuildContext context,
  String title,
  String body,
) async {
  await showDialog(
    context: context,
    barrierDismissible: true,
    dismissWithEsc: true,
    builder: (dialogContext) => ContentDialog(
      constraints: const BoxConstraints(maxWidth: 420),
      style: dialogStyling(dialogContext, false, true),
      title: Text(title),
      content: Text(body),
      actions: const [CloseButtonInDialog()],
    ),
  );
}

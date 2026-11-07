import 'package:apexo/core/reactive/observable.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:apexo/ui/workspace/panels_manager.dart';
import 'package:apexo/ui/workspace/record_session.dart';
import 'package:fluent_ui/fluent_ui.dart' show ChangeNotifier, Color;

/// Whether the clinic uses follow-ups at all. Every follow-up surface and rule
/// checks it, so a clinic that does not chase recalls never sees a promise.
bool get followUpsEnabled => globalSettings.followUpsEnabled;

/// Deliberately not the visit purple, so a dot or chip never reads as a visit.
const Color kFollowUpAccent = Color(0xFF0E9AA7);

/// Bumped on every follow-up write, so the visit's record and the patient's band,
/// either of which may be open, redraw from the store.
final followUpRevision = ObservableState(0);

/// Truncates to the day: the clinic records "come back in two weeks" in the
/// chair, and the hour is only settled when someone books the visit.
DateTime dayOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool sameCalendarDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Whole days from [from]'s day to [to]'s day, counted on the calendar rather
/// than in 24-hour spans — so a daylight-saving change cannot shift it by one.
int calendarDaysBetween(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day)
        .difference(DateTime.utc(from.year, from.month, from.day))
        .inDays;

bool isFollowUpOverdue(DateTime day, {DateTime? asOf}) =>
    calendarDaysBetween(asOf ?? DateTime.now(), day) < 0;

/// The day to offer for the visit: the promised day while it is ahead, else
/// today, since a visit booked into the past keeps nothing.
DateTime followUpBookingDay(DateTime followUpDay, {DateTime? asOf}) =>
    isFollowUpOverdue(followUpDay, asOf: asOf)
        ? dayOnly(asOf ?? DateTime.now())
        : dayOnly(followUpDay);

/// The label shared by the chip, hover card and band, so a promise never reads two ways.
String followUpRelativeLabel(DateTime day, {DateTime? asOf}) {
  final days = calendarDaysBetween(asOf ?? DateTime.now(), day);
  if (days == 0) return txt('today');
  if (days == 1) return txt('tomorrow');
  if (days < 0) return txt('overdue');
  return txt('daysAway').replaceAll('{count}', '$days');
}

/// The unit a preset counts in.
enum FollowUpUnit { day, week, month }

/// One of the preset buttons beside the date. Months are calendar months, so
/// "3m" from 20 January is 20 April, clamped to the target month's last day.
class FollowUpPreset {
  const FollowUpPreset(this.value, this.unit);

  final int value;
  final FollowUpUnit unit;

  DateTime from(DateTime day) {
    switch (unit) {
      case FollowUpUnit.day:
        return DateTime(day.year, day.month, day.day + value);
      case FollowUpUnit.week:
        return DateTime(day.year, day.month, day.day + value * 7);
      case FollowUpUnit.month:
        final month = DateTime(day.year, day.month + value);
        final lastDay = DateTime(month.year, month.month + 1, 0).day;
        return DateTime(
            month.year, month.month, day.day > lastDay ? lastDay : day.day);
    }
  }

  /// The short form the button shows — "1w" in English, "١أ" in Arabic.
  String get label => '$value${txt(switch (unit) {
        FollowUpUnit.day => 'timelineDayUnit',
        FollowUpUnit.week => 'timelineWeekUnit',
        FollowUpUnit.month => 'timelineMonthUnit',
      })}';

  /// The interval in words, for a row wide enough to afford it.
  String get longLabel {
    final key = switch (unit) {
      FollowUpUnit.day => 'followUpPresetDays',
      FollowUpUnit.week =>
        value == 1 ? 'followUpPresetWeek' : 'followUpPresetWeeks',
      FollowUpUnit.month => 'followUpPresetMonths',
    };
    return txt(key).replaceAll('{count}', '$value');
  }

  /// Whether [day] is exactly what this preset makes of [anchor].
  bool fits(DateTime anchor, DateTime day) =>
      sameCalendarDay(from(anchor), day);
}

/// The intervals a practice actually uses, shortest first.
const List<FollowUpPreset> kFollowUpPresets = [
  FollowUpPreset(1, FollowUpUnit.week),
  FollowUpPreset(10, FollowUpUnit.day),
  FollowUpPreset(2, FollowUpUnit.week),
  FollowUpPreset(3, FollowUpUnit.week),
  FollowUpPreset(4, FollowUpUnit.week),
  FollowUpPreset(2, FollowUpUnit.month),
  FollowUpPreset(3, FollowUpUnit.month),
];

/// The patient's follow-up as it reads now, or null when none is planned.
DateTime? patientFollowUpDay(String patientID) =>
    patients.get(patientID)?.followUpDay;

/// Writes the patient's follow-up (null takes it back); a null [note] keeps the
/// stored one. Also writes an open patient panel's draft and marks those fields
/// saved there, or that panel's next Save would undo the write.
void setFollowUp(String patientID, DateTime? date, {String? note}) {
  if (!login.perm(Perm.appointments).some) return;
  final stored = patients.get(patientID);
  // A patient that is not stored yet has no record to carry a promise.
  if (stored == null) return;
  final day = date == null ? null : dayOnly(date);
  final minutes =
      day == null ? null : (day.millisecondsSinceEpoch / 60000).round();
  final text = minutes == null ? '' : (note ?? stored.followUpNote).trim();

  final json = stored.toJson();
  if (minutes == null) {
    json.remove('followUp');
    json.remove('followUpNote');
  } else {
    json['followUp'] = minutes;
    if (text.isEmpty) {
      json.remove('followUpNote');
    } else {
      json['followUpNote'] = text;
    }
  }
  patients.set(patients.modeling(json));

  for (final panel in PanelsManager.active()) {
    if (panel.singularName != 'patient' || panel.itemId != patientID) continue;
    final draft = Map<String, dynamic>.from(panel.draftJson);
    // An explicit null clears it (`Patient.fromJson` reads the key's presence).
    draft['followUp'] = minutes;
    draft['followUpNote'] = text.isEmpty ? null : text;
    panel.adoptDraft(draft);
    if (panel is DraftAcknowledgements) {
      // `Panel` and the acknowledgement interface are unrelated types, so the cast
      // is the contract; acknowledging one field alone would leave the draft dirty.
      (panel as DraftAcknowledgements)
          .markFieldsSaved(const ['followUp', 'followUpNote']);
    }
  }

  followUpRevision(followUpRevision() + 1);
}

/// The recall rule: a visit on or after the promised day keeps the promise and
/// takes it back; a visit before it leaves the promise standing.
void applyFollowUpsForNewVisit(String visitID) {
  if (!followUpsEnabled) return;
  final created = appointments.get(visitID);
  if (created == null || created.archived == true) return;
  final patientID = created.patientID ?? '';
  if (patientID.isEmpty) return;
  final followUp = patients.get(patientID)?.followUpDay;
  if (followUp == null) return;
  if (dayOnly(created.date).isBefore(followUp)) return;
  setFollowUp(patientID, null);
}

/// A follow-up that falls on a day and has no visit of its own yet.
class FollowUpDue {
  const FollowUpDue({required this.patient, required this.date});

  final Patient patient;

  /// The day the patient was asked to come back.
  final DateTime date;
}

/// A follow-up edit staged alongside a visit's form. The values stay
/// patient-owned; [onChanged] lets the visit session mark itself dirty.
class FollowUpDraft extends ChangeNotifier {
  FollowUpDraft({this.onChanged});

  final void Function()? onChanged;

  String? patientID;
  DateTime? day;
  String note = '';
  bool isDirty = false;

  void stage({
    required String patientID,
    required DateTime? day,
    required String note,
  }) {
    final normalizedDay = day == null ? null : dayOnly(day);
    if (isDirty &&
        this.patientID == patientID &&
        this.day == normalizedDay &&
        this.note == note) {
      return;
    }
    this.patientID = patientID;
    this.day = normalizedDay;
    this.note = note;
    isDirty = true;
    onChanged?.call();
    notifyListeners();
  }

  /// Drops the shared values, optionally only for the specified patient.
  void clear({String? forPatientID}) {
    if (forPatientID != null && patientID != forPatientID) return;
    if (!isDirty && patientID == null && day == null && note.isEmpty) return;
    patientID = null;
    day = null;
    note = '';
    isDirty = false;
    onChanged?.call();
    notifyListeners();
  }
}

/// Every follow-up due on [day], with overdue ones folded in from today onward.
/// A patient who already has a visit that day is left out to avoid a duplicate.
List<FollowUpDue> followUpsOn(DateTime day) {
  if (!followUpsEnabled) return const <FollowUpDue>[];
  final today = dayOnly(DateTime.now());
  final includeOverdue = !dayOnly(day).isBefore(today);
  final bookedPatients = <String>{};
  for (final visit in appointments.observableMap.docs.values) {
    if (visit.archived == true) continue;
    if (!sameCalendarDay(visit.date, day)) continue;
    final patientID = visit.patientID ?? '';
    if (patientID.isNotEmpty) bookedPatients.add(patientID);
  }

  final due = <FollowUpDue>[];
  for (final patient in patients.observableMap.docs.values) {
    if (patient.archived == true || patient.locked) continue;
    final followUp = patient.followUpDay;
    if (followUp == null ||
        (!sameCalendarDay(followUp, day) &&
            !(includeOverdue && followUp.isBefore(today)))) {
      continue;
    }
    if (bookedPatients.contains(patient.id)) continue;
    due.add(FollowUpDue(patient: patient, date: followUp));
  }
  return due..sort((a, b) => a.patient.title.compareTo(b.patient.title));
}

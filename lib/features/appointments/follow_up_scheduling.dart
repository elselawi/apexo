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

/// Whether the clinic uses follow-ups at all — settings › optional features.
///
/// The whole feature hangs off this: no field, no dot, no band, no rule that
/// silently rewrites a patient. A clinic that does not chase recalls should never
/// see a promise it never made.
bool get followUpsEnabled => globalSettings.followUpsEnabled;

/// The colour a follow-up is known by.
///
/// Deliberately not the visit's purple: a follow-up is a *future* promise, and a
/// dot, a chip or a band drawn in it must say "this is not a visit" before it
/// says anything else. Teal sits beside the visit colours without racing them.
const Color kFollowUpAccent = Color(0xFF0E9AA7);

/// Bumped whenever a follow-up is written, so the places that show the same one
/// — the visit's operative record and the patient's own band — never disagree.
///
/// The follow-up lives on the **patient**, and either surface may edit it while
/// the other is on screen; each listens here and redraws from the store.
final followUpRevision = ObservableState(0);

/// A follow-up is a **day**, not an hour.
///
/// The clinic writes it down while the patient is still in the chair ("come
/// back in two weeks"); the hour is settled when someone calls and books the
/// visit. Keeping a time would store a booking nobody made.
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

/// The day a follow-up's visit is offered on: the promise's own day while it is
/// still ahead, and today once it is late — a visit booked into the past keeps
/// nothing, and the promise it was booked for would stay open.
DateTime followUpBookingDay(DateTime followUpDay, {DateTime? asOf}) =>
    isFollowUpOverdue(followUpDay, asOf: asOf)
        ? dayOnly(asOf ?? DateTime.now())
        : dayOnly(followUpDay);

/// "Today", "Tomorrow", "in 12 days", "Overdue" — the words a follow-up chip,
/// hover card and band all say, so one promise never reads two ways.
String followUpRelativeLabel(DateTime day, {DateTime? asOf}) {
  final days = calendarDaysBetween(asOf ?? DateTime.now(), day);
  if (days == 0) return txt('today');
  if (days == 1) return txt('tomorrow');
  if (days < 0) return txt('overdue');
  return txt('daysAway').replaceAll('{count}', '$days');
}

/// The unit a preset counts in.
enum FollowUpUnit { day, week, month }

/// One of the buttons beside the follow-up date: "1w", "10d", "3m".
///
/// A day preset adds days, a week preset adds weeks, and a month preset adds a
/// *calendar* month — "3m" from 20 January is 20 April, not "90 days later".
/// If that day does not exist in the target month, its last day is used.
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

  /// The same interval as words — "10 days", "2 weeks" — for a row wide enough
  /// to afford it. The short form is a compromise, not a preference: a dentist
  /// new to the app should not have to decode "3m".
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

/// The intervals a practice actually uses, shortest first — the six buttons the
/// follow-up row draws beside the date.
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

/// Writes the follow-up of [patientID] — or takes the promise back when [date]
/// is null. Requires at least limited appointment permission, like its controls.
///
/// A follow-up is a day **and** the note that says what it is for, so both are
/// written here: [note] is the whole note (null keeps the one the promise
/// already carries), and taking the day back takes the note with it.
///
/// The follow-up lives on the patient, and the two places that edit it (a
/// visit's operative record and the patient's own band) must agree the moment
/// either is touched. So the write reaches **both** records that can hold it:
///
/// * the **store**, which is what the calendar, the scope bar and the day's band
///   read; and
/// * the patient panel's **draft**, when it is open — that draft is what the
///   panel's Save writes, and a value written only to the store would be undone
///   by the next patient Save. The field is acknowledged as saved there
///   (`markFieldsSaved`), so the panel is not made dirty by a write it did not
///   perform, and the follow-up survives a Cancel exactly as it survives the
///   calendar's own toggles.
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
      // `Panel` and the acknowledgements interface are unrelated types, so the
      // check does not promote: the cast is the contract (`RowPanel` implements
      // it, and a panel that owns no record simply is not one).
      // Both halves of the promise: a note acknowledged on its own would leave
      // the draft dirty over a write the user did not make.
      (panel as DraftAcknowledgements)
          .markFieldsSaved(const ['followUp', 'followUpNote']);
    }
  }

  followUpRevision(followUpRevision() + 1);
}

/// The recall rule, applied when [visitID] has just been stored.
///
/// A follow-up is a promise that the patient comes back on a day. A visit made
/// on that day — or after it — keeps that promise: the promise is taken back so
/// the patient is not called again. A visit made *before* it does not: the
/// patient has not reached that day yet, and the promise still stands.
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

/// A follow-up edit staged alongside another record's form.
///
/// The values remain patient-owned; [onChanged] lets the owning visit session
/// include this draft in its dirty state and save action.
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

/// Every follow-up due on [day], plus overdue follow-ups on today or a future
/// day, that still needs a visit, one per patient.
///
/// A patient who already has a visit that day is left out: the promise is being
/// kept, and offering to book a second visit for them would book a duplicate.
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

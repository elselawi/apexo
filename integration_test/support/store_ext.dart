import 'package:apexo/core/model.dart';
import 'package:apexo/core/store.dart';
import 'package:apexo/features/appointments/appointment_model.dart';

/// The little bit of store vocabulary the e2e suite used that this app's
/// [Store] does not spell the same way.
///
/// The suite was written over a store whose rows could be counted and dropped
/// with `total()` and `purge(id)`. Neither exists here: this store counts with
/// `list()` and has no delete at all — `delete(id)` archives (`"the concept of
/// deletion is not supported here"`, `core/store.dart`). So both live here,
/// where the difference is stated once instead of in fifteen group files.
extension E2EStores<G extends Model> on Store<G> {
  /// How many rows the store holds, archived ones included — this store has no
  /// `list()`, it has [docs].
  Future<int> total() async => docs.length;

  /// Drops [id] from the store's view without queueing a remote delete.
  ///
  /// This is as close as this branch gets to the suite's `purge`: the row is
  /// gone from the store, and nothing is sent, so a later pull can bring it
  /// back — which is what the tests that used it were pinning down.
  void purge(String id) => observableMap.remove(id);
}

/// A date in the form this app's stores read and write: **minutes since the
/// epoch**.
///
/// That is the app's own convention, not a choice made here —
/// `appointment_model.dart` writes `json['date'] = (date.millisecondsSinceEpoch
/// / 60000).round()` and reads it back with `* 60000`, and `demo_generator.dart`
/// seeds the same way. A seeded row written in any other unit comes back as a
/// 1970 appointment.
int dateToWire(DateTime date) => (date.millisecondsSinceEpoch / 60000).round();

/// The appointments on one day — a question this store answers for "today" and
/// "this month" (`todayAppointments`, `thisMonthAppointments`) but not for an
/// arbitrary day, which is what a test that books a visit needs.
extension E2EAppointmentDays on Store<Appointment> {
  List<Appointment> forDay(DateTime day) => docs.values
      .where((appointment) =>
          appointment.date.year == day.year &&
          appointment.date.month == day.month &&
          appointment.date.day == day.day)
      .toList();
}

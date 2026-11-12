import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/features/patients/patients_store.dart';

class _LabworksController {
  _LabworksController() {
    appointments.observableMap.observe((_) {
      _nullifyCaches();
    });
    // Not-delivered lists derive from patients, so archiving a patient must
    // invalidate them.
    patients.observableMap.observe((_) {
      _nullifyCaches();
    });
  }
  List<Appointment>? _appointmentsWithLabworksCached;
  List<Appointment>? _dueCached;
  List<Appointment>? _notDeliveredCached;
  List<Patient>? _notDeliveredPatientsCached;

  void _nullifyCaches() {
    _appointmentsWithLabworksCached = null;
    _dueCached = null;
    _notDeliveredCached = null;
    _notDeliveredPatientsCached = null;
  }

  List<Appointment> get appointmentsWithLabworks =>
      _appointmentsWithLabworksCached ??= appointments.present.values
          .where((appointment) => appointment.hasLabwork)
          .toList();

  /// Labwork handed to a lab and not received back yet.
  bool _awaitingLabwork(Appointment appointment) =>
      appointment.hasLabwork && !appointment.labworkReceived;

  List<Appointment> get due => _dueCached ??=
      appointments.present.values.where(_awaitingLabwork).toList();

  /// [due] straight from the store: its cache is dropped asynchronously, which
  /// is a frame too late for the nav badge.
  int get dueCount =>
      appointments.present.values.where(_awaitingLabwork).length;
  List<Patient> get notDeliveredPatients =>
      _notDeliveredPatientsCached ??= patients.present.values
          .where((p) =>
              p.allAppointments.isNotEmpty &&
              p.allAppointments.last.hasLabwork &&
              p.allAppointments.last.labworkReceived)
          .toList();

  List<Appointment> get notDelivered => _notDeliveredCached ??=
      notDeliveredPatients.map((p) => p.allAppointments.last).toList();
}

final labworks = _LabworksController();

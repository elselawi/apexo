import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/features/patients/patients_store.dart';

class _LabworksController {
  List<Appointment>? _appointmentsWithLabworksCached;
  List<Appointment>? _dueCached;
  List<Appointment>? _notDeliveredCached;
  List<Patient>? _notDeliveredPatientsCached;

  _nullifyCaches() {
    _appointmentsWithLabworksCached = null;
    _dueCached = null;
    _notDeliveredCached = null;
    _notDeliveredPatientsCached = null;
  }

  _LabworksController() {
    appointments.observableMap.observe((_) {
      _nullifyCaches();
    });
  }

  List<Appointment> get appointmentsWithLabworks =>
      _appointmentsWithLabworksCached ??= appointments.present.values
          .where((appointment) => appointment.hasLabwork)
          .toList();
  List<Appointment> get due => _dueCached ??= appointments.present.values
      .where((appointment) =>
          appointment.hasLabwork && !appointment.labworkReceived)
      .toList();
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

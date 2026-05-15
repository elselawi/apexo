import 'package:apexo/core/observable.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/patients/patient_model.dart';

class _DashboardController {
  List<Appointment> get thisMonthAppointments =>
      appointments.thisMonthAppointments;
  List<Appointment> get todayAppointments => appointments.todayAppointments;

  final currentOpenTab = ObservableState(0);

  double get paymentsToday {
    double res = 0;
    for (var appointment in appointments.todayAppointments) {
      res += appointment.paid;
    }
    return res;
  }

  List<Patient> get newPatientsToday {
    return appointments.todayAppointments
        .where((x) => x.firstAppointmentForThisPatient && x.patient != null)
        .map((x) => x.patient!)
        .toList();
  }
}

final dashboardCtrl = _DashboardController();

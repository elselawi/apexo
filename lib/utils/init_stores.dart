import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/expenses/expenses_store.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/features/doctors/doctors_store.dart';

initializeStores() {
  doctors.init();
  patients.init();
  appointments.init();
  globalSettings.init();
  expenses.init();
}

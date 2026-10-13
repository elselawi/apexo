import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/expenses/expenses_store.dart';
import 'package:apexo/features/notes/notes_store.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/features/settings/settings_stores.dart';

void initializeStores() {
  globalSettings.init();
  patients.init();
  appointments.init();

  expenses.init();
  notes.init();
}

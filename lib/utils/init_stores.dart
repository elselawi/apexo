import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/expenses/expenses_store.dart';
import 'package:apexo/features/notes/notes_store.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/archived.dart';

initializeStores() {
  globalSettings.init();
  patients.init();
  appointments.init();

  appointments.observableMap.observe((events) {
    for (var event in events) {
      if (event.id == "__removed_all__" || event.id == "__ignore_view__") {
        for (var p in patients.docs.values) {
          p.nullifyLabels();
        }
        break;
      }
      final doc = event.document;
      if (doc is Appointment && doc.patientID != null) {
        patients.docs[doc.patientID!]?.nullifyLabels();
      }
    }
  });

  showArchived.observe((_) {
    for (var p in patients.docs.values) {
      p.nullifyLabels();
    }
  });

  expenses.init();
  notes.init();
}

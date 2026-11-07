import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/services/localization/locale.dart';

/// One line naming the patient in a window: name, age, phone. Lives here so the
/// window enum need not import the model.
String patientOwnerLine(Patient patient) {
  final phone = patient.phone.isEmpty ? '' : patient.phone.first.e164;
  return [
    patient.title,
    if (patient.age > 0)
      '${patient.age} ${txt(patient.age == 1 ? 'year' : 'years')}',
    if (phone.isNotEmpty) phone,
  ].join(' · ');
}

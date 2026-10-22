import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/services/localization/locale.dart';

/// Whose patient a window belongs to: the name, the age and the phone — enough
/// to tell two people with the same name apart without opening either.
///
/// Lives here rather than beside the window enum: it is the one line of view
/// text about a [Patient], and the enum must not depend on the model to draw it
/// — a model that the windows cannot name is a model the enum does not import.
String patientOwnerLine(Patient patient) {
  final phone = patient.phone.isEmpty ? '' : patient.phone.first.e164;
  return [
    patient.title,
    if (patient.age > 0)
      '${patient.age} ${txt(patient.age == 1 ? 'year' : 'years')}',
    if (phone.isNotEmpty) phone,
  ].join(' · ');
}

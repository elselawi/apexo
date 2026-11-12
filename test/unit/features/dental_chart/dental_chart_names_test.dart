import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/open_appointment.dart';
import 'package:apexo/features/patients/patient_dental_chart.dart';
import 'package:apexo/shared/dental_chart/dental_chart_window_spec.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/features/patients/patient_windows.dart';
import 'package:apexo/services/localization/en.dart';
import 'package:flutter_test/flutter_test.dart';

// One chart, two labels: a record's chart and a visit's treatments chart; docks must match.
void main() {
  final patient = Patient.fromJson({'id': 'chart-name-patient', 'title': 'P'});
  final appointment =
      Appointment.fromJson({'id': 'chart-name-visit', 'patient': patient.id});

  test('a record\'s chart and a visit\'s chart are named differently', () {
    final record = dentalChartWindow(patientDentalChart(patient));
    final visit = dentalChartWindow(appointmentDentalChart(appointment));

    expect(record.title, kDentalChartTitleKey);
    expect(visit.title, kTreatmentsTitleKey);
    expect(record.title, isNot(visit.title));
  });

  test('the patient dock keeps the chart name while the window says what it is',
      () {
    final patientChart = patientWindows()
        .firstWhere((window) => window.id == kDentalChartWindowId);
    final visitChart = appointmentWindows(appointment)
        .firstWhere((window) => window.id == kDentalChartWindowId);
    final recordWindow = dentalChartWindow(patientDentalChart(patient));

    expect(patientChart.titleKey, kDentalChartDockTitleKey);
    expect(recordWindow.dockTitle, kDentalChartDockTitleKey);
    expect(recordWindow.title, kDentalChartTitleKey);
    expect(visitChart.titleKey, kTreatmentsTitleKey);
  });

  test('all names are in the dictionary', () {
    final dictionary = En().dictionary;
    expect(dictionary, contains(kDentalChartTitleKey));
    expect(dictionary, contains(kDentalChartDockTitleKey));
    expect(dictionary, contains(kTreatmentsTitleKey));
    expect(dictionary[kDentalChartTitleKey], 'Initial Exam Chart');
    expect(dictionary[kDentalChartDockTitleKey], 'Dental Chart');
    expect(dictionary[kTreatmentsTitleKey], 'Appointment Operative Details');
  });
}

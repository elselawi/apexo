import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/open_appointment_panel.dart';
import 'package:apexo/features/appointments/appointment_dental_chart.dart';
import 'package:apexo/features/patients/patient_dental_chart.dart';
import 'package:apexo/shared/dental_chart/dental_chart_window_spec.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/features/patients/patient_windows.dart';
import 'package:apexo/services/localization/en.dart';
import 'package:flutter_test/flutter_test.dart';

/// One chart, two names: what it writes differs by the record hosting it, so the
/// window must say which one you are looking at — and the button that opens it
/// must say the same thing as the window it opens.
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

  test('each panel\'s dock names the chart as the chart itself does', () {
    // The dock button and the window it opens are two views of one editor: a
    // mismatch would label the same window twice.
    final patientChart = patientWindows()
        .firstWhere((window) => window.id == kDentalChartWindowId);
    final visitChart = appointmentWindows(appointment)
        .firstWhere((window) => window.id == kDentalChartWindowId);

    expect(patientChart.titleKey, kDentalChartTitleKey);
    expect(visitChart.titleKey, kTreatmentsTitleKey);
  });

  test('both names are in the dictionary', () {
    final dictionary = En().dictionary;
    expect(dictionary, contains(kDentalChartTitleKey));
    expect(dictionary, contains(kTreatmentsTitleKey));
  });
}

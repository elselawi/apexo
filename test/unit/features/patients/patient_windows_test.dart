import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/features/patients/patient_owner_line.dart';
import 'package:apexo/features/patients/patient_windows.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a patient's windows ask of the grid: the visit list sizes itself to the
/// visits it has, so a short history is a short window and a long one is not
/// squeezed into half a screen.
void main() {
  test('a short history asks for a short window', () {
    expect(appointmentsListHeight(1), lessThan(appointmentsListHeight(3)));
  });

  test('a long history stops at the window\'s ceiling', () {
    expect(appointmentsListHeight(50), appointmentsListMaxHeight);
  });

  test('the window never asks for less than its floor', () {
    expect(appointmentsListHeight(0), appointmentsListMinHeight);
    expect(
      appointmentsListHeight(0),
      greaterThanOrEqualTo(appointmentsListMinHeight),
    );
  });

  test('the list says how much room it needs, and it is enough for the cards',
      () {
    // Each card is drawn in full: the height the window asks for covers them all
    // (plus the chrome around the list) while it is under the ceiling.
    const count = 3;
    final height = appointmentsListHeight(count);
    expect(
      height,
      greaterThanOrEqualTo(kAppointmentCardHeight * count),
    );
  });

  test('a window without a record still has an owner line', () {
    final patient = Patient.fromJson({
      'id': 'owner-line',
      'title': 'Nadia Hassan',
      'birth': 1990,
    });
    final line = patientOwnerLine(patient);
    expect(line, contains('Nadia Hassan'));
    expect(line, contains('${patient.age}'));
  });
}

import 'package:apexo/ui/workspace/panel_accent.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a window takes the accent of the record its scope names', () {
    expect(PanelAccents.ofScope('patient:p1'), PanelAccents.patient);
    expect(PanelAccents.ofScope('appointment:a1'), PanelAccents.appointment);
    expect(PanelAccents.ofScope('supplier:s1'), PanelAccents.orders);
    // A photo or a scan picked from a file belongs to no record of its own.
    expect(PanelAccents.ofScope('row:a1'), isNull);
    expect(PanelAccents.ofScope(''), isNull);
  });

  test('no two kinds of record share a colour', () {
    final accents = {
      PanelAccents.patient,
      PanelAccents.appointment,
      PanelAccents.orders,
      PanelAccents.labwork,
      PanelAccents.account,
    };
    expect(accents, hasLength(5));
  });
}

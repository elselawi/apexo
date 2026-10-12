@Tags(['serial'])
library;

import 'package:apexo/common_widgets/item_title.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/features/patients/patients_screen.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

void main() {
  testWidgets('patients use detailed table rows without a view toggle',
      (tester) async {
    final previous = patients.docs.values.toList();
    patients.observableMap.clear();
    addTearDown(() {
      patients.observableMap.clear();
      patients.setAll(previous);
    });
    patients.set(Patient.fromJson({
      'id': 'patient-table-test',
      'title': 'Table Patient',
      'tags': ['Follow-up'],
    }));

    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpApexoApp(tester, const PatientsScreen());

    final title = find.byWidgetPredicate(
        (widget) => widget is ItemTitle && widget.item.title == 'Table Patient');
    expect(title, findsOneWidget);
    expect(find.descendant(of: title, matching: find.byType(CircleAvatar)),
        findsOneWidget);
    expect(find.text('Follow-up'), findsWidgets);
    expect(find.byKey(WK.listSearch), findsOneWidget);
    expect(find.byKey(WK.btnNewPatient), findsOneWidget);
    expect(find.byType(GridView), findsNothing);
    expect(find.byKey(const Key('dataTableListView')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long pressing a patient row opens its context menu',
      (tester) async {
    final previous = patients.docs.values.toList();
    patients.observableMap.clear();
    addTearDown(() {
      patients.observableMap.clear();
      patients.setAll(previous);
    });
    patients.set(Patient.fromJson({
      'id': 'patient-menu-test',
      'title': 'Menu Patient',
      'email': 'menu@patient.test',
    }));

    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpApexoApp(tester, const PatientsScreen());

    final title = find.byWidgetPredicate(
        (widget) => widget is ItemTitle && widget.item.title == 'Menu Patient');

    expect(find.byType(MenuFlyout), findsNothing);

    await tester.longPress(title);
    await tester.pumpAndSettle();

    Finder item(String key) => find.descendant(
          of: find.byType(MenuFlyout),
          matching: find.text(txt(key)),
        );
    // One item per patient tab, then the ways to reach the patient.
    expect(item("patientDetails"), findsWidgets);
    expect(item("dentalNotes"), findsWidgets);
    expect(item("patientPage"), findsWidgets);
    expect(item("sendEmail"), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

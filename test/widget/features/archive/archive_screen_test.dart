@Tags(['serial'])
library;

import 'package:apexo/features/archive/archive_screen.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/model_factory.dart';
import '../../../helpers/pump_app.dart';

void main() {
  late List<int> originalPerms;

  setUp(() {
    originalPerms = login.savedPermissions;
    login.savedPermissions = Perm.full;
  });

  tearDown(() {
    login.savedPermissions = originalPerms;
  });

  testWidgets('long pressing an archived row offers open and restore',
      (tester) async {
    final previous = patients.docs.values.toList();
    patients.observableMap.clear();
    final archived = testPatient(
      id: 'archived-row-test',
      name: 'Archived Patient',
    );
    patients.set(archived);
    // The screen reads the store's archived map, which archive() maintains
    // without a live persistence session.
    patients.archive(archived.id);
    addTearDown(() {
      patients.observableMap.clear();
      patients.archived.clear();
      patients.setAll(previous);
    });

    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpApexoApp(tester, const ArchivedScreen());

    expect(find.byType(MenuFlyout), findsNothing);

    await tester.longPress(find.text('Archived Patient').first);
    await tester.pumpAndSettle();

    Finder item(String key) => find.descendant(
          of: find.byType(MenuFlyout),
          matching: find.text(txt(key)),
        );
    expect(item("open"), findsWidgets);
    expect(item("restore"), findsWidgets);
    // Deleting for good is not something this page offers.
    expect(item("delete"), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('restoring from the row menu puts the record back',
      (tester) async {
    final previous = patients.docs.values.toList();
    patients.observableMap.clear();
    final archived = testPatient(
      id: 'archived-restore-test',
      name: 'Restore Patient',
    );
    patients.set(archived);
    patients.archive(archived.id);
    addTearDown(() {
      patients.observableMap.clear();
      patients.archived.clear();
      patients.setAll(previous);
    });

    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpApexoApp(tester, const ArchivedScreen());

    await tester.longPress(find.text('Restore Patient').first);
    await tester.pumpAndSettle();

    await tester.tap(find
        .descendant(
          of: find.byType(MenuFlyout),
          matching: find.text(txt("restore")),
        )
        .first);
    await tester.pumpAndSettle();

    expect(patients.archived.containsKey('archived-restore-test'), isFalse);
    expect(patients.get('archived-restore-test')!.archived, isFalse);
    expect(find.text('Restore Patient'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

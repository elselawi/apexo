@Tags(['serial'])
library;

import 'dart:convert';

import 'package:apexo/common_widgets/item_title.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:apexo/utils/imgs.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/model_factory.dart';
import '../../helpers/pump_app.dart';

void main() {
  late List<Appointment> originalAppointments;
  late List<int> originalPerms;
  final image = MemoryImage(
      base64Decode('R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7'));

  setUp(() {
    originalAppointments = appointments.docs.values.toList();
    originalPerms = login.savedPermissions;
    login.savedPermissions = Perm.full;
    appointments.observableMap.clear();
    imgMemoryCache['avatar-before.jpg'] = image;
    imgMemoryCache['avatar-after.jpg'] = image;
  });

  tearDown(() {
    appointments.observableMap.clear();
    appointments.setAll(originalAppointments);
    login.savedPermissions = originalPerms;
    imgMemoryCache.remove('avatar-before.jpg');
    imgMemoryCache.remove('avatar-after.jpg');
  });

  testWidgets('rendering an empty title does not edit the record',
      (tester) async {
    final patient = testPatient(name: '');
    await pumpApexoApp(tester, Center(child: ItemAvatar(item: patient)));
    expect(patient.title, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'avatar requests survive rebuilds and refresh for changed sources',
      (tester) async {
    final patient = testPatient(id: 'avatar-patient');
    void visit(String id, String file) {
      appointments.observableMap.clear();
      appointments.set(testAppointment(
        id: id,
        patientID: patient.id,
        date: DateTime(2026, 1, 1),
        imgs: [file],
      ));
    }

    Future<void> pumpAvatar() =>
        pumpApexoApp(tester, Center(child: ItemAvatar(item: patient)));
    Future<ImageProvider?>? request() => tester
        .widget<FutureBuilder<ImageProvider?>>(
            find.byType(FutureBuilder<ImageProvider?>))
        .future;

    visit('avatar-visit', 'avatar-before.jpg');
    await pumpAvatar();
    final initialRequest = request();
    expect(initialRequest, isNotNull);
    expect(
        tester.widget<CircleAvatar>(find.byType(CircleAvatar)).backgroundImage,
        same(image));

    await pumpAvatar();
    expect(request(), same(initialRequest));

    visit('another-visit', 'avatar-before.jpg');
    await pumpAvatar();
    final movedRequest = request();
    expect(movedRequest, isNot(same(initialRequest)));

    visit('another-visit', 'avatar-after.jpg');
    await pumpAvatar();
    expect(request(), isNot(same(movedRequest)));

    appointments.observableMap.clear();
    await pumpAvatar();
    expect(request(), isNull);
    expect(
        tester.widget<CircleAvatar>(find.byType(CircleAvatar)).backgroundImage,
        isNull);
    expect(tester.takeException(), isNull);
  });
}

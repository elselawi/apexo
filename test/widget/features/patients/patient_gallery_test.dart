@Tags(['serial'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:apexo/common_widgets/grid_gallery.dart';
import 'package:apexo/core/model.dart';
import 'package:apexo/core/persistence/save_local.dart';
import 'package:apexo/core/persistence/save_remote.dart';
import 'package:apexo/core/reactive/observable.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/appointments/visit_gallery.dart';
import 'package:apexo/features/patients/patient_gallery.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:apexo/utils/imgs.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../../helpers/hive_setup.dart';
import '../../../helpers/model_factory.dart';

/// Never-online remote: file deletes are journalled locally, keeping tests off
/// the network.
class _OfflineRemote extends SaveRemote {
  _OfflineRemote()
      : super(
          storeName: 'appointments',
          pbInstance: PocketBase('http://offline-pocketbase'),
        );

  @override
  Future<void> checkOnline() async => isOnline = false;
}

void _restore<T extends Model>(
    ObservableDict<T> store, Map<String, T> records) {
  store.silently(() {
    store.clear();
    store.setAll(records.values.toList());
  });
  store.notifyView();
}

/// Seeds the image cache so a tile never reaches for the network to draw.
void _cacheImage(String name) {
  final previous = imgMemoryCache[name];
  imgMemoryCache[name] = MemoryImage(
      base64Decode('R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7'));
  addTearDown(() {
    if (previous == null) {
      imgMemoryCache.remove(name);
    } else {
      imgMemoryCache[name] = previous;
    }
  });
}

/// Bounded pumps, not `pumpAndSettle`: a tile still loading never settles.
Future<void> _pumpGallery(WidgetTester tester, Patient patient) async {
  await tester.pumpWidget(FluentApp(
    home: ScaffoldPage(
      content: SingleChildScrollView(child: PatientGallery(patient)),
    ),
  ));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  late List<int> originalPerms;
  late Map<String, Appointment> originalAppointments;
  late Directory hiveDirectory;
  late SaveLocal local;
  var caseNumber = 0;

  setUpAll(() async => hiveDirectory = await setupTestHive());
  tearDownAll(() async => teardownTestHive(hiveDirectory));

  setUp(() async {
    originalPerms = login.savedPermissions;
    originalAppointments = {...appointments.observableMap.docs};
    login.savedPermissions = Perm.full;
    local = SaveLocal(
      name: 'patient-gallery',
      uniqueId: 'case-${caseNumber++}',
      storagePath: hiveDirectory.path,
    );
    appointments.local = local;
    appointments.remote = _OfflineRemote();
    appointments.observableMap.clear();
  });

  tearDown(() async {
    login.savedPermissions = originalPerms;
    appointments.remote?.dispose();
    appointments.remote = null;
    appointments.local = null;
    _restore(appointments.observableMap, originalAppointments);
    await local.dispose();
  });

  testWidgets('each visit holding files is one card, newest first',
      (tester) async {
    const olderPhoto = 'gallery-older.gif';
    const newerPhoto = 'gallery-newer.gif';
    const xray = 'gallery-xray.dcm';
    _cacheImage(olderPhoto);
    _cacheImage(newerPhoto);
    _cacheImage('$xray.png');

    final patient = testPatient(id: 'gallery-widget-patient');
    appointments.setAll([
      testAppointment(
        id: 'gallery-visit-older',
        patientID: patient.id,
        date: DateTime(2026, 1, 10),
        imgs: [olderPhoto],
      ),
      testAppointment(
        id: 'gallery-visit-newer',
        patientID: patient.id,
        date: DateTime(2026, 1, 12),
        imgs: [newerPhoto],
        dcmImgs: [xray],
      ),
      testAppointment(
        id: 'gallery-visit-text-only',
        patientID: patient.id,
        date: DateTime(2026, 1, 11),
        preOpNotes: 'consultation only',
      ),
    ]);

    await _pumpGallery(tester, patient);

    final cards =
        tester.widgetList<VisitPhotosCard>(find.byType(VisitPhotosCard));
    expect(cards.map((card) => card.visit.id).toList(),
        ['gallery-visit-newer', 'gallery-visit-older'],
        reason: 'a card per visit that holds files, newest first');

    final galleries =
        tester.widgetList<GridGallery>(find.byType(GridGallery)).toList();
    expect(galleries.map((gallery) => gallery.rowId).toList(),
        ['gallery-visit-newer', 'gallery-visit-older'],
        reason: 'each card shows its own visit\'s files, addressed by its id');
    expect(galleries.first.imgs, [newerPhoto]);
    expect(galleries.first.dcmImgs, [xray]);
    expect(galleries.last.imgs, [olderPhoto]);
    expect(galleries.every((gallery) => gallery.canDelete), isTrue,
        reason: 'full photos permission, and the visits are this user\'s');
  });

  testWidgets('deleting a photo takes it out of the visit that holds it',
      (tester) async {
    const photo = 'gallery-delete.gif';
    _cacheImage(photo);

    final patient = testPatient(id: 'gallery-delete-patient');
    final visit = testAppointment(
      id: 'gallery-delete-visit',
      patientID: patient.id,
      date: DateTime(2026, 2, 3),
      imgs: [photo],
      drawings: {photo: 'drawing'},
    );
    appointments.set(visit);

    await _pumpGallery(tester, patient);

    final gallery = tester.widget<GridGallery>(find.byType(GridGallery));
    expect(gallery.rowId, visit.id);
    expect(gallery.imgs, [photo]);

    await tester.runAsync(() => gallery.onPressDelete(photo));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The delete is a command on the visit: it writes the store record, not the
    // copy the card held.
    expect(appointments.get(visit.id)!.imgs, isEmpty,
        reason: 'the photo is deleted from the visit, not from the window');
    expect(appointments.get(visit.id)!.drawings, isEmpty,
        reason: 'a drawing of a deleted photo goes with it');
    expect(find.byType(GridGallery), findsNothing,
        reason: 'a visit with nothing left is no longer a gallery card');
  });
}

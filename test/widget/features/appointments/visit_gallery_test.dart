@Tags(['serial'])
library;

import 'package:apexo/features/appointments/appointment_commands.dart';
import 'package:apexo/features/appointments/appointment_windows.dart';
import 'package:apexo/features/appointments/visit_gallery.dart';
import 'package:apexo/common_widgets/grid_gallery.dart';
import 'package:apexo/features/appointments/appointment_sessions.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/model_factory.dart';
import '../../../helpers/pump_app.dart';

/// The gallery's write is not the visit's Save.
///
/// A photo is uploaded the moment the user picks it; the pre-op notes typed
/// beside it are not typed into a photo. Before this, `appointments.set(visit)`
/// wrote the whole draft — notes and all — and `panel.markSaved` then told the
/// visit it had nothing left to save, so the photo's write silently became the
/// visit's write (plan §7.4).
void main() {
  late List<Appointment> originalAppointments;

  setUp(() {
    originalAppointments = appointments.docs.values.toList();
    appointments.observableMap.clear();
  });

  tearDown(() {
    appointmentSessions.clear();
    appointments.observableMap.clear();
    appointments.setAll(originalAppointments);
  });

  Appointment storedVisit() => testAppointment(
        id: 'gallery-visit',
        patientID: 'gallery-patient',
        date: DateTime(2026, 2, 3, 9, 30),
        preOpNotes: 'stored note',
        imgs: ['first.jpg'],
      );

  testWidgets('switching visits replaces the gallery operation state',
      (tester) async {
    final first = testAppointment(id: 'first-gallery');
    final second = testAppointment(id: 'second-gallery');
    await pumpApexoApp(tester, AppointmentGalleryPane(first));
    final previous = tester.state(find.byType(VisitGallery));

    await pumpApexoApp(tester, AppointmentGalleryPane(second));

    expect(tester.state(find.byType(VisitGallery)), isNot(same(previous)));
    expect(previous.mounted, isFalse);
    expect(tester.widget<VisitGallery>(find.byType(VisitGallery)).visit.id,
        second.id);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the visit owner hears gallery upload progress', (tester) async {
    final progress = <bool>[];
    await pumpApexoApp(
        tester,
        VisitGallery(testAppointment(),
            uploads: true, onProgress: progress.add));
    final grid = tester.widget<GridGallery>(find.byType(GridGallery));
    grid.onProgress!(true);
    grid.onProgress!(false);
    expect(progress, [true, false]);
    expect(tester.takeException(), isNull);
  });

  test('an upload writes the files and leaves the typed note unsaved', () {
    appointments.set(storedVisit());
    // The visit's open draft: what the gallery holds, with an unsaved note.
    final draft =
        Appointment.fromJson(appointments.get('gallery-visit')!.toJson())
          ..preOpNotes = 'note being typed'
          ..imgs = ['first.jpg', 'uploaded.jpg']
          ..drawings = {'first.jpg': 'scribble'};

    writeVisitImages(draft);

    final stored = appointments.get('gallery-visit')!;
    expect(stored.imgs, ['first.jpg', 'uploaded.jpg'],
        reason: 'the photo is stored at once: the gallery owns that field');
    expect(stored.drawings, {'first.jpg': 'scribble'});
    expect(stored.preOpNotes, 'stored note',
        reason: 'the note is not the gallery\'s field, so the upload cannot '
            'store it');
    expect(draft.preOpNotes, 'note being typed');
  });

  test('deleting the last photo drops the stored field, not the notes', () {
    appointments.set(storedVisit());
    final draft =
        Appointment.fromJson(appointments.get('gallery-visit')!.toJson())
          ..preOpNotes = 'note being typed'
          ..imgs = <String>[];

    writeVisitImages(draft);

    final stored = appointments.get('gallery-visit')!;
    expect(stored.imgs, isEmpty);
    expect(stored.preOpNotes, 'stored note');
  });

  test('the visit is still dirty on its note after the gallery is acknowledged',
      () {
    final stored = storedVisit();
    appointments.set(stored);
    // The visit's owner is its session: one draft, one Save, and an
    // acknowledgement that names the fields it covers (plan §2.1).
    final session = appointmentSessions.getOrCreate(stored);
    session.item.preOpNotes = 'note being typed';
    session.refreshDirty();
    expect(session.hasPendingEdits, isTrue);

    session.item.imgs = ['first.jpg', 'uploaded.jpg'];
    writeVisitImages(session.item);
    session.markFieldsSaved(kVisitImageFields);

    expect(session.hasPendingEdits, isTrue,
        reason: 'acknowledging the photos must not acknowledge the note');
    expect(appointments.get('gallery-visit')!.preOpNotes, 'stored note');
    expect(
        appointments.get('gallery-visit')!.imgs, ['first.jpg', 'uploaded.jpg']);
  });
}

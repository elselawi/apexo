@Tags(['serial'])
library;

import 'dart:convert';

import 'package:apexo/features/appointments/visit_attachment_chips.dart';
import 'package:apexo/utils/imgs.dart' show imgMemoryCache;
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/model_factory.dart';
import '../../../helpers/pump_app.dart';

/// What a visit's attachment chip says beyond its own name: the gallery shows
/// the pictures it opens, and the labwork order shows whether it exists and
/// whether it has come back.
void main() {
  final onePixelPng = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==');

  void cachePicture(String name) {
    imgMemoryCache[name] = MemoryImage(onePixelPng);
    addTearDown(() => imgMemoryCache.remove(name));
  }

  test('a visit with no pictures previews nothing', () {
    expect(VisitGalleryChipPreviews.of(testAppointment(id: 'empty')), isNull);
  });

  test('a visit with a picture previews it', () {
    final appointment = testAppointment(id: 'shot', imgs: const ['a.jpg']);
    expect(VisitGalleryChipPreviews.of(appointment), isNotNull);
  });

  testWidgets('the gallery chip draws one thumbnail per picture, photos first',
      (tester) async {
    cachePicture('photo.jpg');
    // `getImage` resolves an X-ray to the PNG preview stored beside it.
    cachePicture('xray.dcm.png');
    final appointment = testAppointment(
      id: 'two-pictures',
      imgs: const ['photo.jpg'],
      dcmImgs: const ['xray.dcm'],
    );

    await pumpApexoApp(tester, VisitGalleryChipPreviews(appointment));
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  test('an order that was never written carries no badge', () {
    expect(VisitLabworkChipBadge.of(testAppointment(id: 'no-order')), isNull);
  });

  testWidgets('an order waiting on the lab says so, and one back says that',
      (tester) async {
    final waiting = testAppointment(id: 'due', hasLabwork: true);
    final back =
        testAppointment(id: 'back', hasLabwork: true, labworkReceived: true);

    await pumpApexoApp(tester, VisitLabworkChipBadge(waiting));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Icon>(find.byType(Icon)).icon,
      FluentIcons.clock,
      reason: 'the lab still has it',
    );

    await pumpApexoApp(tester, VisitLabworkChipBadge(back));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Icon>(find.byType(Icon)).icon,
      FluentIcons.check_mark,
      reason: 'the work is back',
    );
    expect(tester.takeException(), isNull);
  });
}

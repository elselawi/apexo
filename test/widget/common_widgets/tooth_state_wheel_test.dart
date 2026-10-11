import 'package:apexo/common_widgets/live_transcribing_textfield.dart';
import 'package:apexo/common_widgets/teeth_selector/tooth_state_wheel.dart';
import 'package:apexo/common_widgets/teeth_selector/tooth_history.dart';
import 'package:apexo/common_widgets/teeth_selector/tx_options.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/common_widgets/teeth_selector/teeth_selector.dart';
import 'package:flutter/semantics.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../helpers/pump_app.dart';

void main() {
  testWidgets(
      'chart wheel remains open through selection and saves notes to same tooth',
      (tester) async {
    final current = <String, String>{};
    final extra = <String, String>{};
    final handle = tester.ensureSemantics();
    await pumpApexoApp(
        tester,
        SingleChildScrollView(
            child: TeethSelector(
          notation: (iso) => 'Tooth $iso',
          type: StateType.state,
          currentNotes: current,
          extraNotes: extra,
          onNote: (iso, value) {
            if (value == null) {
              current.remove(iso);
              extra.remove(iso);
            } else {
              current[iso] = value;
            }
          },
          onExtraNote: (iso, text) => extra[iso] = text,
        )));
    final node = tester.getSemantics(find.bySemanticsLabel('Tooth 11'));
    node.owner!.performAction(node.id, SemanticsAction.tap);
    await tester.pumpAndSettle();
    await tester.tap(find.text(txt('filling')).first);
    await tester.pumpAndSettle();
    expect(find.byType(ToothStateWheel), findsOneWidget);
    expect(current, {'11': 'filling'});
    final field = tester.widget<LiveTranscribingTextField>(
        find.byType(LiveTranscribingTextField));
    field.controller!.text = 'Extra detail';
    field.onChanged!('Extra detail');
    await tester.pumpAndSettle();
    expect(extra, {'11': 'Extra detail'});
    await tester.tap(find.byKey(const ValueKey('wheel-close')));
    await tester.pumpAndSettle();
    expect(find.byType(ToothStateWheel), findsNothing);
    expect(current, {'11': 'filling'});
    expect(extra, {'11': 'Extra detail'});
    handle.dispose();
  });

  testWidgets('selection commits immediately and notes field accepts input',
      (tester) async {
    String? selected;
    String? note;
    await pumpApexoApp(
        tester,
        Center(
            child: ToothStateWheel(
                initialValue: null,
                iso: '11',
                toothName: 'Tooth 11',
                oldNote: null,
                type: StateType.state,
                onTapClose: () {},
                onSet: (value) => selected = value,
                onExtraNote: (value) => note = value)));
    expect(find.byKey(const ValueKey('extra-notes-circle')), findsOneWidget);
    // Nothing is chosen yet, so there is nothing to annotate: no text field.
    expect(find.byType(LiveTranscribingTextField), findsNothing);
    await tester.tap(find.text(txt('filling')).first);
    await tester.pump();
    expect(selected, 'filling');
    await tester.pumpAndSettle();
    expect(
        tester.getSize(find.byKey(const ValueKey('choice-wheel'))).width, 350);
    final field = tester.widget<LiveTranscribingTextField>(
        find.byType(LiveTranscribingTextField));
    field.controller!.text = 'Review next visit';
    field.onChanged!('Review next visit');
    expect(note, 'Review next visit');
    expect(selected, 'filling');

    // A recorded treatment keeps the folded view: tapping the chosen option
    // again changes nothing and does not put the ring back or throw the note
    // away. The wait lets the double-tap window lapse, so the tap is read as
    // a tap on the recorded choice rather than a confirmation.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byWidgetPredicate((widget) =>
        widget is Semantics &&
        widget.properties.button == true &&
        widget.properties.label == txt('filling')));
    await tester.pumpAndSettle();
    expect(selected, 'filling');
    expect(
        tester
            .widget<LiveTranscribingTextField>(
                find.byType(LiveTranscribingTextField))
            .controller!
            .text,
        'Review next visit');
    final rct = find.byWidgetPredicate((widget) =>
        widget is Semantics &&
        widget.properties.button == true &&
        widget.properties.label == txt('rCT'));
    AnimatedOpacity rctOpacity() => tester.widget<AnimatedOpacity>(
        find.descendant(of: rct, matching: find.byType(AnimatedOpacity)).first);
    expect(rctOpacity().opacity, 0.0, reason: 'the ring stays folded');

    // Clearing is the way back to the ring, and it takes the note with it.
    await tester.tap(find.byKey(const ValueKey('wheel-clear')));
    await tester.pumpAndSettle();
    expect(selected, isNull);
    expect(note, '');
    expect(rctOpacity().opacity, 1.0, reason: 'the ring is back');
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom other option commits as it is typed, without buttons',
      (tester) async {
    final values = <String?>[];
    String? note;
    await pumpApexoApp(
        tester,
        Center(
            child: ToothStateWheel(
                initialValue: null,
                iso: '11',
                toothName: 'Tooth 11',
                oldNote: null,
                type: StateType.treatment,
                onTapClose: () {},
                onSet: values.add,
                onExtraNote: (value) => note = value)));
    await tester.tap(find.byWidgetPredicate((widget) =>
        widget is Semantics &&
        widget.properties.button == true &&
        widget.properties.label == txt('other')));
    await tester.pumpAndSettle();
    // The custom editor is the same field as the notes one — no save/cancel.
    expect(find.byType(LiveTranscribingTextField), findsOneWidget);
    expect(find.text(txt('save')), findsNothing);
    expect(find.text(txt('cancel')), findsNothing);
    final field = tester.widget<LiveTranscribingTextField>(
        find.byType(LiveTranscribingTextField));
    field.controller!.text = 'Night guard';
    field.onChanged!('Night guard');
    await tester.pumpAndSettle();
    expect(values.last, 'Night guard');
    // An emptied custom label clears the choice rather than saving a blank.
    field.controller!.text = '';
    field.onChanged!('');
    await tester.pumpAndSettle();
    expect(values.last, isNull);
    expect(note, isNull);

    // "Other" behaves exactly like a selection: the ring folds away and the
    // other options leave the wheel, leaving all the room to the field.
    final filling = find.byWidgetPredicate((widget) =>
        widget is Semantics &&
        widget.properties.button == true &&
        widget.properties.label == txt('filling'));
    final opacity = tester.widget<AnimatedOpacity>(find
        .descendant(of: filling, matching: find.byType(AnimatedOpacity))
        .first);
    expect(opacity.opacity, 0.0);
    // Clearing is the way back: the ring returns and another option can be
    // picked in place of the custom label.
    await tester.tap(find.byKey(const ValueKey('wheel-clear')));
    await tester.pumpAndSettle();
    expect(values.last, isNull);
    await tester.tap(filling);
    await tester.pumpAndSettle();
    expect(values.last, 'filling');
    expect(tester.takeException(), isNull);
  });

  testWidgets('clearing removes the choice and its note', (tester) async {
    final values = <String?>[];
    String? note;
    await pumpApexoApp(
        tester,
        Center(
            child: ToothStateWheel(
                initialValue: 'filling',
                iso: '11',
                toothName: 'Tooth 11',
                oldNote: null,
                type: StateType.treatment,
                extraNote: 'Keep me until cleared',
                onTapClose: () {},
                onSet: values.add,
                onExtraNote: (value) => note = value)));
    await tester.tap(find.byKey(const ValueKey('wheel-clear')));
    await tester.pumpAndSettle();
    expect(values, [null]);
    expect(note, '');
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the chosen option keeps it folded and does not close',
      (tester) async {
    final values = <String?>[];
    var closed = false;
    await pumpApexoApp(
        tester,
        Center(
            child: ToothStateWheel(
                initialValue: 'crown',
                iso: '36',
                toothName: 'Tooth 36',
                oldNote: null,
                type: StateType.treatment,
                onTapClose: () => closed = true,
                onSet: values.add)));
    await tester.tap(find.byWidgetPredicate((widget) =>
        widget is Semantics &&
        widget.properties.button == true &&
        widget.properties.label == txt('crown')));
    await tester.pumpAndSettle();
    // The choice is already recorded: a single tap changes nothing at all —
    // the folded view is the only view of a recorded treatment — and it must
    // not dismiss the popup either.
    expect(values, isEmpty, reason: 'the choice is recorded once');
    expect(closed, isFalse);
    final filling = find.byWidgetPredicate((widget) =>
        widget is Semantics &&
        widget.properties.button == true &&
        widget.properties.label == txt('filling'));
    final opacity = tester.widget<AnimatedOpacity>(find
        .descendant(of: filling, matching: find.byType(AnimatedOpacity))
        .first);
    expect(opacity.opacity, 0.0, reason: 'the ring stays folded');
    expect(tester.takeException(), isNull);
  });

  testWidgets('choosing an option folds the ring into a wide notes surface',
      (tester) async {
    await pumpApexoApp(
        tester,
        Center(
            child: ToothStateWheel(
                initialValue: null,
                iso: '11',
                toothName: 'Tooth 11',
                oldNote: null,
                type: StateType.state,
                onTapClose: () {},
                onSet: (_) {})));
    // Before a choice the notes surface is the small circle in the middle.
    expect(
        tester.getSize(find.byKey(const ValueKey('extra-notes-circle'))).width,
        lessThan(200));
    await tester.tap(find.text(txt('filling')).first);
    await tester.pumpAndSettle();
    // The surface is still 350 wide and the field fills it without the
    // platform's own field box, which would paint grey over the tint.
    final wheel = tester.getRect(find.byKey(const ValueKey('choice-wheel')));
    expect(wheel.width, 350);
    final field = tester.widget<LiveTranscribingTextField>(
        find.byType(LiveTranscribingTextField));
    expect(field.decoration, isNotNull);
    expect(field.decoration!.color, isNull);
    final notes =
        tester.getSize(find.byKey(const ValueKey('extra-notes-circle')));
    expect(notes.width, greaterThan(300));
    expect(notes.height, greaterThan(240));
    // The chosen option rides at the top of the surface...
    final chip = tester.getCenter(find.byWidgetPredicate((widget) =>
        widget is Semantics &&
        widget.properties.button == true &&
        widget.properties.label == txt('filling')));
    expect(chip.dy, lessThan(wheel.top + 70));
    expect(chip.dx, closeTo(wheel.center.dx, 1));
    // ...and the unchosen ones have left the wheel.
    final crownOpacity = tester.widget<AnimatedOpacity>(find
        .descendant(
            of: find.byWidgetPredicate((widget) =>
                widget is Semantics &&
                widget.properties.button == true &&
                widget.properties.label == txt('crown')),
            matching: find.byType(AnimatedOpacity))
        .first);
    expect(crownOpacity.opacity, 0.0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('double tapping an option confirms it and closes the popup',
      (tester) async {
    final values = <String?>[];
    var closed = false;
    await pumpApexoApp(
        tester,
        Center(
            child: ToothStateWheel(
                initialValue: null,
                iso: '11',
                toothName: 'Tooth 11',
                oldNote: null,
                type: StateType.treatment,
                onTapClose: () => closed = true,
                onSet: values.add)));
    final filling = find.byWidgetPredicate((widget) =>
        widget is Semantics &&
        widget.properties.button == true &&
        widget.properties.label == txt('filling'));
    await tester.tap(filling);
    await tester.pump(const Duration(milliseconds: 120));
    expect(values, ['filling']);
    expect(closed, isFalse);
    await tester.tap(filling);
    await tester.pumpAndSettle();
    expect(values, ['filling'], reason: 'the choice is recorded once');
    expect(closed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping outside the floating surfaces dismisses the popup',
      (tester) async {
    var closed = false;
    await pumpApexoApp(
        tester,
        Center(
            child: ToothStateWheel(
                initialValue: null,
                iso: '11',
                toothName: 'Tooth 11',
                oldNote: null,
                type: StateType.treatment,
                onTapClose: () => closed = true,
                onSet: (_) {})));
    final rect = tester.getRect(find.byType(ToothStateWheel));
    // A corner of the popup, clear of the header pill and of the wheel circle.
    await tester.tapAt(Offset(rect.left + 4, rect.top + 4));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the wheel surface itself does not dismiss the popup',
      (tester) async {
    var closed = false;
    await pumpApexoApp(
        tester,
        Center(
            child: ToothStateWheel(
                initialValue: null,
                iso: '11',
                toothName: 'Tooth 11',
                oldNote: null,
                type: StateType.treatment,
                onTapClose: () => closed = true,
                onSet: (_) {})));
    // The empty middle of the wheel, where the hint sits: inside the surface.
    await tester
        .tapAt(tester.getCenter(find.byKey(const ValueKey('choice-wheel'))));
    await tester.pumpAndSettle();
    expect(closed, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the wheel takes taps on its paint, not on the box it sits in',
      (tester) async {
    var closed = false;
    await pumpApexoApp(
        tester,
        Center(
            child: ToothStateWheel(
                initialValue: null,
                iso: '11',
                toothName: 'Tooth 11',
                oldNote: null,
                type: StateType.state,
                onTapClose: () => closed = true,
                onSet: (_) {})));
    final box = tester.getRect(find.byKey(const ValueKey('choice-wheel')));
    // The empty band between the notes surface and the options is still the
    // wheel: a tap there must not throw the clinician out of the popup.
    await tester.tapAt(box.center + const Offset(110, 0));
    await tester.pumpAndSettle();
    expect(closed, isFalse);

    // The transparent corner of the square around the round wheel, however,
    // is outside it and dismisses the popup...
    await tester.tapAt(box.topLeft + const Offset(6, 6));
    await tester.pumpAndSettle();
    expect(closed, isTrue);

    // ...while the folded notes rectangle is one surface all the way out to
    // its rounded edge.
    closed = false;
    await tester.tap(find.text(txt('filling')).first);
    await tester.pumpAndSettle();
    final folded = tester.getRect(find.byKey(const ValueKey('choice-wheel')));
    await tester.tapAt(folded.centerLeft + const Offset(6, 0));
    await tester.pumpAndSettle();
    expect(closed, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'marked tooth opens with selection and its earlier records',
      (tester) async {
    await pumpApexoApp(
        tester,
        Center(
            child: ToothStateWheel(
                initialValue: 'crown',
                iso: '36',
                toothName: 'Tooth 36',
                oldNote: null,
                type: StateType.treatment,
                extraNote: 'Current note',
                onTapClose: () {},
                onSet: (_) {},
                history: [
              ToothHistory(
                  label: '12 June 2026',
                  date: DateTime(2026, 6, 12),
                  teeth: {'36': 'filling'},
                  notes: {'36': 'Full historical note'}),
              const ToothHistory(
                  label: 'Other tooth', teeth: {'11': 'caries'}, notes: {}),
            ])));
    expect(find.byKey(const ValueKey('extra-notes-circle')), findsOneWidget);
    expect(find.text(txt('toothHistory')), findsWidgets);
    expect(find.text('12 June 2026'), findsOneWidget);
    expect(find.text('Full historical note'), findsOneWidget);
    expect(find.text('Other tooth'), findsNothing);
    expect(
        tester
            .widget<LiveTranscribingTextField>(
                find.byType(LiveTranscribingTextField))
            .controller!
            .text,
        'Current note');
    expect(
        tester.getSize(find.byKey(const ValueKey('choice-wheel'))).width, 350);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the patient view names its history after the appointments',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pumpApexoApp(
        tester,
        Center(
            child: SizedBox(
          width: 700,
          child: TeethSelector(
            notation: (iso) => 'Tooth $iso',
            type: StateType.state,
            historyTitle: 'toothAppointmentNotes',
            history: [
              ToothHistory(
                  label: '1 June 2026',
                  date: DateTime(2026, 6, 1),
                  teeth: {'11': 'filling'},
                  notes: {'11': 'Older note'})
            ],
            onNote: (iso, note) {},
          ),
        )));
    final node = tester.getSemantics(find.bySemanticsLabel('Tooth 11'));
    node.owner!.performAction(node.id, SemanticsAction.tap);
    await tester.pumpAndSettle();
    // Browsed from the patient's own records the rows are what appointments
    // left on the tooth, so they are not called other appointments.
    expect(find.text(txt('toothAppointmentNotes')), findsWidgets);
    expect(find.text(txt('toothHistory')), findsNothing);
    expect(tester.takeException(), isNull);
    handle.dispose();
  });

  testWidgets('mobile layout renders without overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpApexoApp(
        tester,
        Center(
            child: ToothStateWheel(
                initialValue: 'filling',
                iso: '11',
                toothName: 'Tooth 11',
                oldNote: null,
                type: StateType.state,
                onTapClose: () {},
                onSet: (_) {})));
    expect(find.byKey(const ValueKey('extra-notes-circle')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

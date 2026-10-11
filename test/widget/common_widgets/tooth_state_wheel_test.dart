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
    await tester.tap(find.widgetWithText(Button, txt('close')).first);
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

    // Changing the choice must keep the notes already entered.
    await tester.tap(find.text(txt('rCT')).first);
    await tester.pumpAndSettle();
    expect(selected, 'rCT');
    expect(
        tester
            .widget<LiveTranscribingTextField>(
                find.byType(LiveTranscribingTextField))
            .controller!
            .text,
        'Review next visit');
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

    // "Other" behaves exactly like a selection: every other option stays on
    // the wheel — dimmed, not hidden — and remains tappable.
    final filling = find.byWidgetPredicate((widget) =>
        widget is Semantics &&
        widget.properties.button == true &&
        widget.properties.label == txt('filling'));
    final opacity = tester.widget<AnimatedOpacity>(find
        .descendant(of: filling, matching: find.byType(AnimatedOpacity))
        .first);
    expect(opacity.opacity, greaterThan(0.0));
    await tester.tap(filling);
    await tester.pumpAndSettle();
    expect(values.last, 'filling');
    expect(tester.takeException(), isNull);
  });

  testWidgets('deleting the choice clears the notes from the same tooth',
      (tester) async {
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
                extraNote: 'Keep me until deleted',
                onTapClose: () {},
                onSet: values.add,
                onExtraNote: (value) => note = value)));
    await tester.tap(find.byIcon(WindowsIcons.delete));
    await tester.pumpAndSettle();
    expect(values, [null]);
    expect(note, '');
    expect(tester.takeException(), isNull);
  });

  testWidgets('re-tapping the selected option keeps it selected',
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
    expect(values, ['crown']);
    // One tap records the choice; it must not also dismiss the popup, or a
    // clinician reaching for the notes field would be thrown out of it.
    expect(closed, isFalse);
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

  testWidgets(
      'marked tooth opens with selection and other appointments records',
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

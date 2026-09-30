import 'package:apexo/app/panels/panel_screen.dart' show PanelScreen;
import 'package:apexo/common_widgets/duration_pill.dart';
import 'package:apexo/features/accounts/accounts_controller.dart';
import 'package:apexo/features/appointments/calendar_widget.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/notes/notes_model.dart';
import 'package:apexo/features/notes/notes_store.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/localization/locale.dart' show Txt, locale, txt;
import 'package:apexo/services/login.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/cupertino.dart' show CupertinoTextField;
// The date/time fields open material's pickers (`showDatePicker`).
import 'package:flutter/material.dart' show DatePickerDialog, TextButton;
import 'package:flutter_test/flutter_test.dart';
import 'e2e.dart';
import 'credentials.dart' show pbEmail, pbPassword, pbServer;
import 'store_ext.dart';

/// The id of the board's uncategorized column.
///
/// It is not a stored row — it collects the notes with no column — so its id is
/// the empty string: `Note.unCategorized` is `isNote && columnID.isEmpty`.
const uncategorizedColumnId = '';

/// Creates records through the UI, so a test exercises the same path a user
/// does — the price is that seeding is slow, which is why these are for the
/// record under test rather than for a bulk baseline (see `todo.md` §0.1).
abstract final class Fixtures {
  // --------------------------------------------------------------- values

  /// A name that belongs to one run, so a failed run leaves nothing ambiguous
  /// and two runs never collide.
  ///
  /// The counter rides along with the clock because two calls in the same
  /// millisecond would otherwise produce the *same* name — and two identically
  /// named columns make every board finder ambiguous.
  static int _seq = 0;
  static String stamp([String prefix = 'e2e']) =>
      '$prefix ${DateTime.now().millisecondsSinceEpoch}-${_seq++}';

  /// A shut services section is its header (`minHeight: 42`); an open one is that
  /// plus its content (hundreds of pixels). Anything between is not expected, so
  /// the boundary is deliberately generous.
  static const double _collapsedSectionHeight = 60;

  // ------------------------------------------------------------ navigation

  /// Opens a route from the navigation pane and returns when [ready] is up.
  ///
  /// The pane items are keyed `<route identifier>_screen_button` in
  /// `lib/app/app.dart`.
  ///
  /// The tap is **verified by arriving**, and retried once if it did not: a tap
  /// that misses only warns, and the pane's header (`AppLogo` + `CurrentAccount`)
  /// changes height as the signed-in account's row settles — so the item that was
  /// under the pointer when the tap was computed can be a different item by the
  /// time it lands. That reads as "the screen never opened" 60 seconds later,
  /// usually in a run's first test (which is also the one that just signed in).
  static Future<void> openRoute(
    WidgetTester tester,
    String identifier,
    Finder ready, {
    String? description,
  }) async {
    final item = find.byKey(Key('${identifier}_screen_button'));
    final where = description ?? 'the $identifier screen';
    await E2E.tap(tester, item, description: 'the $identifier nav item');
    try {
      await E2E.waitFor(tester, ready,
          description: where, timeout: const Duration(seconds: 20));
      // The ready key appearing is not the same as the pane having *finished*
      // swapping screens: fluent wraps the body in an `AnimatedSwitcher`, so the
      // screen being left is still mounted for its 250ms transition — and two
      // screens mounted at once means two `WK.listSearch` boxes, which throws
      // `Bad state: Too many elements` in the next helper that types into one.
      // Settle past the transition before handing the caller a settled screen.
      await E2E.settle(tester, frames: 5);
      return;
    } catch (_) {
      // Fall through to one retry: a real failure still fails, with the same
      // message, 60s later.
    }
    // ignore: avoid_print
    print(
        '⚠️  the $identifier nav tap did not open its screen — tapping again');
    await E2E.tap(tester, item,
        description: 'the $identifier nav item (retry)');
    await E2E.waitFor(tester, ready, description: where);
  }

  static Future<void> openPatients(WidgetTester tester) => openRoute(
        tester,
        'patients',
        find.byKey(WK.btnNewPatient),
        description: 'the patients screen',
      );

  static Future<void> openCalendar(WidgetTester tester) => openRoute(
        tester,
        'calendar',
        find.byKey(WK.btnNewAppointment),
        description: 'the calendar screen',
      );

  // --------------------------------------------------------------- panels

  /// Whether the open panel would save anything (`false` on a clean draft).
  static bool canSave(WidgetTester tester) =>
      tester.widget<IconButton>(find.byKey(WK.panelSave)).onPressed != null;

  /// Waits for the panel's dirty state to settle.
  ///
  /// `PanelScreen` publishes it from a 750ms timer, so right after a keystroke
  /// (or right after the panel opens) the button is still showing the previous
  /// state. Reading it without waiting makes a test that should pass flaky.
  static Future<void> waitForSaveState(
    WidgetTester tester, {
    required bool expectChanges,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 200));
      if (canSave(tester) == expectChanges) return;
    }
    fail('The panel never settled to '
        '${expectChanges ? 'having something to save' : 'nothing to save'}.');
  }

  /// Taps a panel's save control, bringing it into view first.
  ///
  /// A panel with a long body — or one whose lab-name field left fluent's
  /// suggestion overlay open over the footer — swallows a bare tap; the harness
  /// only sees `warnIfMissed`, and the save silently never happens (which reads
  /// as "the panel never settled to nothing to save").
  static Future<void> _tapSave(WidgetTester tester, Finder save) async {
    await tester.ensureVisible(save.first);
    await E2E.settle(tester, frames: 5);
    await tester.tap(save.first);
    await E2E.settle(tester, frames: 5);
  }

  /// Taps Save and waits until the panel reports itself clean again.
  static Future<void> save(WidgetTester tester) async {
    await waitForSaveState(tester, expectChanges: true);
    await _tapSave(tester, find.byKey(WK.panelSave));
    await waitForSaveState(tester, expectChanges: false);
  }

  /// Closes the open panel.
  ///
  /// A panel with work in it asks first (`sureClosePanel`), which is two steps
  /// for a user as well, so the prompt is answered here unless the caller opts
  /// out with [allowPrompt] — do that when the *prompt* is what is under test.
  static Future<void> closePanel(
    WidgetTester tester, {
    bool allowPrompt = true,
  }) async {
    await E2E.tap(tester, find.byKey(WK.panelClose),
        description: 'the panel close button');
    // The flyout is opened through `flyoutFocusFix`, so it is not there on the
    // same frame. Wait for it rather than assuming either way.
    final deadline = DateTime.now().add(const Duration(seconds: 1));
    while (allowPrompt &&
        find.byType(FlyoutContent).evaluate().isEmpty &&
        DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    if (allowPrompt && find.byType(FlyoutContent).evaluate().isNotEmpty) {
      await confirmFlyout(tester);
    }
    await E2E.waitForGone(tester, find.byKey(WK.panelSave),
        description: 'the panel');
  }

  /// Confirms the flyout the panel's delete/archive button opens.
  ///
  /// The confirm button is the first `FilledButton` in the flyout; matching its
  /// label instead is brittle (it is the localized action word, capitalised).
  static Future<void> confirmFlyout(WidgetTester tester) async {
    final confirm = find.descendant(
      of: find.byType(FlyoutContent),
      matching: find.byType(FilledButton),
    );
    await E2E.waitFor(tester, confirm,
        description: 'the flyout confirm button');
    await tester.tap(confirm.first);
    await E2E.settle(tester, frames: 10);
  }

  /// The field's current text (for asserting what the app normalised it to).
  ///
  /// The key can sit on a wrapper that builds the field itself
  /// (`LiveTranscribingTextField`), and the field can be scrolled out of the
  /// panel's view — which is why the lookup descends and does not skip what is
  /// off screen.
  static String fieldText(WidgetTester tester, Key key) {
    final field = find.byKey(key, skipOffstage: false);
    final inner = find.descendant(
      of: field,
      matching: find.byType(CupertinoTextField, skipOffstage: false),
      matchRoot: true,
    );
    final target = inner.evaluate().isNotEmpty ? inner.first : field;
    return tester.widget<CupertinoTextField>(target).controller?.text ?? '';
  }

  /// The scrollable the open panel's body lives in.
  ///
  /// The tab strip has a horizontal scrollable of its own, so this takes the
  /// vertical one inside the panel — and starting from the panel (rather than
  /// the whole tree) keeps it from grabbing the screen behind it.
  static Finder panelBody() => find
      .descendant(
        of: find.byType(PanelScreen),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      )
      .first;

  /// Types [text] into the field with [key], scrolling until the field is on
  /// screen.
  ///
  /// A finder does not see a field a scroll view has moved out of sight, so a
  /// field below the panel's fold — the price, the post-op notes — cannot be
  /// typed into until the panel is scrolled to it.
  static Future<void> enterField(
    WidgetTester tester,
    Key key,
    String text, {
    Finder? scrollable,
  }) async {
    final scroll = scrollable ?? panelBody();
    for (var attempt = 0; attempt < 10; attempt++) {
      final editable = find.descendant(
        of: find.byKey(key),
        matching: find.byType(EditableText),
        matchRoot: true,
      );
      if (editable.evaluate().isNotEmpty) {
        await tester.enterText(editable.first, text);
        await E2E.settle(tester);
        return;
      }
      if (scroll.evaluate().isEmpty) break;
      await tester.drag(scroll, const Offset(0, -180));
      await E2E.settle(tester, frames: 3);
    }
    fail('The "$key" field never came into view, so nothing could be typed '
        'into it.');
  }

  /// Adds one tag by picking it from the suggestion overlay.
  ///
  /// The overlay mirrors what was typed, so this is also how a *new* tag gets
  /// in — the alternative (Enter) is covered by its own skipped test.
  ///
  /// [fieldIsTheBox] is for a field whose key sits on the `AutoSuggestBox`
  /// itself (the labwork editor's lab-name box) rather than on a wrapper that
  /// contains one.
  static Future<String> pickTag(
    WidgetTester tester,
    Key fieldKey,
    String text, {
    bool fieldIsTheBox = false,
  }) async {
    final box = find.descendant(
      of: find.byKey(fieldKey),
      matching: find.byType(AutoSuggestBox<String>),
      matchRoot: fieldIsTheBox,
    );
    await E2E.tap(tester, box, description: 'the tag field');
    await tester.enterText(box, text);
    await E2E.settle(tester, frames: 8);

    // The suggestions are a plain `OverlayEntry`, *not* a `Flyout` — the fluent
    // overlay is inserted into the root overlay directly. Match the row's text
    // by widget predicate so the box's own `EditableText` (which now holds the
    // same string) cannot match.
    final suggestion = find.byWidgetPredicate(
      (widget) => widget is Text && widget.data == text,
    );
    try {
      await E2E.waitFor(tester, suggestion,
          description: 'the "$text" suggestion');
    } catch (_) {
      final shown = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .where((t) => t.isNotEmpty)
          .join(' | ');
      fail('No suggestion for "$text". On screen: $shown');
    }
    await tester.tap(suggestion.last);
    await E2E.settle(tester, frames: 8);
    return text;
  }

  // ------------------------------------------------------------- records

  /// Opens the new-patient panel and waits for it. Types nothing — that is what
  /// the "untouched draft" test needs.
  static Future<void> openNewPatientPanel(WidgetTester tester) async {
    await E2E.tap(tester, find.byKey(WK.btnNewPatient),
        description: 'the new patient button');
    await E2E.waitFor(tester, find.byKey(WK.fieldPatientName),
        description: 'the patient panel');
  }

  /// Creates and saves a patient, then closes the panel.
  static Future<String> createPatient(
    WidgetTester tester, {
    String? name,
    String? yearOfBirth,
    String? email,
    String? phone,
    String? address,
  }) async {
    final patientName = name ?? stamp('e2e patient');
    // The button lives on the patients screen, so tests that started somewhere
    // else (the dashboard, the calendar) do not have to navigate first.
    await openPatients(tester);
    await openNewPatientPanel(tester);
    await tester.enterText(find.byKey(WK.fieldPatientName), patientName);
    if (yearOfBirth != null) {
      await tester.enterText(find.byKey(WK.fieldPatientYOB), yearOfBirth);
    }
    if (email != null) {
      await tester.enterText(find.byKey(WK.fieldPatientEmail), email);
    }
    if (phone != null) {
      await tester.enterText(find.byKey(WK.fieldPatientPhone), phone);
    }
    if (address != null) {
      await tester.enterText(find.byKey(WK.fieldPatientAddress), address);
    }
    await E2E.settle(tester);
    await save(tester);
    await closePanel(tester);
    return patientName;
  }

  /// Opens the patient named [name] from the patients list.
  ///
  /// The list is paged (10 rows at a time) and sorted by title, so a clinic with
  /// more than a page of patients will not be showing the row that was just
  /// created. When it is not there, search for it the way a user would.
  ///
  /// The row is found as the `ListTile` the name sits in, but the tap goes to the
  /// name **inside** it: a selectable row toggles selection when the row itself
  /// is pressed, while the app's own tap target — the one that opens the panel —
  /// is the name. And `find.text(name)` on its own would also match the copy the
  /// search box holds (an `EditableText` with the same string), which comes first
  /// in the tree: tapping that focused the search field and the panel never
  /// opened (a 60s timeout, and only in a full run, where the list is long enough
  /// to need the search).
  static Future<void> openPatient(WidgetTester tester, String name) async {
    final row = find.ancestor(
      of: find.text(name),
      matching: find.byType(ListTile),
    );
    final inRow = find.descendant(of: row, matching: find.text(name));
    await E2E.settle(tester, frames: 5);
    if (row.evaluate().isEmpty) {
      // Start from an empty box: a previous search may still be filtering the
      // list, and the box's own text is matched by `find.text(name)` as well.
      await tester.enterText(find.byKey(WK.listSearch), '');
      await E2E.settle(tester, frames: 10);
      await tester.enterText(find.byKey(WK.listSearch), name);
      // The list re-reads through the engine, so wait for the row instead of
      // assuming one settle is enough (a 60s timeout follows otherwise).
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (DateTime.now().isBefore(deadline) && inRow.evaluate().isEmpty) {
        await tester.pump(const Duration(milliseconds: 200));
      }
    }
    await E2E.tapFirst(tester, inRow, description: 'the "$name" row');
    await E2E.waitFor(tester, find.byKey(WK.fieldPatientName),
        description: 'the "$name" panel');
  }

  // --------------------------------------------------------- appointments

  /// A day the calendar shows in every format, and never today: today's cell is
  /// the *selected* one, so it carries `calendarSelected` instead of its date
  /// key.
  static DateTime tomorrow() => DateTime.now().add(const Duration(days: 1));

  /// Makes [day] the day the calendar's agenda is showing.
  ///
  /// Idempotent by necessity: `table_calendar` builds the *selected* cell from
  /// `selectedBuilder`, so that one carries [WK.calendarSelected] instead of its
  /// date key — asking for the day that is already selected has nothing to tap.
  static Future<void> selectDay(WidgetTester tester, DateTime day) async {
    await E2E.settle(tester, frames: 5);
    if (selectedDay(tester) == _dateKey(day)) return;
    try {
      await E2E.tap(tester, find.byKey(WK.calendarDay(day)),
          description: 'the day cell', timeout: const Duration(seconds: 20));
    } catch (_) {
      // A day that is not on the current page looks exactly like a missing key.
      // Say which days are on screen, so the next occurrence explains itself: the
      // calendar shows one week from the start of the week containing today
      // (`CalendarFormat.week`), so **yesterday is often not there** — which is
      // how `calendar 03` spent 80s on a day the page never held.
      final visible = tester
          .widgetList<DayCell>(find.byType(DayCell))
          .map((cell) => _dateKey(cell.day))
          .toList();
      fail(
          'The day cell for ${_dateKey(day)} is not on screen. The page shows: '
          '${visible.join(', ')}');
    }
    await E2E.waitFor(tester, find.byKey(WK.calendarSelected),
        description: 'the selected day cell');
    expect(selectedDay(tester), _dateKey(day),
        reason: 'tapping the day cell did not select it');
  }

  /// The date the calendar has selected, as `yyyy-mm-dd`, or `null` when the
  /// week on screen has no selection at all.
  static String? selectedDay(WidgetTester tester) {
    final cell = find.byKey(WK.calendarSelected);
    if (cell.evaluate().isEmpty) return null;
    return _dateKey(tester.widget<DayCell>(cell).day);
  }

  static String _dateKey(DateTime day) => '${day.year}-${day.month}-${day.day}';

  /// How many appointments [day] is showing, or `null` when it has none at all
  /// (with no appointments the badge is not drawn).
  static int? dayCount(WidgetTester tester, DateTime day) {
    final badge = find.byKey(WK.calendarDayCount(day));
    if (badge.evaluate().isEmpty) return null;
    final number = tester.widget<Txt>(
      find.descendant(of: badge, matching: find.byType(Txt)),
    );
    return int.tryParse(number.data ?? '');
  }

  /// Opens the new-appointment panel for the day the calendar has selected.
  static Future<void> openNewAppointmentPanel(WidgetTester tester) async {
    await E2E.tap(tester, find.byKey(WK.btnNewAppointment),
        description: 'the new appointment button');
    await E2E.waitFor(tester, find.byKey(WK.fieldAppointmentPreOpNotes),
        description: 'the appointment panel');
  }

  /// Picks the patient in an open appointment panel.
  ///
  /// The picker is a suggestion field (`PatientPicker` → `TagInputWidget`,
  /// strict, limited to one): the patient's name is one of its suggestions, so
  /// picking it is enough — no Enter needed (see `todo.md` §6.2).
  static Future<void> pickPatient(WidgetTester tester, String name) =>
      pickTag(tester, WK.fieldPatient, name);

  /// Books [patientName] on [day] (tomorrow by default) and closes the panel.
  static Future<void> createAppointment(
    WidgetTester tester, {
    required String patientName,
    DateTime? day,
    String? price,
    String? preOpNotes,
  }) async {
    await openCalendar(tester);
    await selectDay(tester, day ?? tomorrow());
    await openNewAppointmentPanel(tester);
    await pickPatient(tester, patientName);
    if (preOpNotes != null) {
      await enterField(tester, WK.fieldAppointmentPreOpNotes, preOpNotes,
          scrollable: _panelBody(WK.fieldAppointmentPreOpNotes));
    }
    if (price != null) {
      // The price is on the operative-details tab — the panel opens on the
      // appointment tab, and only the selected tab is built.
      await openPanelTab(tester, 'operativeDetails');
      await enterField(tester, WK.fieldAppointmentPrice, price,
          scrollable: _panelBody(WK.fieldAppointmentPostOpNotes));
    }
    await E2E.settle(tester);
    await save(tester);
    await closePanel(tester);
  }

  /// The scrollable the open panel's body lives in, reached through a field that
  /// is on screen — so this can never grab the screen behind the panel.
  static Finder _panelBody(Key through) => find
      .ancestor(of: find.byKey(through), matching: find.byType(Scrollable))
      .first;

  /// Opens the appointment on the day's list.
  ///
  /// [patient] narrows it to that patient's tile: the tests share one database,
  /// so the day they book on usually carries appointments from earlier tests
  /// too, and "the first tile" is then not the one under test.
  ///
  /// The agenda is a `ListView.builder`, so a tile below the fold **is not
  /// built** and no finder can see it. A full run books several appointments on
  /// the same day, so the list is scrolled until the wanted tile exists —
  /// without this, a test that books late in the run waits 60 s for a tile the
  /// list never built (`patient_panel 06` did exactly that).
  ///
  /// The cards open on press-and-hold in this app; a tap is tried first and the
  /// hold is the fallback, so a change to plain taps does not break the suite.
  static Future<void> openAppointmentTile(
    WidgetTester tester, {
    String? patient,
  }) async {
    final tile = patient == null
        ? find.byKey(WK.calendarAppointmentTile)
        : find.ancestor(
            of: find.text(patient),
            matching: find.byKey(WK.calendarAppointmentTile),
          );
    final panel = find.byKey(WK.fieldAppointmentPreOpNotes);
    final description = patient == null
        ? "the day's appointment tile"
        : "the tile for \"$patient\"";

    for (var scrolls = 0; scrolls < 12 && tile.evaluate().isEmpty; scrolls++) {
      // The list to scroll is the agenda itself, found through the calendar
      // widget: anchoring on a *tile* cannot work when the day is long enough
      // that no tile is built at all, which is what a full run produces.
      final agenda = find
          .descendant(
            of: find.byType(WeekAgendaCalendar),
            matching: find.byType(Scrollable),
          )
          .last;
      if (agenda.evaluate().isEmpty) break; // the day has no tiles at all
      await tester.drag(agenda, const Offset(0, -240));
      await E2E.settle(tester, frames: 6);
    }

    await E2E.waitFor(tester, tile,
        description: '$description (of '
            '${find.byKey(WK.calendarAppointmentTile).evaluate().length} built)');
    // The agenda is the bottom half of the screen; scroll the tile in so the tap
    // cannot land on the day title bar instead of the tile.
    await tester.ensureVisible(tile.first);
    await E2E.settle(tester);
    await tester.tap(tile.first);
    await E2E.settle(tester, frames: 8);
    if (panel.evaluate().isEmpty) {
      await tester.longPress(tile.first);
      await E2E.settle(tester, frames: 10);
    }
    await E2E.waitFor(tester, panel, description: 'the appointment panel');
  }

  // ------------------------------------------------------------- dashboard

  /// Opens the dashboard (the shell's landing screen).
  static Future<void> openDashboard(WidgetTester tester) => openRoute(
        tester,
        'dashboard',
        find.byKey(WK.dashboardScreen),
        description: 'the dashboard screen',
      );

  /// What a counting square shows, or `null` when that square is not on screen.
  ///
  /// The key sits on the number itself (`Text`, or the `MoneyDisplay` wrapping
  /// one), so this reads whatever that square is showing.
  static String? squareText(WidgetTester tester, String id) {
    final count = find.byKey(WK.dashboardCount(id));
    if (count.evaluate().isEmpty) return null;
    final texts = find.descendant(
      of: count,
      matching: find.byType(Text),
      matchRoot: true,
    );
    if (texts.evaluate().isEmpty) return null;
    return tester.widget<Text>(texts.first).data;
  }

  /// The number a counting square shows (its top squares hold plain integers).
  static int? squareCount(WidgetTester tester, String id) =>
      int.tryParse((squareText(tester, id) ?? '').trim());

  /// How many rows one of the dashboard's *list* squares is showing.
  static int squareItems(WidgetTester tester, String id) => find
      .descendant(
        of: find.byKey(WK.dashboardSquare(id)),
        matching: find.byType(ListTile),
      )
      .evaluate()
      .length;

  /// Taps a list square's own action, which navigates to the screen it counts.
  ///
  /// Only the *list* squares have that button; the top squares are read-only.
  /// The squares live in a horizontally scrolling row, so the button has to be
  /// scrolled into view first — otherwise the tap silently misses
  /// (`warnIfMissed`) and the navigation never happens.
  static Future<void> tapSquare(WidgetTester tester, String id) async {
    final button = find.descendant(
      of: find.byKey(WK.dashboardSquare(id)),
      matching: find.byType(IconButton),
    );
    await tester.ensureVisible(button.first);
    await E2E.settle(tester, frames: 5);
    await E2E.tap(tester, button, description: 'the "$id" square action');
    await E2E.settle(tester, frames: 10);
  }

  // -------------------------------------------------------------- labworks

  /// Opens the labworks screen (its command bar holds the new-labwork button).
  static Future<void> openLabworks(WidgetTester tester) => openRoute(
        tester,
        'labworks',
        find.byKey(WK.btnNewLabwork),
        description: 'the labworks screen',
      );

  /// The labworks table row whose patient cell names [patient].
  ///
  /// Rows are `HoverButton`s with plain text cells, so the row is the button
  /// that contains the patient's name.
  static Finder labworkRow(String patient) => find.ancestor(
        of: find.text(patient),
        matching: find.byType(HoverButton),
      );

  /// The status the labworks table shows for [patient]'s row, or `null` when
  /// the row is not on screen.
  ///
  /// The cell capitalises the label ("⏳ Waiting for lab"), so the comparison is
  /// case-insensitive.
  static String? labworkStatus(WidgetTester tester, String patient) {
    final row = labworkRow(patient);
    if (row.evaluate().isEmpty) return null;
    final texts = tester
        .widgetList<Text>(find.descendant(of: row, matching: find.byType(Text)))
        .map((t) => t.data?.toLowerCase() ?? '')
        .toList();
    for (final status in [
      'waitingForLab',
      'undelivered',
      'receivedAndDelivered'
    ]) {
      final label = txt(status).toLowerCase();
      if (texts.any((text) => text.contains(label))) return status;
    }
    return null;
  }

  /// Switches the labworks table to its "show done" view, where rows that have
  /// been received (and are therefore no longer due) are listed.
  static Future<void> showDoneLabworks(WidgetTester tester) async {
    await E2E.tapFirst(tester, find.text(txt('showDone')),
        description: 'the show-done toggle');
    await E2E.settle(tester, frames: 8);
  }

  /// Attaches lab work to the appointment whose panel is open.
  ///
  /// The labwork section lives on the panel's operative-details tab and starts
  /// behind an "add labwork" link.
  static Future<void> attachLabwork(
    WidgetTester tester, {
    required String lab,
    String? orderNotes,
    bool received = false,
  }) async {
    await openPanelTab(tester, 'operativeDetails');
    await E2E.tapFirst(tester, find.text(txt('addLabwork')),
        description: 'the add-labwork link');
    await E2E.waitFor(tester, find.byKey(WK.fieldLabworkLabName),
        description: 'the labwork editor');

    await enterField(tester, WK.fieldLabworkLabName, lab,
        scrollable: panelBody());
    if (orderNotes != null) {
      await enterField(tester, WK.fieldLabworkOrderNotes, orderNotes,
          scrollable: panelBody());
    }
    if (received) {
      await E2E.tap(tester, find.byKey(WK.fieldLabworkReceived),
          description: 'the labwork-received checkbox');
    }
    await E2E.settle(tester);
    await _parkAfterTyping(tester);
  }

  /// Opens the labworks screen's own panel and links [patient]'s visit.
  ///
  /// The panel asks for a patient first, then for one of their appointments —
  /// a `ComboBox` that only exists once the patient is picked. It drives a
  /// panel rather than a record, which is what the "new labwork" button is.
  static Future<void> openNewLabworkPanel(
    WidgetTester tester, {
    required String patient,
  }) async {
    await openLabworks(tester);
    await E2E.tap(tester, find.byKey(WK.btnNewLabwork),
        description: 'the new labwork button');
    await E2E.waitFor(tester, find.byKey(WK.fieldPatient),
        description: 'the labwork panel');
    await pickPatient(tester, patient);

    // One visit means exactly one option; `ComboBoxItem` matches only the
    // dropdown's own rows, so the placeholder cannot be tapped by mistake.
    await E2E.tap(tester, find.byKey(WK.fieldLabworkAppointment),
        description: 'the appointment picker');
    await E2E.waitFor(tester, find.byType(ComboBoxItem<String>),
        description: 'the appointment options');
    await tester.tap(find.byType(ComboBoxItem<String>).first);
    await E2E.settle(tester, frames: 8);
    await E2E.waitFor(tester, find.byKey(WK.fieldLabworkLabName),
        description: 'the labwork editor');
  }

  /// Let fluent's own text work finish before the panel it lives in goes away.
  ///
  /// `AutoSuggestBox` schedules a post-frame `_updateLocalItems()` from its text
  /// listener and calls `setState` from it; a panel disposed in the same frame
  /// leaves that call landing on a dead element (the harness filters that one
  /// out — see `E2E.installKnownFlutterIssueFilters`). Blurring first matters for
  /// a second reason: an open suggestion overlay is a root `OverlayEntry` drawn
  /// over the panel, so the *next* tap (usually the panel's Save button) lands on
  /// the overlay and is reported only as `warnIfMissed` — the save silently never
  /// happens. Losing focus is what fluent dismisses it on.
  static Future<void> _parkAfterTyping(WidgetTester tester) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(seconds: 1));
  }

  /// Opens the labwork panel for the row naming [patient].
  static Future<void> openLabworkRow(
      WidgetTester tester, String patient) async {
    final row = labworkRow(patient);
    await E2E.waitFor(tester, row,
        description: 'the labwork row for "$patient"');
    await E2E.tapFirst(
        tester, find.descendant(of: row, matching: find.text(patient)),
        description: 'the "$patient" labwork row');
    await E2E.waitFor(tester, find.byKey(WK.fieldLabworkLabName),
        description: 'the labwork panel');
  }

  /// Picks the lab-name suggestion [lab] in the open labwork panel.
  static Future<String> pickLabName(WidgetTester tester, String lab) =>
      pickTag(tester, WK.fieldLabworkLabName, lab, fieldIsTheBox: true);

  /// Saves the labwork panel and waits for it to close.
  ///
  /// That panel draws its own save button (its footer is turned off), so the
  /// shared `save()` — which reads `WK.panelSave` — cannot be used: there is no
  /// such button here. Its own button saves through the panel, and is enabled by
  /// the same `hasUnsavedChanges` the host's button would read.
  static Future<void> saveLabworkPanel(WidgetTester tester) async {
    await _parkAfterTyping(tester);
    await _tapSave(tester, find.text(txt('save')));
    await E2E.waitForGone(tester, find.byKey(WK.fieldLabworkLabName),
        description: 'the labwork panel (saved and closed)');
  }

  // -------------------------------------------------------------- expenses

  /// Opens the expenses screen (its command bar holds "add supplier").
  static Future<void> openExpenses(WidgetTester tester) => openRoute(
        tester,
        'expenses',
        find.byKey(WK.btnNewSupplier),
        description: 'the expenses screen',
      );

  /// Creates a supplier through the screen's dialog.
  static Future<void> createSupplier(WidgetTester tester, String name) async {
    await openExpenses(tester);
    await E2E.tap(tester, find.byKey(WK.btnNewSupplier),
        description: 'the add-supplier button');
    await E2E.waitFor(tester, find.byType(ContentDialog),
        description: 'the add-supplier dialog');
    await tester.enterText(
      find.descendant(
        of: find.byType(ContentDialog),
        matching: find.byType(TextBox),
      ),
      name,
    );
    await E2E.settle(tester);
    await confirmDialog(tester);
  }

  /// Confirms the open dialog (its action row holds the Save button).
  ///
  /// Fluent puts the primary action *last* ([last]), and the notes dialogs have
  /// their Cancel first and a delete/archive second, so a bare `.first` would
  /// press Cancel. The existing callers' dialogs happen to have the primary
  /// action first, which is why the default reads that way.
  static Future<void> confirmDialog(
    WidgetTester tester, {
    bool last = false,
  }) async {
    final save = find.descendant(
      of: find.byType(ContentDialog),
      matching: find.byType(FilledButton),
    );
    await E2E.tapFirst(tester, last ? save.last : save,
        description: 'the dialog save button');
    await E2E.waitForGone(tester, find.byType(ContentDialog),
        description: 'the dialog');
  }

  /// The supplier row on the expenses list.
  static Finder supplierRow(String name) =>
      find.ancestor(of: find.text(name), matching: find.byType(ListTile));

  /// Opens the orders panel of the supplier named [name].
  ///
  /// The name sits inside a `FlyoutTarget` in the tile's title, but that wrapper
  /// takes no gestures of its own: pressing the name is what opens the panel. The
  /// row's own overflow menu is a different target (the leading icon button).
  static Future<void> openSupplier(WidgetTester tester, String name) async {
    final row = supplierRow(name);
    await E2E.waitFor(tester, row, description: 'the "$name" supplier row');
    await E2E.tapFirst(
      tester,
      find.descendant(of: row, matching: find.text(name)),
      description: 'the "$name" supplier row',
    );
    await E2E.waitFor(tester, find.byKey(WK.btnAddOrder),
        description: "the supplier's orders panel");
  }

  /// Adds one order to the open supplier and fills its money fields.
  static Future<void> addOrder(
    WidgetTester tester, {
    String? cost,
    String? paid,
  }) async {
    await E2E.tap(tester, find.byKey(WK.btnAddOrder),
        description: 'the add-order button');
    await E2E.waitFor(tester, find.byKey(WK.fieldOrderCost),
        description: 'the new order row');
    if (cost != null) {
      await enterField(tester, WK.fieldOrderCost, cost,
          scrollable: panelBody());
    }
    if (paid != null) {
      await enterField(tester, WK.fieldOrderPaid, paid,
          scrollable: panelBody());
    }
    await E2E.settle(tester);
  }

  /// Flips the open order's processed flag (its menu's first item: "mark as
  /// paid" / "mark as due").
  static Future<void> flipOrderProcessed(WidgetTester tester) async {
    final menu = find.byKey(WK.orderMenu);
    await tester.ensureVisible(menu.first);
    await E2E.settle(tester, frames: 5);
    // The keyed widget is the `IconButton`'s outer `FlyoutTarget` on some paths
    // and the button itself on others; its icon is the same either way.
    await E2E.tap(tester, find.byIcon(WindowsIcons.more),
        description: "the order's menu");
    await E2E.waitFor(tester, find.byType(MenuFlyoutItem),
        description: "the order's menu items");
    await E2E.tapFirst(tester, find.byType(MenuFlyoutItem),
        description: 'the first menu item (mark as paid / mark as due)');
    await E2E.settle(tester, frames: 8);
  }

  /// Switches the orders panel to one of its two tabs (they are titled here).
  static Future<void> openOrdersTab(WidgetTester tester, String title) async {
    await E2E.tapFirst(tester, find.text(txt(title)),
        description: 'the "$title" tab');
    await E2E.settle(tester, frames: 8);
  }

  /// The icon a panel gives the tab titled [title].
  ///
  /// A panel draws its tabs as **icons only**: `Panel.showTitles` defaults
  /// to `false`, so the label the app passes to `PanelTab` is never rendered
  /// (only expenses and labworks turn titles on). Switching tabs therefore means
  /// tapping the icon the panel built that tab with.
  static const tabIcons = <String, IconData>{
    'patientDetails': FluentIcons.medication_admin,
    'dentalNotes': FluentIcons.teeth,
    'patientPage': FluentIcons.q_r_code,
    'appointment': WindowsIcons.calendar,
    'appointments': WindowsIcons.calendar,
    'operativeDetails': FluentIcons.medical_care,
    'gallery': FluentIcons.camera,
  };

  /// The tab strip's match for the tab titled [title].
  static Finder tabIcon(String title) => find.descendant(
        of: find.byType(TabView),
        matching: find.byIcon(tabIcons[title]!),
      );

  /// Switches the open panel to the tab titled [title] (`txt('gallery')`
  /// and friends).
  static Future<void> openPanelTab(WidgetTester tester, String title) async {
    await E2E.tapFirst(tester, tabIcon(title), description: 'the "$title" tab');
    await E2E.settle(tester, frames: 8);
  }

  /// Records [condition] on a tooth of whatever teeth chart is on screen.
  ///
  /// Tapping the tooth opens the state wheel (a flyout on a wide screen, a
  /// dialog on a narrow one — `ToothStateWheel._open`), and picking a condition
  /// there stores it in the open draft. The condition is a localization key from
  /// `tx_options.dart` (`filling`, `caries`, `extraction`, `crown`…).
  static Future<void> setToothCondition(
    WidgetTester tester,
    String iso,
    String condition,
  ) async {
    await E2E.tap(tester, find.byKey(WK.tooth(iso, selected: false)),
        description: 'tooth $iso');
    // `txt()` is rendered by `Txt`, which is a `Text` that builds another
    // `Text`: a label finder matches twice, so take the first.
    await E2E.tapFirst(tester, find.text(txt(condition)),
        description: 'the "$condition" condition');
    await E2E.settle(tester, frames: 8);
  }

  // ---------------------------------------------------------------- notes

  /// Opens the notes board.
  static Future<void> openNotes(WidgetTester tester) => openRoute(
        tester,
        'notes',
        find.byKey(WK.btnNewNote),
        description: 'the notes screen',
      );

  /// The id of the board column named [name].
  ///
  /// A column is keyed by its record id, not by its name: the name is the
  /// header's text, and another widget on the board can show the same string.
  /// The uncategorized column is the exception — it collects the notes with no
  /// column and is not a stored row at all, so it has no record id.
  static Future<String> columnId(String name) async {
    if (name == txt('uncategorized')) return uncategorizedColumnId;
    for (final column in notes.columns) {
      if (column.columnName == name) return column.id;
    }
    throw StateError('no board column named "$name"');
  }

  /// Waits until the board's columns include [name] (and returns its id).
  ///
  /// A column write lands asynchronously: the editor dialog closes as soon as
  /// it has started the write, so asking the store — or the board — in the next
  /// frame can still see the old state.
  static Future<String> waitForColumn(
    WidgetTester tester,
    String name, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      for (final column in notes.columns) {
        if (column.columnName == name) return column.id;
      }
      await tester.pump(const Duration(milliseconds: 200));
    }
    fail('The board never showed a column named "$name".');
  }

  /// Waits until the board's columns no longer include [name].
  static Future<void> waitForColumnGone(
    WidgetTester tester,
    String name, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (!await columnExists(name)) return;
      await tester.pump(const Duration(milliseconds: 200));
    }
    fail('The board never dropped the column named "$name".');
  }

  /// Whether the board has a column named [name].
  ///
  /// A renamed-away or archived column cannot be looked up by name at all, so
  /// "it is gone" is a question about the columns the board reads, not a finder.
  static Future<bool> columnExists(String name) async =>
      notes.columns.any((column) => column.columnName == name);

  /// The board column named [name] — its root, so a note card inside it is a
  /// descendant.
  static Future<Finder> boardColumn(String name) async =>
      find.byKey(WK.columnRoot(await columnId(name)));

  /// The tappable header of the board column named [name] (its editor dialog).
  static Future<Finder> columnHeader(String name) async =>
      find.byKey(WK.columnHeader(await columnId(name)));

  /// The notes the board would show, read through the store's own filter.
  ///
  /// The board does not page or sort its rows itself: it reads the store's
  /// `filtered`, which applies `filterByAccountId`, `showIncoming` and
  /// `sortDirection` — and the permission rule on top. So this sets those three
  /// the way the board's controls would and reads what the board would draw.
  static List<Note> boardNotes({
    required String filterByAccountId,
    required bool showIncoming,
    required int sortDirection,
  }) {
    notes.filterByAccountId(filterByAccountId);
    notes.showIncoming(showIncoming);
    notes.sortDirection(sortDirection);
    return notes.filtered.values.toList();
  }

  /// The note the board would show for [title], read exactly the way the board
  /// reads it — so a note the board drops (archived, filtered) is `null` here
  /// as well.
  static Future<Note?> storedNote(String title) async {
    final board = boardNotes(
      filterByAccountId: '',
      showIncoming: false,
      sortDirection: 1,
    );
    for (final note in board) {
      if (note.title == title) return note;
    }
    return null;
  }

  /// The card of the note with [id].
  ///
  /// A card is keyed by its note id, and that is the only handle that survives
  /// the card being expanded: an expanded card replaces its title label with an
  /// editable field, so a finder that matched the title text stops seeing it.
  static Finder noteCardById(String id) => find.byKey(Key(id));

  /// The stored note titled [title] — what the board would show under that
  /// name — or a failure naming the title.
  static Future<Note> noteNamed(String title) async {
    final note = await storedNote(title);
    expect(note, isNotNull, reason: 'no stored note titled "$title"');
    return note!;
  }

  /// Waits until the note titled [title] is stored, and returns it.
  ///
  /// The dialog closes as soon as it has started the write, so the record is not
  /// there in the next frame.
  static Future<Note> waitForNote(
    WidgetTester tester,
    String title, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final note = await storedNote(title);
      if (note != null) return note;
      await tester.pump(const Duration(milliseconds: 200));
    }
    fail('The note "$title" was never stored.');
  }

  /// Brings the card of the note with [id] into view — both axes.
  ///
  /// A column's cards are a `ListView.builder`: below that list's viewport they
  /// are **not built at all**, so no finder can see them and `ensureVisible`
  /// cannot rescue them (this is what a full-suite run hit: by the time the
  /// attachments group ran, its new note was under every note the earlier tests
  /// had left on the board). The board is scrolled horizontally first — its own
  /// `Row` runs past the right edge of the window — and then the column's list
  /// vertically, which builds the card as it scrolls.
  static Future<void> revealNoteCard(WidgetTester tester, String id) async {
    final columnId = notes.get(id)?.columnID ?? uncategorizedColumnId;
    final column = find.byKey(WK.columnRoot(columnId));
    await revealInBoard(tester, column);
    final card = noteCardById(id);
    if (card.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        card,
        200,
        scrollable: find
            .descendant(of: column, matching: find.byType(Scrollable))
            .first,
      );
      await E2E.settle(tester, frames: 5);
    }
    await tester.ensureVisible(card);
    await E2E.settle(tester, frames: 5);
  }

  /// Brings [target] into the board's viewport.
  ///
  /// The board puts its columns in a `Row` inside a horizontal scroll view, so
  /// once there are more than a handful of columns the rest are laid out *past
  /// the right edge of the window* — `tester.tap` then derives an offset that
  /// hit-tests nothing, and the tap silently does nothing (`warnIfMissed` only
  /// prints). A built-but-offscreen widget is visible to a finder, so
  /// `scrollUntilVisible` is no help: the scroll has to be measured and driven.
  static Future<void> revealInBoard(WidgetTester tester, Finder target) async {
    // The board's own scrollable is the shallowest one: every column carries a
    // `ListView` of its own inside it, so this has to take the *first* match.
    final board = find
        .descendant(
          of: find.byKey(WK.notesBoard),
          matching: find.byType(Scrollable),
        )
        .first;
    // The scroll position is driven directly: a `tester.drag` here would land on
    // whatever column happens to be under the pointer, and a drag the card does
    // not claim does not scroll the board.
    for (var attempt = 0; attempt < 10; attempt++) {
      final viewport = tester.getRect(find.byKey(WK.notesBoard));
      final rect = tester.getRect(target.first);
      if (rect.left >= viewport.left + 8 && rect.right <= viewport.right - 8) {
        return;
      }
      final position = tester.state<ScrollableState>(board).position;
      final next = (position.pixels + rect.left - viewport.left - 40)
          .clamp(position.minScrollExtent, position.maxScrollExtent);
      if (next == position.pixels) return; // Already at that end.
      position.jumpTo(next);
      await E2E.settle(tester, frames: 5);
    }
  }

  /// Taps something on the board, bringing it into view first.
  static Future<void> _tapInBoard(
    WidgetTester tester,
    Finder target, {
    required String description,
  }) async {
    await revealInBoard(tester, target);
    await E2E.tap(tester, target, description: description);
  }

  /// Adds a column titled [title] with the board's own add-column button.
  static Future<void> addColumn(WidgetTester tester, String title) async {
    await _tapInBoard(tester, find.byKey(WK.btnAddColumn),
        description: 'the add-column button');
    await E2E.waitFor(tester, find.byKey(WK.fieldColumnTitle),
        description: 'the column dialog');
    await tester.enterText(find.byKey(WK.fieldColumnTitle), title);
    await E2E.settle(tester);
    await confirmDialog(tester, last: true);
    await waitForColumn(tester, title);
  }

  /// Opens the dialog behind the header of the column titled [title].
  static Future<void> _openColumnDialog(
      WidgetTester tester, String title) async {
    await _tapInBoard(
      tester,
      await columnHeader(title),
      description: 'the "$title" column header',
    );
    await E2E.waitFor(tester, find.byKey(WK.fieldColumnTitle),
        description: 'the column dialog');
  }

  /// Renames the column titled [from] to [to].
  static Future<void> renameColumn(
      WidgetTester tester, String from, String to) async {
    await _openColumnDialog(tester, from);
    await tester.enterText(find.byKey(WK.fieldColumnTitle), to);
    await E2E.settle(tester);
    await confirmDialog(tester, last: true);
    await waitForColumn(tester, to);
  }

  /// Archives the column titled [title] — the board's delete, which is
  /// restorable and therefore asks in a flyout first.
  static Future<void> archiveColumn(WidgetTester tester, String title) async {
    await _openColumnDialog(tester, title);
    await E2E.tap(
      tester,
      find.descendant(
        of: find.byType(ContentDialog),
        matching: find.byIcon(WindowsIcons.delete),
      ),
      description: 'the archive-column button',
    );
    await confirmFlyout(tester);
    await E2E.waitForGone(tester, find.byType(ContentDialog),
        description: 'the column dialog');
    await waitForColumnGone(tester, title);
  }

  /// Fills the add/edit note dialog and saves it.
  static Future<void> _fillNoteDialog(
    WidgetTester tester, {
    required String title,
    String? note,
  }) async {
    await E2E.waitFor(tester, find.byKey(WK.fieldNoteTitle),
        description: 'the note dialog');
    await tester.enterText(find.byKey(WK.fieldNoteTitle), title);
    if (note != null) {
      await tester.enterText(find.byKey(WK.fieldNoteText), note);
    }
    await E2E.settle(tester);
    await confirmDialog(tester, last: true);
  }

  /// Creates a note in the column titled [column] (its header's add-note
  /// button), or in the uncategorized column when [column] is null (the command
  /// bar's new-note button).
  static Future<void> createNote(
    WidgetTester tester,
    String title, {
    String? note,
    String? column,
  }) async {
    if (column == null) {
      await E2E.tap(tester, find.byKey(WK.btnNewNote),
          description: 'the new-note button');
    } else {
      await _tapInBoard(
        tester,
        find.descendant(
          of: await boardColumn(column),
          matching: find.byKey(WK.btnAddNote),
        ),
        description: 'the "$column" add-note button',
      );
    }
    await _fillNoteDialog(tester, title: title, note: note);
    // Wait for the *record*, then make its card reachable: the card can be below
    // its column's viewport, and a card that was never built has no finder to
    // wait for.
    final created = await waitForNote(tester, title);
    await revealNoteCard(tester, created.id);
  }

  /// Expands the card of the note titled [title] so its inline fields and
  /// controls exist.
  static Future<void> expandCard(WidgetTester tester, String title) async {
    final id = (await noteNamed(title)).id;
    await revealNoteCard(tester, id);
    await E2E.tap(tester, noteCardById(id),
        description: 'the "$title" note card');
    await E2E.waitFor(
      tester,
      find.descendant(
          of: noteCardById(id), matching: find.byKey(WK.noteCardTitle)),
      description: 'the "$title" card title field',
    );
  }

  /// Edits one of an expanded card's inline fields and saves that field.
  static Future<void> _setCardField(
    WidgetTester tester, {
    required String title,
    required Key field,
    required Key save,
    required String value,
  }) async {
    final id = (await noteNamed(title)).id;
    final card = noteCardById(id);
    await revealNoteCard(tester, id);
    await tester.enterText(
      find.descendant(of: card, matching: find.byKey(field)),
      value,
    );
    await E2E.settle(tester, frames: 5);
    // Each field carries its own save button, and it only appears once the text
    // differs from the stored value — and editing can push it out of the
    // column's viewport.
    final save2 = find.descendant(of: card, matching: find.byKey(save));
    await tester.ensureVisible(save2);
    await E2E.settle(tester, frames: 5);
    await E2E.tap(tester, save2, description: 'the inline save button');
    await E2E.settle(tester, frames: 10);
  }

  /// Renames an expanded card's title through its inline field.
  static Future<void> renameNote(
          WidgetTester tester, String from, String to) async =>
      _setCardField(tester,
          title: from,
          field: WK.noteCardTitle,
          save: WK.btnNoteTitleSave,
          value: to);

  /// Sets an expanded card's body text through its inline field.
  static Future<void> commentNote(
          WidgetTester tester, String title, String comment) async =>
      _setCardField(tester,
          title: title,
          field: WK.noteCardNote,
          save: WK.btnNoteTextSave,
          value: comment);

  /// Archives the note titled [title] through its card's delete button.
  static Future<void> deleteNote(WidgetTester tester, String title) async {
    final id = (await noteNamed(title)).id;
    await expandCard(tester, title);
    final remove = find.descendant(
      of: noteCardById(id),
      matching: find.byKey(WK.btnNoteDelete),
    );
    await tester.ensureVisible(remove);
    await E2E.settle(tester, frames: 5);
    await E2E.tap(tester, remove, description: 'the "$title" delete button');
    await confirmFlyout(tester);
    await E2E.waitForGone(tester, noteCardById(id),
        description: 'the "$title" note card');
  }

  /// Drags the note titled [title] into the column titled [column].
  ///
  /// A card is a `LongPressDraggable`, so the press has to outlast
  /// `kLongPressTimeout` before the pointer may move.
  static Future<void> dragNoteToColumn(
    WidgetTester tester,
    String title,
    String column,
  ) async {
    final card = noteCardById((await noteNamed(title)).id);
    // Only the source needs revealing: the target column is the next one along,
    // and the viewport holds several columns.
    await revealInBoard(tester, card);
    final gesture = await tester.startGesture(tester.getCenter(card));
    await tester.pump(const Duration(milliseconds: 700));
    // A first small move arms the drag; the second lands it on the column.
    await gesture.moveBy(const Offset(20, 20));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveTo(tester.getCenter(await boardColumn(column)));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await E2E.settle(tester, frames: 20);
    await E2E.waitFor(
      tester,
      find.descendant(
          of: await boardColumn(column), matching: find.text(title)),
      description: 'the "$title" note card in "$column"',
    );
  }

  // ------------------------------------------------- scale (perf budgets)

  /// Runs [body] and returns how long it took, printing the measurement.
  ///
  /// A performance test that only asserts "it rendered" measures nothing: the
  /// number has to land in the log, where a regression shows up as a number that
  /// grew rather than as a red test that somebody re-runs until it passes. The
  /// budget asserts are deliberately generous — this is a loaded desktop CI box,
  /// not a stopwatch — and exist to catch an order-of-magnitude change.
  static Future<int> measure(
    String what,
    Future<void> Function() body,
  ) async {
    final watch = Stopwatch()..start();
    await body();
    watch.stop();
    // ignore: avoid_print
    print('⏱️  $what took ${watch.elapsedMilliseconds}ms');
    return watch.elapsedMilliseconds;
  }

  /// A valid PocketBase id for a bulk-seeded row: fifteen alphanumerics.
  ///
  /// Two digits of prefix, nine of the run's stamp and **four of the row index**
  /// — the index has to fit whole: an earlier version folded it with `i % 100`,
  /// which made rows 0 and 100 the *same* id, so a seed of a thousand patients
  /// wrote a hundred (and a seed of two hundred visits collided with itself
  /// exactly the way the insights assertion then reported: 100 rows, not 200).
  static String _bulkId(String prefix, int stamp, int index) =>
      '$prefix${(stamp % 1000000000).toString().padLeft(9, '0')}'
      '${index.toString().padLeft(4, '0')}';

  /// Creates [count] patients with **one** store write.
  ///
  /// [seedPatients] writes a row at a time, which is right for ten and wrong for
  /// a thousand: the write is not what is being measured here, and a thousand
  /// round trips would dominate the test. Names are padded so their order is
  /// index order, so "the tenth row" is predictable.
  static Future<List<String>> seedPatientsBulk(
    WidgetTester? tester, {
    required int count,
    String prefix = 'e2e bulk',
  }) async {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final ids = [for (var i = 0; i < count; i++) _bulkId('e2', stamp, i)];
    patients.setAll([
      for (var i = 0; i < count; i++)
        Patient.fromJson({
          'id': ids[i],
          // The patient's name is **`title`** on the wire (`Patients.title`);
          // `name` is not a field at all, and writing it produced a thousand
          // patients with no name — which `perf_budgets 04` never noticed,
          // because `find.text` also matches the search box holding the very
          // string being searched for.
          'title': '$prefix ${i.toString().padLeft(4, '0')}',
        }),
    ]);
    if (tester != null) await E2E.settle(tester, frames: 5);
    return ids;
  }

  /// Creates [count] visits spread across the current month, with **one** write.
  ///
  /// Every visit is the signed-in account's, so it is on the calendar (the
  /// agenda and the day markers are operator-filtered) and inside the insights
  /// screen's view. Each carries a price, so the revenue aggregation has work to
  /// do. Days are built as `DateTime(year, month, day)` rather than by adding a
  /// `Duration`, so a DST shift cannot move a visit into the neighbouring day.
  static Future<List<String>> seedVisitsThisMonth(
    WidgetTester? tester, {
    required int count,
    required List<String> patientIDs,
    double price = 40,
  }) async {
    final now = DateTime.now();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final ids = [for (var i = 0; i < count; i++) _bulkId('ev', stamp, i)];
    appointments.setAll([
      for (var i = 0; i < count; i++)
        Appointment.fromJson({
          'id': ids[i],
          'patientID': patientIDs[i % patientIDs.length],
          'operatorsIDs': [login.currentAccountID],
          'date': dateToWire(
            DateTime(now.year, now.month, 1 + (i % 27), 9 + (i % 8)),
          ),
          'price': price,
        }),
    ]);
    if (tester != null) await E2E.settle(tester, frames: 5);
    return ids;
  }

  /// Removes every record in [ids] from [store] and returns how many are gone.
  ///
  /// The scale tests seed thousands of rows into the clinic the whole suite
  /// shares, so they hand them back: a leftover thousand patients would change
  /// every later group's paging and search.
  static Future<void> purgeSeeded(
    WidgetTester? tester,
    String store,
    List<String> ids,
  ) async {
    for (final id in ids) {
      if (store == 'patients') {
        patients.purge(id);
      } else if (store == 'notes') {
        notes.purge(id);
      } else {
        appointments.purge(id);
      }
    }
    if (tester != null) await E2E.settle(tester, frames: 5);
  }

  /// The record id of the patient named [name], or `''`.
  ///
  /// `createPatient` returns a *name* (that is what the screens work with), but
  /// the portal's `pid` is the record's **id** — it is the value an appointment
  /// carries in `patientID`, and the public view's rule compares it.
  static Future<String> patientIdOf(String name) async {
    for (final row in patients.docs.values) {
      if (row.title == name) return row.id;
    }
    return '';
  }

  /// Creates one board column and [count] notes in it, with **two** bulk writes.
  ///
  /// The board is the app's heaviest screen: every column is its own list of note
  /// cards, and each card reads its own record. A column *is* a note with
  /// `isColumn` set, which is what makes seeding it a store write rather than a
  /// dialog-driven one. Returns both id sets so the caller can hand them back.
  static Future<({String column, List<String> notes})> seedNotesBulk(
    WidgetTester? tester, {
    required int count,
    String name = 'e2e scale column',
  }) async {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final column = _bulkId('nc', stamp, 0);
    notes.setAll([
      Note.fromJson({
        'id': column,
        'title': name,
        'isColumn': true,
        'columnName': name,
        'order': 0,
        'columnID': '',
      }),
    ]);
    final ids = [for (var i = 0; i < count; i++) _bulkId('nn', stamp, i)];
    notes.setAll([
      for (var i = 0; i < count; i++)
        Note.fromJson({
          'id': ids[i],
          'title': 'e2e note ${i.toString().padLeft(4, '0')}',
          'isColumn': false,
          'columnID': column,
          'order': i.toDouble(),
          'date': dateToWire(DateTime.now()),
        }),
    ]);
    if (tester != null) await E2E.settle(tester, frames: 5);
    return (column: column, notes: ids);
  }

  /// The shareable patient-side link stored on a patient's record, or `''`.
  ///
  /// The link is minted once and *stored* (`Patients.link`), so another device
  /// shows the same one instead of minting a second — which is what makes it
  /// assertable at all: the minting itself calls a shortening server.
  static Future<String> patientLinkOf(String id) async {
    final row = patients.get(id);
    return row?.link ?? '';
  }

  // ------------------------------------------------- crud leftovers

  /// Creates [count] patients **through the store**.
  ///
  /// The list is paged to ten rows, so eleven patients created through the panel
  /// would be eleven panel round-trips of a test that is about paging. The id is
  /// written explicitly: `Model.fromJson` reads the id from the JSON and invents
  /// a random one without it (`/memories/repo/seed-data-contract.md`).
  static Future<List<String>> seedPatients(
    WidgetTester tester, {
    required int count,
    String prefix = 'e2e seeded',
  }) async {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final ids = <String>[];
    for (var i = 0; i < count; i++) {
      // PocketBase ids are exactly 15 alphanumerics (`Invalid record id …;
      // expected [A-Za-z0-9_]{15}`), so the id is built to that width.
      final id = 'e2e${(stamp % 10000000000).toString().padLeft(10, '0')}'
          '${i.toString().padLeft(2, '0')}';
      // Padded, so name order is index order and "the last one" is predictable.
      // `title` is the patient's name on the wire (see `seedPatientsBulk`).
      patients.set(Patient.fromJson({
        'id': id,
        'title': '$prefix ${i.toString().padLeft(2, '0')} $stamp',
      }));
      ids.add(id);
    }
    await E2E.settle(tester, frames: 5);
    return ids;
  }

  /// Opens Deleted Items, the archived-record screen.
  static Future<void> openDeletedItems(WidgetTester tester) => openRoute(
        tester,
        'deletedItems',
        find.text(txt('showAll')),
        description: 'the deleted items screen',
      );

  /// Restores the archived record named [name] from Deleted Items.
  ///
  /// There is no per-row restore button: the screen restores its *selection*
  /// from the command bar, so the row is selected first.
  static Future<void> restoreFromDeletedItems(
      WidgetTester tester, String name) async {
    await E2E.tapFirst(tester, find.text(name), description: 'the "$name" row');
    await E2E.settle(tester, frames: 5);
    await E2E.tapFirst(tester, find.byIcon(WindowsIcons.undo),
        description: 'the restore button');
    await E2E.settle(tester, frames: 20);
  }

  /// Where a row sits vertically — for asserting *order* without reading text.
  static double rowY(WidgetTester tester, Finder finder) =>
      tester.getTopLeft(finder.first).dy;

  /// The string a rendered label shows (the innermost `Text` inside [finder]).
  static String labelText(WidgetTester tester, Finder finder) {
    final inner = find.descendant(of: finder, matching: find.byType(Text));
    final target = inner.evaluate().isEmpty ? finder : inner.first;
    return tester.widget<Text>(target).data ?? '';
  }

  /// Drags the calendar's page view one month forward ([delta] > 0) or back.
  ///
  /// The drag starts on the *selected day cell*: the calendar widget also holds
  /// the day's agenda list, and a drag from its middle lands there instead of on
  /// the month's page view.
  static Future<void> turnCalendarMonth(WidgetTester tester, int delta) async {
    // Anchor on the selected day cell when there is one. Paging away can leave
    // the calendar with *no* selection, so the fallback is a point inside the
    // month grid: the calendar widget's middle is the day's agenda list, and a
    // horizontal drag from there never reaches the month's page view.
    final selected = find.byKey(WK.calendarSelected);
    final Offset from;
    if (selected.evaluate().isNotEmpty) {
      from = tester.getCenter(selected.first);
    } else {
      final rect = tester.getRect(find.byType(WeekAgendaCalendar));
      from = Offset(rect.center.dx, rect.top + 60);
    }
    await tester.dragFrom(from, Offset(delta > 0 ? -700 : 700, 0));
    await E2E.settle(tester, frames: 30);
  }

  /// Switches the calendar between the agenda list and the timeline grid.
  ///
  /// The switch is the date label's button; its icon says which view is coming
  /// (`group_list` for the agenda, `grid_view` for the timeline).
  static Future<void> openCalendarTimeline(WidgetTester tester) async {
    await E2E.tapFirst(tester, find.byIcon(WindowsIcons.group_list),
        description: 'the view switch');
    await E2E.settle(tester, frames: 20);
  }

  /// Sets the open appointment panel's duration through the pill's flyout.
  static Future<void> setDuration(WidgetTester tester, int minutes) async {
    await E2E.tapFirst(tester, find.byType(DurationPill),
        description: 'the duration pill');
    final option = find.text('$minutes ${txt('minutes')}');
    await E2E.waitFor(tester, option,
        description: 'the "$minutes ${txt('minutes')}" option');
    await E2E.tap(tester, option, description: 'the duration option');
    await E2E.settle(tester, frames: 10);
  }

  /// Picks [day] in the panel's date field — a material `showDatePicker`.
  ///
  /// The dialog opens on the date the field holds, so [day] has to be in the
  /// same month for the day number to be on screen at all. Its confirm button is
  /// the dialog's *last* text button (the other is CANCEL) — matching the label
  /// would be a bet on `MaterialLocalizations`.
  static Future<void> changeAppointmentDate(
      WidgetTester tester, DateTime day) async {
    // The panel scrolls: the field has to be on screen before it can be tapped,
    // or the tap lands on nothing and no dialog ever opens.
    await tester.ensureVisible(find.byKey(WK.fieldAppointmentDate));
    await E2E.settle(tester, frames: 5);
    await E2E.tap(tester, find.byKey(WK.fieldAppointmentDate),
        description: 'the date field');
    await E2E.waitFor(tester, find.byType(DatePickerDialog),
        description: 'the date dialog');
    // Scoped to the *dialog*: the panel behind it, and the calendar behind that,
    // also render day numbers, and tapping one of those hit-tests the modal
    // barrier instead of the picker.
    final dialog = find.byType(DatePickerDialog);
    await E2E.tap(
      tester,
      find.descendant(of: dialog, matching: find.text('${day.day}')).first,
      description: 'day ${day.day} in the date dialog',
    );
    await E2E.tap(
      tester,
      find.descendant(of: dialog, matching: find.byType(TextButton)).last,
      description: 'the date dialog confirm',
    );
    await E2E.settle(tester, frames: 20);
  }

  /// Opens the open appointment panel's "other appointments" history flyout.
  ///
  /// The button has no key: it is the `IconButton` around the history icon (the
  /// dental-notes expander draws the same icon, but not inside a button, so the
  /// ancestor lookup is what identifies it).
  static Future<void> openAppointmentHistory(WidgetTester tester) async {
    await E2E.tap(
      tester,
      find
          .ancestor(
            of: find.byIcon(WindowsIcons.history),
            matching: find.byType(IconButton),
          )
          .first,
      description: 'the appointment history button',
    );
    await E2E.settle(tester, frames: 15);
  }

  /// Opens the insights (charts) screen.
  static Future<void> openInsights(WidgetTester tester) => openRoute(
        tester,
        'insights',
        find.text(txt('days')),
        description: 'the insights screen',
      );

  /// Switches the insights charts' period (`days`, `weeks`, `months`, …).
  static Future<void> setStatsInterval(
      WidgetTester tester, String period) async {
    await E2E.tapFirst(tester, find.text(txt(period)),
        description: 'the "$period" period');
    await E2E.settle(tester, frames: 30);
  }

  // ------------------------------------------------------------- accounts

  /// Opens the accounts screen.
  static Future<void> openAccounts(WidgetTester tester) async {
    await openRoute(
      tester,
      'accounts',
      find.byKey(WK.btnNewAccount),
      description: 'the accounts screen',
    );
    // The search box keeps whatever the last test left in it, and the list is
    // filtered by it — a leftover term makes every row finder below lie.
    final search = find.byKey(WK.listSearch);
    if (search.evaluate().isNotEmpty) {
      await tester.enterText(search, '');
      await E2E.settle(tester, frames: 5);
    }
  }

  /// Types [name] into the accounts search box, which filters on name *or* email.
  ///
  /// The rows are a lazy `ListView`, so an account far down the list is not built
  /// at all — searching is what makes its row findable (and there is no paging
  /// here, unlike the patients list).
  static Future<void> searchAccounts(WidgetTester tester, String name) async {
    await tester.enterText(find.byKey(WK.listSearch), name);
    await E2E.settle(tester, frames: 10);
  }

  /// Creates an account through its own panel ([admin] picks the admin button).
  static Future<void> createAccount(
    WidgetTester tester, {
    required String name,
    required String email,
    required String password,
    bool admin = false,
  }) async {
    await E2E.tap(tester, find.byKey(admin ? WK.btnNewAdmin : WK.btnNewAccount),
        description: 'the new-account button');
    await E2E.waitFor(tester, find.byKey(WK.fieldAccountName),
        description: 'the account panel');
    await tester.enterText(find.byKey(WK.fieldAccountName), name);
    await tester.enterText(find.byKey(WK.fieldAccountEmail), email);
    await tester.enterText(find.byKey(WK.fieldAccountPassword), password);
    await E2E.settle(tester);
    await save(tester);
    await closePanel(tester);

    // Creating an account is a *server* write (the user record, then its profile),
    // and the app reports a refusal in a dialog rather than by throwing — so a
    // caller that only waits for the row cannot tell "the server said no" from
    // "the list did not refresh". Say which one it is here.
    if (accountEnabled(name) == null) {
      fail('The account "$name" never reached the accounts store: creating it '
          'did not work (the app shows an error dialog for this — PocketBase '
          'refuses the write, or is unreachable).');
    }
  }

  /// The account row of the account called [name].
  ///
  /// `.first` because a `Txt` renders both itself and an inner `Text`: the ancestor
  /// finder would otherwise return the same `ListTile` twice, and `tap()` refuses
  /// an ambiguous match.
  static Finder accountRow(String name) =>
      find.ancestor(of: find.text(name), matching: find.byType(ListTile)).first;

  /// Opens the panel of the account called [name].
  static Future<void> openAccount(WidgetTester tester, String name) async {
    await searchAccounts(tester, name);
    await E2E.waitFor(tester, accountRow(name),
        description: 'the "$name" account row');
    // The row itself, not its title: a `Txt` renders both itself and an inner
    // `Text`, so a text finder matches twice and cannot be tapped.
    await E2E.tap(tester, accountRow(name),
        description: 'the "$name" account row');
    await E2E.waitFor(tester, find.byKey(WK.fieldAccountName),
        description: 'the "$name" account panel');
  }

  /// Leaves the session: the dashboard's own logout button, then the login screen.
  ///
  /// The stored session is restored on every boot (`login.fromJson` re-activates
  /// the token), so this is the only way to *see* the login screen — `E2E.boot`
  /// waits for the restore now, which means a test that expects to find the login
  /// form has to sign out first. Safe to call from any route, and a no-op when the
  /// login screen is already up.
  static Future<void> signOut(WidgetTester tester) async {
    if (find.byKey(WK.btnLogin).evaluate().isNotEmpty) return;
    // The logout button lives on the dashboard (twice: pane header and command
    // bar), so get there first.
    await openDashboard(tester);
    await E2E.tap(
      tester,
      find.descendant(
        of: find.byKey(WK.dashboardScreen),
        matching: find.byKey(WK.btnLogout),
      ),
      description: 'the logout button',
    );
    await E2E.waitFor(tester, find.byKey(WK.btnLogin),
        description: 'the login screen');
  }

  /// Logs out and signs back in as [email].
  ///
  /// This is the only way to reach a second account's session: permissions are
  /// per account, and the shell rebuilds for whichever one is signed in. Safe to
  /// call from any route — and from the login screen itself (a previous test may
  /// have left the app there, or a failed sign-in may have).
  static Future<void> loginAs(
    WidgetTester tester, {
    required String email,
    required String password,
  }) async {
    await signOut(tester);
    await E2E.enterCredentials(tester,
        server: pbServer, email: email, password: password);
    await E2E.tapLogin(tester);
    await E2E.settle(tester, frames: 30);
  }

  /// Puts the harness's own (admin) session back.
  ///
  /// A test that signed in as a *created* account has to restore this, or every
  /// test after it runs under that account's permissions — `E2E.signIn` returns
  /// straight away when a session is already up, whichever account it is.
  static Future<void> signInAsAdmin(WidgetTester tester) async {
    if (find.byKey(WK.btnLogin).evaluate().isNotEmpty) {
      await E2E.signIn(tester);
      return;
    }
    await loginAs(tester, email: pbEmail, password: pbPassword);
  }

  /// The stored `operate` flag of the account called [name] (`null` if there is
  /// no such account).
  static bool? accountEnabled(String name) {
    for (final record in accounts.list()) {
      if (record.getStringValue('name') == name) {
        return record.getIntValue('operate') == 1;
      }
    }
    return null;
  }

  /// Turns the account called [name] on or off through its panel's own switch.
  ///
  /// A **newly created account is stored disabled** (the panel model defaults
  /// `operate` to `0`), which is why a test that signs in as one has to enable it
  /// first.
  static Future<void> setAccountEnabled(
    WidgetTester tester,
    String name,
    bool enabled,
  ) async {
    if (accountEnabled(name) == enabled) return;
    await openAccount(tester, name);
    await E2E.tap(tester, find.byKey(WK.accountOperates),
        description: 'the enabled switch');
    await E2E.settle(tester, frames: 10);
    await save(tester);
    await closePanel(tester);
  }

  /// Sets a permission row of the open account panel.
  ///
  /// [titleKey] is the row's localization key (`patients`, `notes`, `photos`, …)
  /// and [levelLabel] one of its level labels — the three-level rows use
  /// `restricted` / `personal` / `full`, `notes` uses `personal` / `all`.
  static Future<void> grantPermission(
    WidgetTester tester,
    String titleKey,
    String levelLabel,
  ) async {
    final row = find.byKey(WK.permissionSelector(titleKey));
    await tester.ensureVisible(row);
    await E2E.settle(tester, frames: 5);
    await E2E.tap(tester, row, description: 'the "$titleKey" permission row');
    await E2E.settle(tester, frames: 10);
    await E2E.tap(tester, find.text(levelLabel).last,
        description: 'the "$levelLabel" level');
    await E2E.settle(tester, frames: 10);
  }

  /// Opens the insights-style settings screen (its first card is `currency`).
  static Future<void> openSettings(WidgetTester tester) => openRoute(
        tester,
        'settings',
        find.byKey(WK.settingsItem('currency')),
        description: 'the settings screen',
      );

  /// Scrolls the settings list until card [identifier] is on screen (which is
  /// also what builds it — the cards are lazy list children).
  static Future<void> revealSettingsCard(
    WidgetTester tester,
    String identifier,
  ) async {
    final card = find.byKey(WK.settingsItem(identifier));
    if (card.evaluate().isEmpty) {
      // The list's **own** scrollable — not `find.byType(Scrollable).last`, which
      // is a *text field's* internal `editable` scrollable whenever the screen
      // holds one: a drag on that goes nowhere and `scrollUntilVisible` gives up
      // with `Bad state: No element` (`settings_general 03`, whose cards have to
      // be scrolled to).
      await tester.scrollUntilVisible(
        card,
        150,
        scrollable: find
            .descendant(
              of: find.byKey(WK.settingsList),
              matching: find.byType(Scrollable),
            )
            .first,
        maxScrolls: 40,
      );
    }
    // **Built is not visible.** A card stays built while it sits in the list's
    // cache extent, and a tap on a card outside the viewport only warns — the
    // flyout it was meant to open never appears and the test's next wait times
    // out on it. `tester.ensureVisible` does nothing on this list, so the
    // position is driven directly instead.
    await _scrollIntoSettingsView(tester, card);
    await E2E.settle(tester, frames: 5);
  }

  /// Expands a settings card by its title's localization key — the AI card (and
  /// any other card without a stable identifier) is addressed this way.
  static Future<void> expandSettingsCardByTitle(
    WidgetTester tester,
    String titleKey,
  ) async {
    final header = find.text(txt(titleKey)).first;
    if (header.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        header,
        150,
        scrollable: find.byType(Scrollable).last,
        maxScrolls: 40,
      );
      await E2E.settle(tester, frames: 5);
    }
    await E2E.tap(tester, header, description: 'the "$titleKey" card header');
    await E2E.settle(tester, frames: 15);
  }

  /// The text a settings card's field currently holds (revealing and expanding it
  /// first).
  ///
  /// This is deliberately a *UI* read: a store read of the same setting can
  /// answer with the default until the row has synced down, which makes a test
  /// that compares against it disagree with what the card shows.
  static Future<String> settingsTextValue(
    WidgetTester tester,
    String identifier,
  ) async {
    await revealSettingsCard(tester, identifier);
    final card = find.byKey(WK.settingsItem(identifier));
    final field = find.byKey(Key('${identifier}_text_field'));
    if (field.evaluate().isEmpty) {
      await E2E.tap(tester, card, description: 'the "$identifier" card');
      await E2E.settle(tester, frames: 15);
    }
    await E2E.waitFor(tester, field,
        description: 'the "$identifier" field',
        timeout: const Duration(seconds: 20));
    return tester.widget<CupertinoTextField>(field).controller?.text ?? '';
  }

  /// Expands the settings card [identifier] and commits [value] into its text
  /// field, which is what the card's Save button applies.
  static Future<void> setSettingsText(
    WidgetTester tester,
    String identifier,
    String value,
  ) async {
    await revealSettingsCard(tester, identifier);
    final card = find.byKey(WK.settingsItem(identifier));
    final field = find.byKey(Key('${identifier}_text_field'));
    if (field.evaluate().isEmpty) {
      await E2E.tap(tester, card, description: 'the "$identifier" card');
      await E2E.settle(tester, frames: 15);
    }

    await E2E.waitFor(tester, field,
        description: 'the "$identifier" field',
        timeout: const Duration(seconds: 20));
    await tester.enterText(field, value);
    await E2E.settle(tester, frames: 10);

    // The Save button only exists once the field differs from the stored value,
    // so an absent one usually means "the value is already $value". It also often
    // sits *below* the viewport (expanding the card pushed it out), which makes a
    // default finder blind to it — hence `skipOffstage: false` plus a scroll.
    // (No `.first` before the emptiness check: `evaluate()` on a `.first` finder
    // throws "Bad state: No element" instead of answering "nothing".)
    final saves = find.descendant(
      of: card,
      matching: find.byType(FilledButton, skipOffstage: false),
      skipOffstage: false,
    );
    if (saves.evaluate().isEmpty) {
      fail('The "$identifier" card never offered a Save button after "$value" '
          'was typed into it — the stored value is probably already "$value", '
          'so there was nothing to apply.');
    }
    final save = saves.first;
    await tester.ensureVisible(save);
    await E2E.settle(tester, frames: 10);
    await E2E.tap(tester, save, description: 'the "$identifier" save button');
    await E2E.settle(tester, frames: 20);
  }

  // ------------------------------------------- shell, size and settings

  /// Resizes the window the test drives.
  ///
  /// The app reads its own width from a `LayoutBuilder` (`launch.layoutWidth`),
  /// so this is what moves it between the pane's display modes: expanded above
  /// ~1000, compact below that, and (under 710) the phone layout with the bottom
  /// navigation bar. [E2E.boot] restores 1600x1000 for every test, so a test
  /// that resizes must not rely on it surviving.
  static Future<void> sizeTo(
    WidgetTester tester, {
    required double width,
    double height = 1000,
  }) async {
    tester.view.physicalSize = Size(width, height);
    await E2E.settle(tester, frames: 20);
  }

  /// The window size the harness drives everywhere else.
  static Future<void> fullSize(WidgetTester tester) =>
      sizeTo(tester, width: 1600, height: 1000);

  /// Presses one of the shell's global actions (`notifications`, `theme`,
  /// `sync`, `errors`).
  ///
  /// A *disabled* action ignores a tap silently, which reads as "the button did
  /// nothing" and turns into a mysterious timeout further down the test — the
  /// sync action disables itself while a sync is already running, and while the
  /// session works offline. So this waits for the action to be pressable first,
  /// and fails with the reason if it never is.
  static Future<void> tapGlobalAction(WidgetTester tester, String id) async {
    final action = find.byKey(WK.globalAction(id));
    await E2E.waitFor(tester, action, description: 'the "$id" global action');
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (globalActionDisabled(tester, id)) {
      if (DateTime.now().isAfter(deadline)) {
        fail('The "$id" global action is on screen but disabled — it cannot be '
            'pressed. (The sync action disables itself while a sync runs or '
            'while the session is offline; the errors action does when it has '
            'no errors to show.)');
      }
      await E2E.settle(tester, frames: 5);
    }
    await E2E.tap(tester, action, description: 'the "$id" global action');
    await E2E.settle(tester, frames: 15);
  }

  /// Whether the shell's [id] action is disabled (`onPressed == null`) — the
  /// difference between "offered" and "the user can press it".
  static bool globalActionDisabled(WidgetTester tester, String id) {
    final button = find.descendant(
      of: find.byKey(WK.globalAction(id)),
      matching: find.byType(IconButton),
      skipOffstage: false,
    );
    if (button.evaluate().isEmpty) return false;
    return tester.widget<IconButton>(button.first).onPressed == null;
  }

  /// The number shown on a global action's badge, or `null` when it has none.
  static String? globalActionBadge(WidgetTester tester, String id) {
    final badge = find.descendant(
      of: find.byKey(WK.globalAction(id)),
      matching: find.byType(Text),
    );
    if (badge.evaluate().isEmpty) return null;
    return tester.widget<Text>(badge.first).data;
  }

  /// Opens the notification bell (failing the test if it does not open).
  static Future<void> openBell(WidgetTester tester) async {
    await tapGlobalAction(tester, 'notifications');
    expect(
      find.byType(FlyoutContent),
      findsWidgets,
      reason: 'the notification bell did not open a flyout',
    );
  }

  /// Opens the errors (or reconnect) panel.
  static Future<void> openErrorsPanel(WidgetTester tester) async {
    await tapGlobalAction(tester, 'errors');
    await E2E.settle(tester, frames: 10);
  }

  /// Presses the app bar's back arrow.
  ///
  /// It only exists while `routes.canGoBack` — that is the app's own "there is
  /// somewhere to go back to".
  static Future<void> back(WidgetTester tester) async {
    await E2E.tap(tester, find.byKey(WK.backButton),
        description: 'the back button');
    await E2E.settle(tester, frames: 20);
  }

  /// Expands the settings card [identifier] without touching its value.
  static Future<void> expandSettingsCard(
    WidgetTester tester,
    String identifier,
  ) async {
    await revealSettingsCard(tester, identifier);
    final card = find.byKey(WK.settingsItem(identifier));
    // **"The content exists" is not "the card is open".** fluent's `Expander`
    // lays its content out while it is collapsed (the same behaviour
    // `openServiceSection` works around), so the old early return on the child's
    // existence left the card shut: the tap on its dropdown derived an offset
    // inside the *header*, only warned, and the option was never offered —
    // `localization_rtl 04` waited out a full 60s on it. Height is the test that
    // works, exactly as it does for the service sections.
    if (tester.getSize(card).height > _collapsedSectionHeight) return;
    await E2E.tap(tester, card, description: 'the "$identifier" card');
    await E2E.settle(tester, frames: 15);
  }

  /// Picks [optionLabel] in the settings card [identifier]'s dropdown and saves.
  ///
  /// The card has to be a dropdown one (`language`, `dateFormat`,
  /// `startingDayOfWeek`, `ai_services_ena`, `calendarSystem`, `calendarView`,
  /// `dentalNotation`); its options are `ComboBoxItem`s in an overlay, so the
  /// option is `find.text(label).last` — the *last* one is the overlay's copy.
  static Future<void> setSettingsDropdown(
    WidgetTester tester,
    String identifier,
    String optionLabel,
  ) async {
    await expandSettingsCard(tester, identifier);
    final card = find.byKey(WK.settingsItem(identifier));
    final combo = find.byKey(Key('${identifier}_combo'));
    await E2E.waitFor(tester, combo,
        description: 'the "$identifier" dropdown',
        timeout: const Duration(seconds: 20));
    await E2E.tap(tester, combo, description: 'the "$identifier" dropdown');
    await E2E.settle(tester, frames: 10);
    await E2E.tapFirst(tester, find.text(optionLabel),
        description: 'the "$optionLabel" option');
    await E2E.settle(tester, frames: 10);

    final saves = find.descendant(
      of: card,
      matching: find.byType(FilledButton, skipOffstage: false),
      skipOffstage: false,
    );
    if (saves.evaluate().isEmpty) {
      fail('The "$identifier" card never offered a Save button after '
          '"$optionLabel" was picked — it is probably already the stored value.');
    }
    final save = saves.first;
    await tester.ensureVisible(save);
    await E2E.settle(tester, frames: 10);
    await E2E.tap(tester, save, description: 'the "$identifier" save button');
    await E2E.settle(tester, frames: 20);
  }

  /// Switches the app's language **through the settings card**.
  ///
  /// The language card also triggers a resync, so this is the honest user path
  /// and the slow one; a test that only cares about rendering can set
  /// `localSettings.selectedLocale` instead (see the localization group).
  static Future<void> setLocale(WidgetTester tester, int index) async {
    await setSettingsDropdown(tester, 'language', locale.list[index].$name);
    expect(localSettings.selectedLocale, index,
        reason: 'picking "${locale.list[index].$name}" did not change the '
            'locale (it is ${localSettings.selectedLocale})');
  }

  /// Writes an appointment **through the store**, with the signed-in account as
  /// its operator and (unless [day] says otherwise) on today.
  ///
  /// The panel cannot set an operator from the harness in one step, and the
  /// notification bell is keyed on `operatorsIDs.contains(currentAccountID)` —
  /// so this is the write the bell under test has to see. Being a *store* write
  /// also makes it a local change in the database's change feed, which is what
  /// the push/notice paths listen to.
  static Future<String> seedAppointmentForMe(
    WidgetTester tester, {
    required String patientID,
    DateTime? day,
    bool labworkDue = false,
    double price = 0,
  }) async {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    // PocketBase ids are exactly 15 alphanumerics (`Invalid record id …; expected
    // [A-Za-z0-9_]{15}`) — the milliseconds carry more than ten digits, so this
    // keeps the id at the required width without inventing a counter.
    final id = 'ape${(stamp % 1000000000000).toString().padLeft(12, '0')}';
    appointments.set(Appointment.fromJson({
      'id': id,
      'patientID': patientID,
      'operatorsIDs': [login.currentAccountID],
      'date': dateToWire(day ?? DateTime.now()),
      if (labworkDue) 'hasLabwork': true,
      if (labworkDue) 'labworkReceived': false,
      if (labworkDue) 'labName': 'e2e lab',
      if (price > 0) 'price': price,
    }));
    await E2E.settle(tester, frames: 10);
    return id;
  }

  // --------------------------------------- settings services and backups

  /// Opens the settings screen and expands one of its **services** sections.
  ///
  /// The sections (`smtp_settings`, `s3_settings`, `backups`,
  /// `file_upload_settings`, `meta_settings`, `auth_settings`) sit below the
  /// cards, are collapsed `Expander`s, and are rendered only for an admin on an
  /// online session.
  static Future<void> openServiceSection(
    WidgetTester tester,
    String id,
  ) async {
    await openSettings(tester);
    // The screen reads its values before it builds the list; the list is what
    // has the scrollable, so wait for it rather than for the first card.
    await E2E.waitFor(tester, find.byKey(WK.settingsList),
        description: 'the settings list', timeout: const Duration(seconds: 60));

    final section = find.byKey(WK.serviceSection(id));
    if (section.evaluate().isEmpty) {
      final scrollable = find.descendant(
        of: find.byKey(WK.settingsList),
        matching: find.byType(Scrollable),
      );
      expect(scrollable, findsWidgets,
          reason: 'the settings list has no scrollable to scroll');
      await tester.scrollUntilVisible(
        section,
        150,
        scrollable: scrollable.first,
        maxScrolls: 80,
      );
      await E2E.settle(tester, frames: 10);
    }
    if (section.evaluate().isEmpty) {
      const known = [
        'meta_settings',
        'auth_settings',
        'file_upload_settings',
        's3_settings',
        'smtp_settings',
        'backups',
      ];
      final present = known
          .where((candidate) =>
              find.byKey(WK.serviceSection(candidate)).evaluate().isNotEmpty)
          .toList();
      fail('The "$id" section is not on the settings screen after scrolling '
          'to the end. Sections present: $present (they are rendered only for '
          'an admin on an online session).');
    }
    // Is it already open? **Not** by looking for its content: fluent's
    // `Expander` keeps the content in the tree and merely animates its height to
    // zero (`SizeTransition`), so a field, a Save button and every key inside are
    // findable while the section is still shut — they are simply not
    // hit-testable (`tester.tap` only *warns* about that, so the failure surfaces
    // much later as a missing dialog). The one honest signal is height: shut,
    // the section is its header (`minHeight: 42`); open, it is header + content.
    if (_sectionHeight(tester, section) <= _collapsedSectionHeight) {
      // The header has to be *on screen* before it can be tapped — the section
      // below the fold is where the expand tap used to miss. Its top strip is
      // what matters (the last section's header can sit right on the fold, and
      // the list has no room to lift it further).
      await _scrollIntoSettingsView(tester, section, topEdgeIsEnough: true);
      final rect = tester.getRect(section.first);
      // The header, not the box's middle: while the section is shut the box is
      // the header, and the header starts at the box's own top.
      await tester.tapAt(Offset(rect.center.dx, rect.top + 20));
      await E2E.settle(tester, frames: 5);
      // The open/close animation is `mediumAnimationDuration`; the height grows
      // as it plays, which is what the wait below watches.
      for (var frame = 0; frame < 60; frame++) {
        if (_sectionHeight(tester, section) > _collapsedSectionHeight) break;
        await E2E.settle(tester, frames: 5);
      }
    }
    expect(
        _sectionHeight(tester, section), greaterThan(_collapsedSectionHeight),
        reason: 'the "$id" section never opened: tapping its header left it '
            'only ${_sectionHeight(tester, section)} tall, which is a header '
            'and nothing else (a collapsed section lays its content out anyway, '
            'so nothing inside it can be tapped).');
  }

  /// The height a services section draws at — a header while it is shut.
  static double _sectionHeight(WidgetTester tester, Finder section) {
    final rect = tester.getRect(section.first);
    return rect.height;
  }

  /// Scrolls the settings list until [target] is inside the window, then taps it.
  ///
  /// The `ScrollPosition` is driven directly, because neither of the usual
  /// gestures works here: the services sections are full of text fields and a
  /// drag that starts on one is swallowed by it (thirty drags left the target at
  /// y≈2140 in a 1000-tall window), and `tester.ensureVisible` scrolled nothing
  /// either — while a tap that misses only *warns*, so the test then waits for a
  /// dialog that never comes. The notes board is scrolled the same way
  /// (`revealInBoard`).
  static Future<void> _scrollIntoSettingsView(
    WidgetTester tester,
    Finder target, {
    bool topEdgeIsEnough = false,
  }) async {
    final listFinder = find.byKey(WK.settingsList);
    final scrollables = find.descendant(
      of: listFinder,
      matching: find.byType(Scrollable),
    );
    final state = tester.state<ScrollableState>(scrollables.first);
    final position = state.position;
    final window = tester.view.physicalSize / tester.view.devicePixelRatio;

    // A `ListView` builds its children lazily, so its `maxScrollExtent` is only
    // an *estimate* until every child has been laid out — and it refuses to
    // grow until something asks it to go past the estimate. Asking for the end
    // of the list repeatedly is what makes the extent catch up, which is how
    // the services sections (twelve cards below the fold) come into reach.
    for (var attempt = 0; attempt < 80; attempt++) {
      final rect = tester.getRect(target.first);
      // A control is reachable when its own middle is on screen, because that is
      // where the tap lands. Four pixels of margin is what the last section's
      // header gets: the settings list has no room to lift it any further, and a
      // tighter bound simply refuses to reach a control that *is* tappable.
      final onScreen = rect.top >= 40 &&
          rect.top <= window.height - 40 &&
          (topEdgeIsEnough || rect.bottom <= window.height - 4);
      if (onScreen) return;
      // Below the fold: ask for the end of the list. Above it: scroll back up.
      final next = rect.top > window.height / 2
          ? position.maxScrollExtent
          : (position.pixels - 200.0)
              .clamp(position.minScrollExtent, position.maxScrollExtent);
      if (next == position.pixels) break;
      position.jumpTo(next);
      await E2E.settle(tester, frames: 6);
    }

    final rect = tester.getRect(target.first);
    final inside =
        find.ancestor(of: target.first, matching: listFinder).evaluate();
    fail(
        'Could not scroll the settings list to a control (it sits at $rect in a '
        '$window window; the list is at ${position.pixels} of '
        '${position.maxScrollExtent}, its viewport is '
        '${position.viewportDimension}, its own rect is '
        '${tester.getRect(listFinder)}, it holds '
        '${scrollables.evaluate().length} scrollables, and the control is '
        '${inside.isEmpty ? 'NOT ' : ''}a descendant of it).');
  }

  /// Presses a control inside a services section, scrolling it into view first.
  static Future<void> tapInSection(
    WidgetTester tester,
    String id,
    Finder matching, {
    String? description,
  }) async {
    final target = find.descendant(
      of: find.byKey(WK.serviceSection(id)),
      matching: matching,
    );
    await E2E.waitFor(tester, target,
        description: description ?? 'a control in the "$id" section');
    await _scrollIntoSettingsView(tester, target);
    await E2E.tapFirst(tester, target,
        description: description ?? 'a control in the "$id" section');
  }

  /// The text a services section's field holds (`CupertinoTextField` or
  /// `ComboBox`).
  static String serviceFieldText(WidgetTester tester, String id) {
    final widget = tester.widget(find.byKey(WK.serviceField(id)));
    if (widget is CupertinoTextField) return widget.controller?.text ?? '';
    if (widget is ComboBox<String>) return widget.value ?? '';
    return '';
  }

  /// Types [value] into a services section's field.
  static Future<void> setServiceField(
    WidgetTester tester,
    String id,
    String value,
  ) async {
    await tester.enterText(find.byKey(WK.serviceField(id)), value);
    await E2E.settle(tester, frames: 10);
  }

  /// Closes whatever dialog is open through its own `close` button.
  ///
  /// The services sections answer a save with a `ContentDialog` whose action is
  /// a labelled button (`txt("close")`), not the cancel icon
  /// [E2E.dismissStartupDialogs] looks for.
  static Future<void> closeDialog(WidgetTester tester) async {
    await E2E.tapFirst(tester, find.text(txt('close')),
        description: 'the dialog\'s close button');
    await E2E.settle(tester, frames: 15);
  }

  /// Taps a services section's Save and returns everything its result dialog
  /// says (`smtp_save_success`, `s3_save_fail: …`, …), closing it afterwards.
  ///
  /// The dialog **must be gone** before this returns: it is a modal barrier, so
  /// while it is up the section behind it is not hit-testable at all — a second
  /// save in the same section then tapped the barrier (a miss only warns), no
  /// save happened, and the helper happily re-read the *previous* dialog's text
  /// and reported success. That is exactly how `settings_services 03` failed:
  /// the restore never reached the server while the test was told it had.
  static Future<String> saveServiceSection(
    WidgetTester tester,
    String id,
  ) async {
    await tapInSection(tester, id, find.text(txt('save')),
        description: 'the "$id" save button');

    final dialog = find.byType(ContentDialog);
    await E2E.waitFor(tester, dialog,
        description: 'the "$id" save result',
        timeout: const Duration(seconds: 30));
    final said = tester
        .widgetList<Text>(
            find.descendant(of: dialog, matching: find.byType(Text)))
        .map((text) => text.data ?? '')
        .where((text) => text.isNotEmpty)
        .join(' | ');
    await closeDialog(tester);
    await E2E.waitForGone(tester, dialog,
        description: 'the "$id" save result to close');
    return said;
  }
}

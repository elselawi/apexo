import 'package:apexo/core/observable.dart';
import 'package:apexo/features/appointments/calendar_widget.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// `settings_store_test.dart` covers what is left in `settings_stores.dart`:
/// the device-scoped [LocalSettings]. The app-scoped settings moved to the
/// `settings_global` localpocket store — their behaviour (the wire shape, the
/// defaults fallback, the flag encoding, the ISO bridge and the local-rows
/// drop) is asserted in `settings_global_store_test.dart`.
void main() {
  group('LocalSettings', () {
    late Map<String, dynamic> saved;

    setUp(() {
      saved = Map<String, dynamic>.from(localSettings.toJson());
    });

    tearDown(() {
      localSettings.fromJson(saved);
    });
    test('singleton is LocalSettings instance', () {
      expect(localSettings, isA<LocalSettings>());
    });

    test('selectedLocale defaults to 0', () {
      expect(localSettings.selectedLocale, 0);
    });

    test('dateFormat defaults correctly', () {
      expect(localSettings.dateFormat, 'dd/MM/yyyy');
    });

    test('calendarSystem defaults to gregorian', () {
      expect(localSettings.calendarSystem, 'gregorian');
    });

    test('selectedTheme is a ThemeMode', () {
      expect(localSettings.selectedTheme, isA<ThemeMode>());
    });

    test('dentalNotation defaults to "p"', () {
      expect(localSettings.dentalNotation, 'p');
    });

    test('calendarEventsViewMode is EventsViewMode', () {
      expect(
        localSettings.calendarEventsViewMode,
        isA<EventsViewMode>(),
      );
    });

    test('lastSeenVersion defaults to empty', () {
      expect(localSettings.lastSeenVersion, isEmpty);
    });

    test('aiToken defaults to null', () {
      expect(localSettings.aiToken, isNull);
    });

    test('aiTokenExpiry defaults to null', () {
      expect(localSettings.aiTokenExpiry, isNull);
    });

    test('dicomViewerPrefs defaults to empty string', () {
      expect(localSettings.dicomViewerPrefs, isEmpty);
    });

    test('transcriptionLocaleNonFinal defaults to empty', () {
      expect(localSettings.transcriptionLocaleNonFinal, isEmpty);
    });

    test('transcriptionOutputLocale getter returns string', () {
      expect(localSettings.transcriptionOutputLocale, isA<String>());
    });

    test('fromJson restores every persisted local preference exactly', () {
      final expiry = DateTime.utc(2030, 1, 2, 3, 4, 5);
      localSettings.fromJson({
        'selectedLocale': 2,
        'dateFormat': 'MM/dd/yyyy',
        'calendarSystem': 'persian',
        'transcriptionLocale': 'es',
        'dentalNotation': 'f',
        'selectedTheme': 1,
        'aiToken': 'token',
        'aiTokenExpiry': expiry.millisecondsSinceEpoch,
        'calendarEventsViewMode': EventsViewMode.timeline.index,
        'lastSeenVersion': '1.2.3',
        'dicomViewerPrefs': '{"invert":true}',
      });

      expect(localSettings.selectedLocale, 2);
      expect(localSettings.dateFormat, 'MM/dd/yyyy');
      expect(localSettings.calendarSystem, 'persian');
      expect(localSettings.transcriptionOutputLocale, 'es');
      expect(localSettings.dentalNotation, 'f');
      expect(localSettings.selectedTheme, ThemeMode.dark);
      expect(localSettings.aiToken, 'token');
      expect(localSettings.aiTokenExpiry!.millisecondsSinceEpoch,
          expiry.millisecondsSinceEpoch);
      expect(localSettings.calendarEventsViewMode, EventsViewMode.timeline);
      expect(localSettings.lastSeenVersion, '1.2.3');
      expect(localSettings.dicomViewerPrefs, '{"invert":true}');
    });

    test('toJson omits absent AI credentials and serializes active values', () {
      localSettings.fromJson({});
      final withoutToken = localSettings.toJson();
      expect(withoutToken.containsKey('aiToken'), isFalse);
      expect(withoutToken.containsKey('aiTokenExpiry'), isFalse);

      final expiry = DateTime.utc(2030).millisecondsSinceEpoch;
      localSettings.fromJson({
        'aiToken': 'active-token',
        'aiTokenExpiry': expiry,
      });
      final withToken = localSettings.toJson();
      expect(withToken['aiToken'], 'active-token');
      expect(withToken['aiTokenExpiry'], expiry);
    });

    test('toggleEventsViewMode toggles and notifies observers', () async {
      localSettings.fromJson({'calendarEventsViewMode': 0});
      var notifications = 0;
      int observer(ObservablePersistingObject _) => notifications++;
      localSettings.observe(observer);

      localSettings.toggleEventsViewMode();
      await Future<void>.delayed(Duration.zero);

      expect(localSettings.calendarEventsViewMode, EventsViewMode.timeline);
      expect(notifications, 1);
      localSettings.unObserve(observer);
    });

    test('invalid calendar events view mode is rejected', () {
      expect(
        () => localSettings.fromJson({'calendarEventsViewMode': 999}),
        throwsRangeError,
      );
    });

    test('hasValidAiToken honors the two-hour safety margin', () {
      localSettings.fromJson({
        'aiToken': 'token',
        'aiTokenExpiry':
            DateTime.now().add(const Duration(hours: 3)).millisecondsSinceEpoch,
      });
      expect(localSettings.hasValidAiToken, isTrue);

      localSettings.fromJson({
        'aiToken': 'token',
        'aiTokenExpiry':
            DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch,
      });
      expect(localSettings.hasValidAiToken, isFalse);
    });
  });
}

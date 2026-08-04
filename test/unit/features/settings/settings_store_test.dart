import 'package:apexo/core/observable.dart';
import 'package:apexo/features/appointments/calendar_widget.dart';
import 'package:apexo/features/settings/settings_model.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GlobalSettings behavior', () {
    late GlobalSettings settings;

    setUp(() {
      // An isolated store instance avoids coupling these behavior tests to
      // the process-wide globalSettings singleton or persisted Hive state.
      settings = GlobalSettings();
    });

    test('missing settings resolve to their documented defaults', () {
      expect(settings.currency, 'USD');
      expect(settings.phone, '1234567890');
      expect(settings.prescriptionFooter, isEmpty);
      expect(settings.startDayOfWeek, 'monday');
      expect(settings.isoCountryCode, isEmpty);
      expect(settings.aiServicesEnabled, isFalse);
      expect(settings.dicomAutoImport, isTrue);
    });

    test('DICOM directory setter trims, filters, and persists directories', () {
      settings.dicomWatchDirs = [' C:/one ', '', 'C:/two', '   '];

      expect(settings.dicomWatchDir, 'C:/one;C:/two');
      expect(settings.dicomWatchDirs, ['C:/one', 'C:/two']);
    });

    test('DICOM auto import setter uses explicit wire values', () {
      settings.dicomAutoImport = false;
      expect(settings.get('dicom_auto_imp_').value, '0');
      expect(settings.dicomAutoImport, isFalse);

      settings.dicomAutoImport = true;
      expect(settings.get('dicom_auto_imp_').value, '1');
      expect(settings.dicomAutoImport, isTrue);
    });

    test('setting changes emit observable add and modify events', () async {
      final events = <List<DictEvent>>[];
      settings.observableMap.observe(events.add);

      settings.dicomWatchDir = 'C:/one';
      await Future<void>.delayed(Duration.zero);
      settings.dicomWatchDir = 'C:/two';
      await Future<void>.delayed(Duration.zero);

      expect(events.length, 2);
      expect(events[0].single.type, DictEventType.add);
      expect(events[0].single.id, 'dicom_watch_dir');
      expect(events[1].single.type, DictEventType.modify);
      expect(settings.dicomWatchDir, 'C:/two');
    });

    test('clear resets overridden values back to default fallback values',
        () async {
      settings.set(Setting.fromJson({
        'id': 'currency_______',
        'value': 'EUR',
      }));
      expect(settings.currency, 'EUR');

      settings.observableMap.clear();
      await Future<void>.delayed(Duration.zero);
      expect(settings.currency, 'USD');
    });
  });

  group('GlobalSettings', () {
    test('singleton is GlobalSettings instance', () {
      expect(globalSettings, isA<GlobalSettings>());
    });

    test('observableMap is ObservableDict', () {
      expect(globalSettings.observableMap, isA<ObservableDict<Setting>>());
    });

    test('defaults map has expected keys', () {
      expect(globalSettings.defaults, contains('currency_______'));
      expect(globalSettings.defaults, contains('phone__________'));
      expect(globalSettings.defaults, contains('prescriptionFot'));
      expect(globalSettings.defaults, contains('start_day_of_wk'));
      expect(globalSettings.defaults, contains('ISO_country____'));
      expect(globalSettings.defaults, contains('ai_services_ena'));
      expect(globalSettings.defaults, contains('dicom_watch_dir'));
      expect(globalSettings.defaults, contains('dicom_auto_imp_'));
    });

    test('currency getter returns non-null string', () {
      expect(globalSettings.currency, isA<String>());
      expect(globalSettings.currency, isNotEmpty);
    });

    test('phone getter returns non-null string', () {
      expect(globalSettings.phone, isA<String>());
      expect(globalSettings.phone, isNotEmpty);
    });

    test('prescriptionFooter getter returns string', () {
      expect(globalSettings.prescriptionFooter, isA<String>());
    });

    test('startDayOfWeek getter returns string', () {
      expect(globalSettings.startDayOfWeek, isA<String>());
      expect(globalSettings.startDayOfWeek, isNotEmpty);
    });

    test('isoCountryCode getter returns string', () {
      expect(globalSettings.isoCountryCode, isA<String>());
    });

    test('aiServicesEnabled getter returns bool', () {
      expect(globalSettings.aiServicesEnabled, isA<bool>());
    });

    test('dicomWatchDir getter returns string', () {
      expect(globalSettings.dicomWatchDir, isA<String>());
    });

    test('dicomWatchDirs returns a list', () {
      expect(globalSettings.dicomWatchDirs, isA<List<String>>());
    });

    test('dicomWatchDirs handles empty string', () {
      // With no data, dicomWatchDir defaults to ""
      expect(globalSettings.dicomWatchDirs, isEmpty);
    });

    test('dicomAutoImport getter returns bool', () {
      expect(globalSettings.dicomAutoImport, isA<bool>());
    });

    test('present returns a map', () {
      expect(globalSettings.present, isA<Map<String, Setting>>());
    });
  });

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

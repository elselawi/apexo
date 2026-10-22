import 'package:apexo/app/data/application_store_effects.dart';
import 'package:apexo/app/data/store_session_binding.dart';
import 'package:apexo/core/persistence/observable_persisting_object.dart';
import 'package:apexo/features/accounts/accounts_controller.dart';
import 'events_view_mode.dart';

export 'events_view_mode.dart';
import 'package:apexo/services/launch.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/utils/country_code_iso_fetch.dart';
import 'package:apexo/services/backups.dart';
import 'package:apexo/utils/js/js_bridge.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:apexo/utils/hijri_utils.dart';
import 'package:apexo/utils/jalali_utils.dart';
import '../network_actions/network_actions_controller.dart';
import 'settings_model.dart';
import '../../core/store.dart';

const _storeNameGlobal = "settings_global";
const _storeNameLocal = "settings_local";

class GlobalSettings extends Store<Setting> {
  GlobalSettings()
      : super(
          effects: applicationStoreEffects,
          loadDocuments: loadApplicationDocuments,
          modeling: Setting.fromJson,
          isDemo: launch.isDemo,
          onSyncStart: () {
            networkActions.isSyncing(networkActions.isSyncing() + 1);
          },
          onSyncEnd: () {
            networkActions.isSyncing(networkActions.isSyncing() - 1);
          },
        );
  String get currency => get("currency_______").value;
  String get phone => get("phone__________").value;
  String get prescriptionFooter => get("prescriptionFot").value;
  String get startDayOfWeek => get("start_day_of_wk").value;
  String get isoCountryCode => get("ISO_country____").value;
  bool get aiServicesEnabled => get("ai_services_ena").value == "1";

  // Windows-only feature: directory/directories where the Xray software
  // stores `.dcm` files. Supports multiple directories separated by `;`.
  // Empty string = not configured.
  String get dicomWatchDir => get("dicom_watch_dir").value;
  set dicomWatchDir(String v) =>
      set(Setting.fromJson({"id": "dicom_watch_dir", "value": v}));

  /// Parsed list of watch directories (split by `;`, trimmed, empty entries
  /// filtered out). Use this for scanning — handles both single-dir legacy
  /// values (no semicolons) and the new multi-dir format.
  List<String> get dicomWatchDirs {
    final raw = dicomWatchDir;
    if (raw.isEmpty) return const <String>[];
    return raw
        .split(";")
        .map((d) => d.trim())
        .where((d) => d.isNotEmpty)
        .toList();
  }

  /// Persists a list of watch directories as a semicolon-separated string.
  set dicomWatchDirs(List<String> dirs) {
    dicomWatchDir =
        dirs.map((d) => d.trim()).where((d) => d.isNotEmpty).join(";");
  }

  // When true, new `.dcm` files for already-linked patients are auto-imported
  // during scans (startup + appointments resync). When false, the dentist
  // opens the DICOM Import screen manually.
  bool get dicomAutoImport => get("dicom_auto_imp_").value == "1";
  set dicomAutoImport(bool v) =>
      set(Setting.fromJson({"id": "dicom_auto_imp_", "value": v ? "1" : "0"}));

  Map<String, String> defaults = {
    "currency_______": "USD",
    "phone__________": "1234567890",
    "prescriptionFot": "",
    "start_day_of_wk": "monday",
    "ISO_country____": "",
    "ai_services_ena": "0",
    "dicom_watch_dir": "",
    "dicom_auto_imp_": "1",
  };

  @override
  Setting get(String id) {
    return super.get(id) ?? Setting.fromJson({"id": id, "value": defaults[id]});
  }

  late final _session = StoreSessionBinding<Setting>(
    store: this,
    name: _storeNameGlobal,
    loadingMessage: 'Synchronizing settings',
    syncAction: () async {
      await Future.wait([
        synchronize(),
        accounts.reloadFromRemote(),
        backups.reloadFromRemote()
      ]);
    },
    afterSynchronize: (isCurrent) async {
      defaults.forEach((key, value) {
        if (!has(key)) set(Setting.fromJson({'id': key, 'value': value}));
      });
      await Future.wait(
          [backups.reloadFromRemote(), accounts.reloadFromRemote()]);
      if (!isCurrent()) return;
      if (get('ISO_country____').value == '') {
        final code = await getCountryCode();
        if (isCurrent()) {
          set(Setting.fromJson({'id': 'ISO_country____', 'value': code}));
        }
      }
    },
  );

  @override
  void init() {
    super.init();
    _session.install();
  }
}

String currency() => globalSettings.get("currency_______").value;

/// The clinic's ISO country code, as the phone parser and `IsoCode.byName` want
/// it: two letters, upper case.
///
/// The setting is free text — the card is a plain text field, and
/// `getCountryCode` answers with one of the API's two-letter codes — so it can
/// hold something else. `substring(0, 2)` on a pasted flag emoji (four code
/// units) hands the rest of the app a string that ends in half a surrogate pair,
/// which Flutter's paragraph builder refuses to draw.
String isoCC() {
  final code = globalSettings.isoCountryCode;
  if (code.isEmpty) return "US";
  final letters = code.replaceAll(RegExp(r"[^A-Za-z]"), "");
  if (letters.length >= 2) return letters.substring(0, 2).toUpperCase();
  if (letters.length == 1 && code.length == 1) return code.toUpperCase();
  return "US";
}

class LocalSettings extends ObservablePersistingObject {
  LocalSettings() : super(_storeNameLocal) {
    if (kIsWeb) {
      observe((_) {
        // We need to set the language in the JS bridge for the web
        // this is to localize the permission requst & push notifications
        JSBridge.setGlobalVariable("lang", locale.s.$code);
      });
    }
  }

  String transcriptionLocaleNonFinal = "";
  String dateFormat = "dd/MM/yyyy";
  String timeFormat = DF.time12hPattern;
  String calendarSystem = "gregorian";
  ThemeMode selectedTheme = ThemeMode.light;
  int _selectedLocale = 0;

  /// The language the user picked, persisted with the rest of the device
  /// settings — and pushed into [locale], which owns what is on screen.
  ///
  /// The setter is the only way in, so a stored preference, a settings dropdown
  /// and a language button cannot leave the dictionary and the persisted value
  /// disagreeing.
  int get selectedLocale => _selectedLocale;

  set selectedLocale(int value) {
    _selectedLocale = value < 0
        ? 0
        : (value >= locale.list.length ? locale.list.length - 1 : value);
    locale.select(_selectedLocale);
  }
  String dentalNotation = "p";
  String? aiToken;
  String aiTokenServer = '';
  DateTime? aiTokenExpiry;
  EventsViewMode calendarEventsViewMode = EventsViewMode.agenda;
  String lastSeenVersion = "";

  // ── DICOM viewer preferences
  // JSON string: {"windowCenter": double, "windowWidth": double,
  //               "colorMap": String, "invert": bool, "rotationSteps": int}
  // Empty string = use DICOM defaults. The viewer panel (Phase 6) reads this
  // on open and writes back (debounced) when the dentist changes a setting,
  // so the next image opens with the same preferences.
  String dicomViewerPrefs = "";

  // ── Panels' floating windows
  // JSON string: {"patient": ["dentalChart", "appointments"], ...} — the windows
  // each kind of panel was left with, so the next panel of that kind opens the
  // way the last one was left. Read and written through `WindowDefaults`; kept
  // per device and deliberately not offered as a setting.
  String windowsPerKind = "";

  static const _aiTokenSafetyMargin = Duration(hours: 2);

  void toggleEventsViewMode() {
    calendarEventsViewMode = calendarEventsViewMode == EventsViewMode.agenda
        ? EventsViewMode.timeline
        : EventsViewMode.agenda;
    notifyAndPersist();
  }

  String get transcriptionOutputLocale {
    if (transcriptionLocaleNonFinal.isNotEmpty) {
      return transcriptionLocaleNonFinal;
    } else {
      return locale.s.$code;
    }
  }

  bool get hasValidAiToken =>
      aiToken != null &&
      aiTokenExpiry != null &&
      DateTime.now().isBefore(aiTokenExpiry!.subtract(_aiTokenSafetyMargin));

  @override
  void fromJson(Map<String, dynamic> json) {
    selectedLocale = json["selectedLocale"] as int? ?? selectedLocale;
    dateFormat = json["dateFormat"] as String? ?? dateFormat;
    final storedTimeFormat = json["timeFormat"];
    timeFormat = DF.timeFormats.contains(storedTimeFormat)
        ? storedTimeFormat as String
        : DF.time12hPattern;
    calendarSystem = json["calendarSystem"] as String? ?? calendarSystem;
    transcriptionLocaleNonFinal =
        json["transcriptionLocale"] as String? ?? transcriptionLocaleNonFinal;
    final legacyLanguageCodes = locale.list.map((l) => l.$code).toList();
    final legacyIndex = int.tryParse(transcriptionLocaleNonFinal);
    if (legacyIndex != null &&
        legacyIndex >= 0 &&
        legacyIndex < legacyLanguageCodes.length) {
      transcriptionLocaleNonFinal = legacyLanguageCodes[legacyIndex];
    }
    dentalNotation = json["dentalNotation"] as String? ?? dentalNotation;
    selectedTheme =
        json["selectedTheme"] == 1 ? ThemeMode.dark : ThemeMode.light;
    aiToken = json["aiToken"] as String?;
    aiTokenServer = json['aiTokenServer'] as String? ?? '';
    aiTokenExpiry = json["aiTokenExpiry"] != null
        ? DateTime.fromMillisecondsSinceEpoch(json["aiTokenExpiry"] as int)
        : null;
    calendarEventsViewMode =
        EventsViewMode.values[json["calendarEventsViewMode"] as int? ?? 0];
    lastSeenVersion = json["lastSeenVersion"] as String? ?? lastSeenVersion;
    dicomViewerPrefs = json["dicomViewerPrefs"] as String? ?? "";
    windowsPerKind = json["windowsPerKind"] as String? ?? "";
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      "selectedLocale": selectedLocale,
      "dateFormat": dateFormat,
      "timeFormat": timeFormat,
      "calendarSystem": calendarSystem,
      "dentalNotation": dentalNotation,
      "transcriptionLocale": transcriptionLocaleNonFinal,
      "selectedTheme": selectedTheme == ThemeMode.dark ? 1 : 0,
      "lastSeenVersion": lastSeenVersion,
      "calendarEventsViewMode": calendarEventsViewMode.index,
      "dicomViewerPrefs": dicomViewerPrefs,
      "windowsPerKind": windowsPerKind,
      'aiTokenServer': aiTokenServer,
      if (aiToken != null) "aiToken": aiToken,
      if (aiTokenExpiry != null)
        "aiTokenExpiry": aiTokenExpiry!.millisecondsSinceEpoch,
    };
  }
}

abstract class DF {
  static const String time12hPattern = "hh:mm a";
  static const String time24hPattern = "HH:mm";
  static const List<String> timeFormats = [time12hPattern, time24hPattern];

  static String get timePattern =>
      timeFormats.contains(localSettings.timeFormat)
          ? localSettings.timeFormat
          : time12hPattern;

  static bool get is24Hour => timePattern.startsWith("H");

  static bool get isPersianCalendar =>
      localSettings.calendarSystem == "persian";

  static bool get isHijriCalendar => localSettings.calendarSystem == "hijri";

  static String commonDate(DateTime date) {
    if (isPersianCalendar) {
      final jDate = JalaliUtils.formatJalaliDMY(date);
      final dayName = JalaliUtils.dayOfWeekAbbr(date.weekday);
      return "📅 $dayName $jDate";
    }
    if (isHijriCalendar) {
      final hDate = HijriUtils.formatHijriDMY(date);
      final dayName = HijriUtils.dayOfWeekAbbr(date.weekday);
      return "📅 $dayName $hDate";
    }
    final df = localSettings.dateFormat.startsWith("d") == true
        ? "📅 EE dd / MM / yyyy"
        : "📅 EE MM / dd / yyyy";
    return DateFormat(df, locale.s.$code).format(date);
  }

  static String full(DateTime date) {
    if (isPersianCalendar || isHijriCalendar) {
      return "${commonDate(date)} ${time(date)}";
    }
    final df = localSettings.dateFormat.startsWith("d") == true
        ? "📅 EE dd / MM / yyyy 🕒 $timePattern"
        : "📅 EE MM / dd / yyyy 🕒 $timePattern";
    return DateFormat(df, locale.s.$code).format(date);
  }

  static String fullCompact(DateTime date) {
    if (isPersianCalendar || isHijriCalendar) {
      return "📅 ${allNumbers(date)} ${time(date)}";
    }
    final df = localSettings.dateFormat.startsWith("d") == true
        ? "📅 dd / MM / yyyy 🕒 $timePattern"
        : "📅 MM / dd / yyyy 🕒 $timePattern";
    return DateFormat(df, locale.s.$code).format(date);
  }

  static String allNumbers(DateTime date) {
    if (isPersianCalendar) {
      return JalaliUtils.formatJalaliDMY(date);
    }
    if (isHijriCalendar) {
      return HijriUtils.formatHijriDMY(date);
    }
    final df = localSettings.dateFormat.startsWith("d") == true
        ? "dd / MM / yyyy"
        : "MM / dd / yyyy";
    return DateFormat(df, locale.s.$code).format(date);
  }

  static String dayOfWeek(DateTime date) {
    return jalaliDayOfWeekAbbr(date);
  }

  static String time(DateTime date) {
    return DateFormat("🕒 $timePattern", locale.s.$code).format(date);
  }

  static String timeOnly(DateTime date) {
    return DateFormat(timePattern, locale.s.$code).format(date);
  }

  static String hourLabel(DateTime date) {
    return DateFormat(is24Hour ? "HH" : "h a", locale.s.$code).format(date);
  }

  static String jalaliDate(DateTime date) => allNumbers(date);

  static String jalaliDay(DateTime date) {
    if (isPersianCalendar) {
      return JalaliUtils.formatDay(date);
    }
    if (isHijriCalendar) {
      return HijriUtils.formatDay(date);
    }
    return DateFormat("d", locale.s.$code).format(date);
  }

  static String jalaliMonthYear(DateTime date) {
    if (isPersianCalendar) {
      return JalaliUtils.formatMonthYear(date);
    }
    if (isHijriCalendar) {
      return HijriUtils.formatMonthYear(date);
    }
    return DateFormat('MMMM yyyy', locale.s.$code).format(date);
  }

  static String jalaliDayOfWeekAbbr(DateTime date) {
    if (isPersianCalendar) {
      return JalaliUtils.dayOfWeekAbbr(date.weekday);
    }
    if (isHijriCalendar) {
      return HijriUtils.dayOfWeekAbbr(date.weekday);
    }
    return DateFormat("EE", locale.s.$code).format(date);
  }

  static String jalaliCommonDate(DateTime date) => commonDate(date);
}

final globalSettings = GlobalSettings();
final localSettings = LocalSettings();

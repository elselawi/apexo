import 'package:apexo/core/observable.dart';
import 'package:apexo/features/accounts/accounts_controller.dart';
import 'package:apexo/features/appointments/calendar_widget.dart';
import 'package:apexo/features/login/login_controller.dart';
import 'package:apexo/services/launch.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/network.dart';
import 'package:apexo/utils/country_code_iso_fetch.dart';
import 'package:apexo/utils/hash.dart';
import 'package:apexo/services/backups.dart';
import 'package:apexo/utils/js/js_bridge.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../../core/save_local.dart';
import '../../core/save_remote.dart';
import '../network_actions/network_actions_controller.dart';
import '../../services/login.dart';
import 'settings_model.dart';
import '../../core/store.dart';

const _storeNameGlobal = "settings_global";
const _storeNameLocal = "settings_local";

class GlobalSettings extends Store<Setting> {
  String get currency => get("currency_______").value;
  String get phone => get("phone__________").value;
  String get prescriptionFooter => get("prescriptionFot").value;
  String get startDayOfWeek => get("start_day_of_wk").value;
  String get isoCountryCode => get("ISO_country____").value;
  bool get aiServicesEnabled => get("ai_services_ena").value == "1";

  Map<String, String> defaults = {
    "currency_______": "USD",
    "phone__________": "1234567890",
    "prescriptionFot": "",
    "start_day_of_wk": "monday",
    "ISO_country____": "",
    "ai_services_ena": "0",
  };

  @override
  Setting get(String id) {
    return super.get(id) ?? Setting.fromJson({"id": id, "value": defaults[id]});
  }

  GlobalSettings()
      : super(
          modeling: Setting.fromJson,
          isDemo: launch.isDemo,
          onSyncStart: () {
            networkActions.isSyncing(networkActions.isSyncing() + 1);
          },
          onSyncEnd: () {
            networkActions.isSyncing(networkActions.isSyncing() - 1);
          },
        );

  @override
  init() {
    super.init();
    login.activators[_storeNameGlobal] = () async {
      await loaded;

      local =
          SaveLocal(name: _storeNameGlobal, uniqueId: simpleHash(login.url));
      await deleteMemoryAndLoadFromPersistence();

      remote = SaveRemote(
        pbInstance: login.pb!,
        storeName: _storeNameGlobal,
        onOnlineStatusChange: (current) {
          if (network.isOnline() != current) {
            network.isOnline(current);
          }
        },
      );

      return () async {
        loginCtrl.loadingIndicator("Synchronizing settings");
        await Future.wait([loaded, synchronize()]).then((_) {
          defaults.forEach((key, value) {
            if (has(key) == false) {
              set(Setting.fromJson({"id": key, "value": value}));
            }
          });
        });
        networkActions.syncCallbacks[_storeNameGlobal] = () async {
          await Future.wait([
            synchronize(),
            accounts.reloadFromRemote(),
            backups.reloadFromRemote(),
          ]);
        };
        networkActions.reconnectCallbacks[_storeNameGlobal] =
            remote!.checkOnline;

        network.onOnline[_storeNameGlobal] = synchronize;
        network.onOffline[_storeNameGlobal] = cancelRealtimeSub;

        // setting services
        await Future.wait([
          backups.reloadFromRemote(),
          accounts.reloadFromRemote(),
        ]);

        // setting country code iso if not already set
        if (get("ISO_country____").value == "") {
          set(Setting.fromJson(
              {"id": "ISO_country____", "value": await getCountryCode()}));
        }
      };
    };
  }
}

String currency() => globalSettings.get("currency_______").value;
String isoCC() => globalSettings.isoCountryCode.isEmpty
    ? "US"
    : globalSettings.isoCountryCode.substring(0, 2).toUpperCase();

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
  ThemeMode selectedTheme = ThemeMode.light;
  int selectedLocale = 0;
  String dentalNotation = "p";
  String? aiToken;
  DateTime? aiTokenExpiry;
  EventsViewMode calendarEventsViewMode = EventsViewMode.agenda;

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
  fromJson(Map<String, dynamic> json) {
    selectedLocale = json["selectedLocale"] ?? selectedLocale;
    dateFormat = json["dateFormat"] ?? dateFormat;
    transcriptionLocaleNonFinal =
        json["transcriptionLocale"] ?? transcriptionLocaleNonFinal;
    dentalNotation = json["dentalNotation"] ?? dentalNotation;
    selectedTheme =
        json["selectedTheme"] == 1 ? ThemeMode.dark : ThemeMode.light;
    aiToken = json["aiToken"] as String?;
    aiTokenExpiry = json["aiTokenExpiry"] != null
        ? DateTime.fromMillisecondsSinceEpoch(json["aiTokenExpiry"] as int)
        : null;
    calendarEventsViewMode =
        EventsViewMode.values[json["calendarEventsViewMode"] ?? 0];
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      "selectedLocale": selectedLocale,
      "dateFormat": dateFormat,
      "dentalNotation": dentalNotation,
      "transcriptionLocale": transcriptionLocaleNonFinal,
      "selectedTheme": selectedTheme == ThemeMode.dark ? 1 : 0,
      "calendarEventsViewMode": calendarEventsViewMode.index,
      if (aiToken != null) "aiToken": aiToken,
      if (aiTokenExpiry != null)
        "aiTokenExpiry": aiTokenExpiry!.millisecondsSinceEpoch,
    };
  }
}

abstract class DF {
  static String commonDate(date) {
    final df = localSettings.dateFormat.startsWith("d") == true
        ? "📅 EE dd / MM / yyyy"
        : "📅 EE MM / dd / yyyy";
    return DateFormat(df, locale.s.$code).format(date);
  }

  static String full(date) {
    final df = localSettings.dateFormat.startsWith("d") == true
        ? "📅 EE dd / MM / yyyy 🕒 hh:mm a"
        : "📅 EE MM / dd / yyyy 🕒 hh:mm a";
    return DateFormat(df, locale.s.$code).format(date);
  }

  static String fullCompact(date) {
    final df = localSettings.dateFormat.startsWith("d") == true
        ? "📅 dd / MM / yyyy 🕒 hh:mm a"
        : "📅 MM / dd / yyyy 🕒 hh:mm a";
    return DateFormat(df, locale.s.$code).format(date);
  }

  static String allNumbers(date) {
    final df = localSettings.dateFormat.startsWith("d") == true
        ? "dd / MM / yyyy"
        : "MM / dd / yyyy";
    return DateFormat(df, locale.s.$code).format(date);
  }

  static String dayOfWeek(date) {
    return DateFormat("EE", locale.s.$code).format(date);
  }

  static String time(date) {
    return DateFormat("🕒 hh:mm a", locale.s.$code).format(date);
  }
}

final globalSettings = GlobalSettings();
final localSettings = LocalSettings();

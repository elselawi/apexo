import 'package:apexo/common_widgets/static_notifications_widget.dart';
import 'package:apexo/features/login/login_controller.dart';
import 'package:apexo/features/network_actions/errors_list_widget.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/launch.dart';
import 'package:apexo/services/network.dart';
import 'package:apexo/services/notifications/static_notifications.dart';
import 'package:apexo/services/patient_side.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';
import '../../services/login.dart';
import '../../core/observable.dart';

class ErrorItem {
  final String message;
  final String when;
  int count;
  ErrorItem({required this.message, required this.when, this.count = 1});
}

class NetworkAction {
  String tooltip;
  Widget icon;
  void Function()? onPressed;
  Color activeColor;
  bool? hidden;
  bool? disabled;
  bool? processing;
  bool? animate;
  String? badge;
  NetworkAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    required this.activeColor,
    this.hidden,
    this.disabled,
    this.processing,
    this.animate,
    this.badge,
  });
}

class _NetworkActions {
  final isSyncing = ObservableState(0);

  Map<String, void Function()> syncCallbacks = {};
  Map<String, void Function()> reconnectCallbacks = {};

  // Error tracking
  final List<ErrorItem> _errors = [];
  final hasErrors = ObservableState(false);
  final errorPulse = ObservableState(0);

  List<ErrorItem> get errors => List.unmodifiable(_errors);

  /// Returns true if it's a new unique error (caller should show dialog),
  /// false if it's a duplicate (caller should skip dialog, we already pulse).
  bool addError(Object message, String when) {
    final msg = message.toString();
    final existing = _errors.where((e) => e.message == msg && e.when == when);
    if (existing.isNotEmpty) {
      existing.first.count++;
      errorPulse(errorPulse() + 1);
      return false; // repeated error, just pulse
    }

    _errors.add(ErrorItem(message: msg, when: when));
    hasErrors(true);
    errorPulse(errorPulse() + 1);
    return true; // new error, show dialog
  }

  Future<void> performReconnect() async {
    if (launch.isDemo) return;
    if (launch.open() == Open.patient) {
      await patientSide.activate();
      return;
    }
    await login.activate(login.url, [login.token], true);
    for (var callback in reconnectCallbacks.values) {
      callback();
    }
    if (network.isOnline()) {
      _errors.clear();
      hasErrors(false);
    }
  }

  Future<void> resync() async {
    if (launch.open() == Open.patient) {
      isSyncing(isSyncing() + 1);
      await patientSide.activate();
      isSyncing(isSyncing() - 1);
      return;
    }

    isSyncing(isSyncing() + 1);
    await login.activate(login.url, [login.token], true);
    isSyncing(isSyncing() - 1);

    for (var callback in syncCallbacks.values) {
      callback();
    }
  }

  List<NetworkAction> get actions {
    return [
      // coming soon: chat with staff feature
      // NetworkAction(
      //   tooltip: "Chat",
      //   icon: WindowsIcons.action_center,
      //   onPressed: () {},
      //   activeColor: Colors.transparent,
      //   badge: "12",
      // ),
      if (launch.open() != Open.login)
        NetworkAction(
          tooltip: "Notifications",
          activeColor: Colors.blue,
          badge: staticNotifications.notifications.isNotEmpty
              ? staticNotifications.notifications.length.toString()
              : null,
          processing: staticNotifications.notifications.isNotEmpty,
          icon: const StaticNotificationsIcon(),
          onPressed: showStaticNotifications,
        ),
      NetworkAction(
        tooltip: "Theme",
        icon: Icon((localSettings.selectedTheme == ThemeMode.light)
            ? FluentIcons.sunny
            : FluentIcons.clear_night),
        onPressed: () {
          localSettings.selectedTheme =
              localSettings.selectedTheme == ThemeMode.dark
                  ? ThemeMode.light
                  : ThemeMode.dark;
          localSettings.notifyAndPersist();
        },
        animate: false,
        activeColor: Colors.transparent,
      ),
      NetworkAction(
        tooltip: "Synchronize",
        icon: const Icon(FluentIcons.sync),
        onPressed: () async {
          if (launch.isDemo) return;
          await resync();
        },
        badge: (launch.open() == Open.patient)
            ? null
            : isSyncing() > 0
                ? "${isSyncing()}"
                : syncCallbacks.length.toString(),
        disabled: (network.isOnline() == false ||
            isSyncing() > 0 ||
            loginCtrl.proceededOffline()),
        processing: isSyncing() > 0 || loginCtrl.loadingIndicator().isNotEmpty,
        animate: true,
        activeColor: Colors.blue,
      ),
      NetworkAction(
        tooltip: hasErrors() ? txt("errors") : txt("reconnect"),
        icon: Icon((network.isOnline() && !loginCtrl.proceededOffline())
            ? FluentIcons.streaming
            : FluentIcons.streaming_off),
        onPressed: hasErrors()
            ? () => showErrorsFlyout()
            : () async {
                await performReconnect();
              },
        badge: hasErrors() ? "${_errors.length}" : null,
        disabled: hasErrors()
            ? false
            : (network.isOnline() && !loginCtrl.proceededOffline()),
        processing: hasErrors() ||
            (network.isOnline() && !loginCtrl.proceededOffline()),
        animate: false,
        activeColor: hasErrors() ? Colors.red : Colors.teal,
      ),
    ];
  }
}

final networkActions = _NetworkActions();

import 'package:apexo/common_widgets/static_notifications_widget.dart';
import 'package:apexo/features/login/login_controller.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/launch.dart';
import 'package:apexo/services/network.dart';
import 'package:apexo/services/notifications/static_notifications.dart';
import 'package:fluent_ui/fluent_ui.dart';
import '../../services/login.dart';
import '../../core/observable.dart';

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

  Future<void> resync() async {
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
        badge: isSyncing() > 0
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
        tooltip: "Reconnect",
        icon: Icon((network.isOnline() && !loginCtrl.proceededOffline())
            ? FluentIcons.streaming
            : FluentIcons.streaming_off),
        onPressed: () async {
          if (launch.isDemo) return;
          await login.activate(login.url, [login.token], true);
          for (var callback in reconnectCallbacks.values) {
            callback();
          }
        },
        disabled: (network.isOnline() && !loginCtrl.proceededOffline()),
        processing: (network.isOnline() && !loginCtrl.proceededOffline()),
        animate: false,
        activeColor: Colors.teal,
      ),
    ];
  }
}

final networkActions = _NetworkActions();

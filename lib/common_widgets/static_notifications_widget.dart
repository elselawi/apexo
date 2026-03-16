import 'package:apexo/app/routes.dart';
import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/no_items_found.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/notifications/static_notifications.dart';
import 'package:apexo/utils/flyout_focus_fix.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:apexo/utils/js/js_bridge.dart';

final FlyoutController _notificationsFlyoutController = FlyoutController();

class StaticNotificationsIcon extends StatelessWidget {
  const StaticNotificationsIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return FlyoutTarget(
      controller: _notificationsFlyoutController,
      child: const Icon(FluentIcons.ringer),
    );
  }
}

showStaticNotifications() async {
  await flyoutFocusFix(null);
  _notificationsFlyoutController.showFlyout(
    barrierColor: Colors.transparent,
    barrierDismissible: true,
    dismissWithEsc: true,
    builder: (ctx) {
      return FlyoutContent(
        useAcrylic: false,
        constraints: const BoxConstraints(maxWidth: 300, maxHeight: 360),
        child: staticNotifications.notifications.isEmpty
            ? const NoItemsFound()
            : ListView(
                children: staticNotifications.notifications
                    .map((notification) {
                      return Container(
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: staticNotifications
                                          .notifications.last.title ==
                                      notification.title
                                  ? Colors.transparent
                                  : FluentTheme.of(ctx)
                                      .inactiveColor
                                      .withValues(alpha: 0.2),
                            ),
                          ),
                        ),
                        width: 280,
                        padding: const EdgeInsets.all(8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          mainAxisSize: MainAxisSize.min,
                          spacing: 5,
                          children: [
                            Row(
                              spacing: 5,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.grey,
                                    borderRadius: BorderRadius.circular(40),
                                  ),
                                  child: Icon(notification.icon,
                                      color: Colors.white),
                                ),
                                SizedBox(
                                  width: 165,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        notification.title,
                                        style: FluentTheme.of(ctx)
                                            .typography
                                            .bodyStrong,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        notification.body,
                                        style: FluentTheme.of(ctx)
                                            .typography
                                            .caption,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            ...notification.actions
                                .where((a) =>
                                    a.hideOnRoute !=
                                    routes.currentRoute.identifier)
                                .map((action) {
                              return HyperlinkButton(
                                onPressed: () {
                                  action.action();
                                  _notificationsFlyoutController.close();
                                },
                                child: Text(action.label),
                              );
                            }),
                          ],
                        ),
                      );
                    })
                    .cast<Widget>()
                    .toList()
                  ..addAll([
                    if (kIsWeb) ...[
                      const Divider(),
                      HyperlinkButton(
                        onPressed: () {
                          JSBridge.setGlobalVariable(
                            "shouldShowPrompt",
                            "yes",
                          );
                          _notificationsFlyoutController.close();
                        },
                        child: ButtonContent(
                          FluentIcons.ringer_active,
                          txt("enableNotifications"),
                        ),
                      )
                    ],
                  ]),
              ),
      );
    },
  );
}

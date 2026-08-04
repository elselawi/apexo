import 'package:apexo/services/notifications/static_notifications.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NotificationAction', () {
    test('constructor stores all fields', () {
      bool tapped = false;
      final action = NotificationAction(
        color: const Color(0xFF0000FF),
        label: 'View',
        action: () => tapped = true,
        hideOnRoute: 'appointments',
      );

      expect(action.label, 'View');
      expect(action.hideOnRoute, 'appointments');
      expect(tapped, isFalse);
      action.action();
      expect(tapped, isTrue);
    });
  });

  group('StaticNotification', () {
    test('constructor stores all fields', () {
      final notif = StaticNotification(
        icon: FluentIcons.goto_today,
        title: 'Test Title',
        body: 'Test Body',
        actions: [
          NotificationAction(
            color: const Color(0xFF00FF00),
            label: 'OK',
            action: () {},
            hideOnRoute: '',
          ),
        ],
      );

      expect(notif.title, 'Test Title');
      expect(notif.body, 'Test Body');
      expect(notif.actions.length, 1);
    });

    test('allows empty actions list', () {
      final notif = StaticNotification(
        icon: FluentIcons.goto_today,
        title: 'No Actions',
        body: 'This notification has no actions',
        actions: [],
      );

      expect(notif.actions, isEmpty);
    });

    test('supports multiple actions', () {
      final notif = StaticNotification(
        icon: FluentIcons.goto_today,
        title: 'Multi',
        body: 'Body',
        actions: [
          NotificationAction(
            color: const Color(0xFFFF0000),
            label: 'A',
            action: () {},
            hideOnRoute: '',
          ),
          NotificationAction(
            color: const Color(0xFF00FF00),
            label: 'B',
            action: () {},
            hideOnRoute: '',
          ),
          NotificationAction(
            color: const Color(0xFF0000FF),
            label: 'C',
            action: () {},
            hideOnRoute: '',
          ),
        ],
      );

      expect(notif.actions.length, 3);
      expect(notif.actions[0].label, 'A');
      expect(notif.actions[2].label, 'C');
    });
  });

  group('staticNotifications service', () {
    test('addNotification adds to the notifications list', () {
      final initialCount = staticNotifications.notifications.length;

      staticNotifications.addNotification(
        StaticNotification(
          icon: FluentIcons.info,
          title: 'Test',
          body: 'Body',
          actions: [],
        ),
      );

      expect(
        staticNotifications.notifications.length,
        greaterThanOrEqualTo(initialCount + 1),
      );
    });

    test('notifications is a list of StaticNotification', () {
      expect(
        staticNotifications.notifications,
        isA<List<StaticNotification>>(),
      );
    });
  });
}

@Tags(['serial'])
library;

import 'package:apexo/app/routing/app_route.dart';
import 'package:apexo/core/synchronization/push_data.dart';
import 'package:apexo/services/notifications/listeners.dart';
import 'package:apexo/services/notifications/static_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    staticNotifications.clear();
    resetStaticNotificationDedupe();
  });

  group('NotificationAction', () {
    test('constructor stores all fields', () {
      bool tapped = false;
      final action = NotificationAction(
        color: const Color(0xFF0000FF),
        label: 'View',
        action: () => tapped = true,
        hideOnRoute: AppRoute.calendar,
      );

      expect(action.label, 'View');
      expect(action.hideOnRoute, AppRoute.calendar);
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
            hideOnRoute: null,
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
            hideOnRoute: null,
          ),
          NotificationAction(
            color: const Color(0xFF00FF00),
            label: 'B',
            action: () {},
            hideOnRoute: null,
          ),
          NotificationAction(
            color: const Color(0xFF0000FF),
            label: 'C',
            action: () {},
            hideOnRoute: null,
          ),
        ],
      );

      expect(notif.actions.length, 3);
      expect(notif.actions[0].label, 'A');
      expect(notif.actions[2].label, 'C');
    });
  });

  group('staticNotifications service', () {
    test('addNotification adds to the notifications list and bumps state', () {
      final initialCount = staticNotifications.notifications.length;
      final initialState = staticNotifications.state();

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
      expect(staticNotifications.state(), initialState + 1);
    });

    test('clear removes added notifications', () {
      staticNotifications.addNotification(
        StaticNotification(
          icon: FluentIcons.info,
          title: 'Test',
          body: 'Body',
          actions: [],
        ),
      );
      staticNotifications.clear();
      expect(
        staticNotifications.notifications.where((n) => n.title == 'Test'),
        isEmpty,
      );
    });

    test('notifications is a list of StaticNotification', () {
      expect(
        staticNotifications.notifications,
        isA<List<StaticNotification>>(),
      );
    });
  });

  group('dispatchStaticNotification & listener payload guards', () {
    test('deduplicates identical push notices within the dedupe window',
        () async {
      final push = PushData(
        store: 'appointments',
        id: 'appt-1',
        readableIdentifier: 'Ada Lovelace',
        isCreation: false,
        isUpdate: true,
        updatedFields: const ['date'],
        oldVals: const [100],
        newVals: const [200],
        targetIDs: const ['op1'],
      );

      final t0 = DateTime(2026, 1, 1, 12);
      expect(await dispatchStaticNotification(push, clock: t0), isTrue);
      expect(
        await dispatchStaticNotification(
          push,
          clock: t0.add(const Duration(seconds: 5)),
        ),
        isFalse,
      );
      expect(
        await dispatchStaticNotification(
          push,
          clock: t0.add(staticNotificationDedupeWindow),
        ),
        isTrue,
      );
    });

    test('tryParsePushPayload and pushPayloadOf reject missing/corrupt data',
        () {
      expect(tryParsePushPayload(null), isNull);
      expect(tryParsePushPayload(''), isNull);
      expect(tryParsePushPayload('not-json'), isNull);
      expect(tryParsePushPayload('[]'), isNull);

      expect(pushPayloadOf(const RemoteMessage()), isNull);
      expect(
        pushPayloadOf(const RemoteMessage(data: {'payload': ''})),
        isNull,
      );
      expect(
        pushPayloadOf(const RemoteMessage(data: {'payload': '{bad'})),
        isNull,
      );
    });

    test('foregroudRes tolerates null or invalid payload without throwing', () {
      expect(
        () => PushListeners.foregroudRes(
          const NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotification,
          ),
        ),
        returnsNormally,
      );
    });
  });
}

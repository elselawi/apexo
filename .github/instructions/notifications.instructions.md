---
description: Notifications architecture for Apexo — Firebase Cloud Messaging, local notifications, push relay via Cloudflare Worker, deferred push queue, and static in-app notifications. Applies when working with push notifications, FCM, notification listeners, or the relay server.
applyTo: "lib/services/notifications/**"
---

# Apexo Notifications Architecture

## Overview

Apexo has a **multi-layered push notification system** that works across Android, iOS, macOS, and Web:

```
┌──────────────────────────────────────────────────────────┐
│                    Notification Flow                      │
├──────────┬──────────┬──────────────┬─────────────────────┤
│  Store   │  FCM     │ Relay Server │  Device (App)       │
│ changes  │ (Firebase│ (Cloudflare  │                     │
│ trigger  │ Cloud    │  Worker)     │                     │
│  push    │ Msging)  │              │                     │
└──────────┴──────────┴──────────────┴─────────────────────┘
```

| Layer | File | Role |
|-------|------|------|
| **Push Data** | `lib/core/synchronization/push_data.dart` | Core-owned wire payload, with no delivery/UI imports — shared with `web/fcm/push_data.js` for web |
| **Push Interpretation** | `lib/services/notifications/push_interpretation.dart` | Interprets `PushData` into localized title/body pairs across all 10 supported locales — mirrored in `web/fcm/push_data.js` |
| **Push Generation** | `Store._processChangesForSession()` in `lib/core/store.dart` | Generates `PushData` from store changes based on `targetsToPushTo`, `pushIfChanged`, `pushOnCreation` |
| **Relay Client** | `lib/services/notifications/push_relay.dart` | Sends push payloads to the Cloudflare Worker relay at `apexo-notifications-relay.alisaleem.workers.dev` |
| **Deferred Queue** | `lib/services/notifications/push_deferring.dart` | Hive-persisted queue for pushes that couldn't be sent while offline |
| **FCM Service** | `lib/services/notifications/core_firebase_messaging.dart` | Firebase Cloud Messaging — token management, permission requests, foreground/background listeners |
| **Local Notifications** | `lib/services/notifications/core_local_notification.dart` | `flutter_local_notifications` — displays OS-level notifications on Android/iOS/macOS |
| **APNs Token Wait** | `lib/services/notifications/apns_token.dart` | `waitForAPNSToken()` — bounded retry for the APNs token iOS/macOS need before FCM issues a token |
| **Static Notifications** | `lib/services/notifications/static_notifications.dart` | In-app notification list — today's appointments, due labworks, pending notes, and received push notifications |
| **Initializer** | `lib/services/notifications/core_notifications_initializer.dart` | Orchestrates setup — calls Firebase init, FCM init, local notification init, device identification |
| **Listeners & Dispatch** | `lib/services/notifications/listeners.dart` | Handles foreground/background/tap events, deduplicates notices across FCM and sync, syncs stores, navigates to items |

## Initialization Flow

```
main() → Messaging.initializeReceiving()
  ├── Platform.isAndroid/iOS/macOS → Firebase.initializeApp() → FCM.init() → LocalNotifications.init()
  ├── FCM.init(): requestPermission() → foreground/background/tap listeners
  │     └── iOS/macOS: waitForAPNSToken() (10 reads, 500 ms apart) → getToken()
  │     └── Android: getToken()
  │     └── the token fetch is not awaited, so it never delays the first frame
  │     └── no APNs token / empty token: logged, not stored; onTokenRefresh registers the device later
  └── Web → handled by fcm/fcm.js (JS bridge)

After login → Messaging.identifyDevice()
  ├── PushRelay.ensureKey() — creates/retrieves relay key from PocketBase
  ├── Web: JSBridge.setGlobalVariable() → fcm.js handles token + registration
  └── Native (Android/iOS/macOS): PushRelay.putDevice() → registers FCM token and platform with relay server
```

`getToken()` is called without a `vapidKey` on native platforms — the VAPID key identifies a
web push subscription and lives in `web/fcm/constants.js` for `fcm.js`.

## What the Relay Sends Per Platform

`putDevice` records `platform` (`ios`, `macos`, `android`, `web`) with the token, and `/push`
shapes the message from it. Every push also carries `alert: {title, body}`, rendered on the
sending device by `displayTuple()` — the relay has no text of its own, so it is in the
**sender's** language.

| Token platform | Message | Displayed by |
|---|---|---|
| `ios` | `apns-push-type: alert`, `apns-priority: 10`, `aps.alert` + sound + badge, **no** `content-available` | iOS itself — works even when the app is closed or force-quit; tapping opens the app with `data` and `PushListeners.causedTheAppToOpen` navigates to the record |
| `macos` | `apns-push-type: background`, `content-available: 1` | the app, only while it runs |
| `android` | data-only, `android.priority: high` | the app (`foregroundMsg`/`backgroundMsg`) |
| `web` / unknown | data-only | the service worker |

An alert push deliberately omits `content-available`: the app is not woken, so it cannot post a
second notification for the same event. A device registered before `platform` existed gets the
silent push until its next login re-registers it.

## How Push Notifications Are Triggered

1. A `Store` detects changes in `_processChanges()`
2. For each changed document, it checks:
   - `pushOnCreation` — send on first create?
   - `pushIfChanged` — which field changes trigger a push?
   - `targetsToPushTo` — which user IDs should receive the push?
3. `PushRelay.sendPush()` POSTs to the relay Worker
4. The relay Worker looks up device tokens for target users and sends via FCM

## Model Integration

To make a Model support push notifications, override in your model:

```dart
class MyModel extends Model {
  @override
  bool get pushOnCreation => true;  // notify when first created

  @override
  List<String> get pushIfChanged => ["status", "assignedTo"];  // fields that trigger push

  @override
  List<String> get targetsToPushTo => [assignedToID];  // user IDs to notify

  @override
  Map<String, dynamic> get jsonCopyForPush => {
    "status": status,
    "assignedTo": assignedTo,
  };  // subset of data in push payload
}
```

## PushRelay Server

- **URL**: `https://apexo-notifications-relay.alisaleem.workers.dev`
- **Endpoints**: `/put-device`, `/replace-token`, `/push`
- **Auth**: Uses a `clinicKey` (stored in PocketBase collection `data` with ID `notifications_k`)
- **Key management**: `PushRelay.ensureKey()` generates a deterministic hash from `login.url + token + email + timestamp`

## Deferred Push Queue (`push_deferring.dart`)

When offline or if the relay is unreachable, pushes are stored in a Hive box keyed by clinic server hash. They're replayed when connectivity returns.

```dart
deferredPush.init(login.url);
deferredPush.putBulk(toPush);    // queue pushes
deferredPush.getByID(id);        // check a specific push
deferredPush.clearByStore(name); // clear all pushes for a store
```

## Platform-Specific Behavior

| Platform | FCM | Local Notifications | How Push Arrives |
|----------|-----|---------------------|------------------|
| **Android** | ✅ via `firebase_messaging` | ✅ via `flutter_local_notifications` | FCM → local notification |
| **iOS** | ✅ via `firebase_messaging` | ✅ via `flutter_local_notifications` | APNs alert (system displays it, app closed included) → tap opens the record |
| **Web** | ✅ via `fcm/fcm.js` (JS bridge) | ❌ | Service worker → `setGlobalVariable` → JS handles display |
| **Windows** | ❌ | ❌ | Only static in-app notifications + ding sound |
| **macOS** | ✅ via `firebase_messaging` | ✅ via `flutter_local_notifications` | APNs → FCM → local notification |

## Static In-App Notifications

The `_NotificationsService` in `static_notifications.dart` provides computed lists:
- `todayAppointmentsForYou` — today's appointments assigned to the current user
- `dueLabworks` — labworks due for the current user
- `notDeliveredLabworks` — patients with undelivered labworks
- `incomingPendingNotes` / `outgoingPendingNotes` — kanban notes assigned to/by the current user

These drive the notification bell in the app header and the static notifications widget.

## Web JS Bridge for Notifications

On web, instead of using the Flutter FCM plugin directly, notifications go through JavaScript:
1. `JSBridge.setGlobalVariable()` sets `clinicKey`, `clinicServer`, `accountId`, `lang` on `window`
2. `fcm/fcm.js` reads these globals, requests FCM permission, gets the token, and registers with the relay server
3. The service worker (`firebase-messaging-sw.js`) handles background push display

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Forgetting to call `Messaging.initializeReceiving()` | Must be called before `runApp()` in `main.dart` |
| Not calling `Messaging.identifyDevice()` after login | Device won't be registered with the relay server |
| Editing `lib/core/synchronization/push_data.dart` or `lib/services/notifications/push_interpretation.dart` without syncing `web/fcm/push_data.js` | Web push display will break — the JS file mirrors the Dart wire model, interpretations, and all 10 locale translations |
| Assuming notifications work on desktop | Browsers use the JS bridge, macOS uses FCM, and only Windows has static in-app notifications alone |
| Removing `com.apple.developer.aps-environment` from the macOS entitlements | Set to `development` in `DebugProfile.entitlements` and `production` in `Release.entitlements`; without it APNs never registers and no FCM token is issued |
| Calling `getToken(vapidKey: ...)` on native platforms | `vapidKey` is web-only — native calls take no key |
| Calling `getToken()` on iOS/macOS when no APNs token exists yet | It throws `apns-token-not-set`; `waitForAPNSToken()` first, and let `onTokenRefresh` pick up a late token |
| Expecting a Mac notification while the app is not running | macOS gets the silent `apns-push-type: background` push, so the app shows the notice itself; iOS gets an alert the system displays |
| Registering a device without `platform` | `putDevice` sends it, and the relay only sends iOS an alert; a token without it keeps the silent push |

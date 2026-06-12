---
description: Notifications architecture for Apexo — Firebase Cloud Messaging, local notifications, push relay via Cloudflare Worker, deferred push queue, and static in-app notifications. Applies when working with push notifications, FCM, notification listeners, or the relay server.
applyTo: "lib/services/notifications/**"
---

# Apexo Notifications Architecture

## Overview

Apexo has a **multi-layered push notification system** that works across Android, iOS, and Web:

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
| **Push Data** | `model_push_data.dart` | Serializable push payload — shared with `fcm/push_data.js` for web |
| **Push Generation** | `Store._processChanges()` in `core/store.dart` | Generates `PushData` from store changes based on `targetsToPushTo`, `pushIfChanged`, `pushOnCreation` |
| **Relay Client** | `push_relay.dart` | Sends push payloads to the Cloudflare Worker relay at `apexo-notifications-relay.alisaleem.workers.dev` |
| **Deferred Queue** | `push_deferring.dart` | Hive-persisted queue for pushes that couldn't be sent while offline |
| **FCM Service** | `core_firebase_messaging.dart` | Firebase Cloud Messaging — token management, permission requests, foreground/background listeners |
| **Local Notifications** | `core_local_notification.dart` | `flutter_local_notifications` — displays OS-level notifications on Android/iOS |
| **Static Notifications** | `static_notifications.dart` | In-app notification list — today's appointments, due labworks, pending notes |
| **Initializer** | `core_notifications_initializer.dart` | Orchestrates setup — calls Firebase init, FCM init, local notification init, device identification |
| **Listeners** | `listeners.dart` | Handles foreground/background/tap events — syncs stores, navigates to items |

## Initialization Flow

```
main() → Messaging.initializeReceiving()
  ├── Platform.isAndroid/iOS → Firebase.initializeApp() → FCM.init() → LocalNotifications.init()
  └── Web → handled by fcm/fcm.js (JS bridge)

After login → Messaging.identifyDevice()
  ├── PushRelay.ensureKey() — creates/retrieves relay key from PocketBase
  ├── Web: JSBridge.setGlobalVariable() → fcm.js handles token + registration
  └── Native: PushRelay.putDevice() → registers FCM token with relay server
```

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
| **iOS** | ✅ via `firebase_messaging` | ✅ via `flutter_local_notifications` | FCM → local notification |
| **Web** | ✅ via `fcm/fcm.js` (JS bridge) | ❌ | Service worker → `setGlobalVariable` → JS handles display |
| **Windows** | ❌ | ❌ | Only static in-app notifications + ding sound |
| **macOS** | ❌ | ❌ | Only static in-app notifications |

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
| Editing `model_push_data.dart` without syncing `fcm/push_data.js` | Web push display will break — the JS file mirrors this Dart model |
| Assuming notifications work on desktop | Only static in-app notifications work on Windows/macOS |

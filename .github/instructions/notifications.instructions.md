---
description: Apexo notifications — store-triggered pushes, the Cloudflare relay, FCM vs Windows WNS transports, the notification-session boundary, MSIX packaging, deduplication, and in-app notifications.
applyTo: "{lib/services/notifications/**,windows/runner/push_*,windows/runner/main.cpp,windows/runner/flutter_window.cpp,tools/patch_push_manifest.dart,tools/patch_msix_manifest.ps1,web/fcm/**,web/firebase-messaging-sw.js}"
---

# Apexo Notifications

## Layers

| File | Role |
|---|---|
| `lib/core/synchronization/push_data.dart` | Wire payload (`PushData`) — core-owned, no delivery/UI imports |
| `lib/services/notifications/push_interpretation.dart` | `PushData` → localized title/body in all 10 locales |
| `lib/core/store.dart` (`_processChangesForSession`) | Builds `PushData` from changed documents |
| `push_relay.dart` | Relay client: `ensureKey`, `putDevice`, `replaceToken`, `sendPush` |
| `push_deferring.dart` (`deferredPush`) | Hive queue of pushes that could not be sent |
| `core_notifications_initializer.dart` (`Messaging`) | `initializeReceiving()` at startup, `identifyDevice()` after login |
| `listeners.dart` (`PushListeners`) | `handlePushData()` — the transport-neutral core: sync, in-app notice, local toast, navigation |
| `core_firebase_messaging.dart`, `core_local_notification.dart`, `apns_token.dart` | FCM token/permission, `flutter_local_notifications`, bounded APNs token wait |
| `push_platform.dart` | `PushPlatform.current`: `wns`/`ios`/`macos`/`android`/`web`/`null` |
| `notification_session.dart` | `notificationSessions` — restoring/active/absent boundary |
| `windows_push*.dart`, `windows_notification_*.dart` | WNS transport, toast ids, app identity |
| `static_notifications.dart` | In-app list and computed lists |
| `web/fcm/*`, `web/firebase-messaging-sw.js` | Service worker, `fcm.js` and `push_data.js` |

## Flow

```
startup  → Messaging.initializeReceiving()
           Windows: local notifications + WindowsPush.startReceiving()
           Android/iOS/macOS: Firebase.initializeApp → FCM.init → local notifications
           Web: fcm.js through the JS bridge
after login → Messaging.identifyDevice()
           wns: WindowsPush.requestRegistration (returns at once; background work)
           web: PushRelay.ensureKey → JSBridge globals → fcm.js
           else: PushRelay.ensureKey → putDevice(platform: …)
store change → PushData → PushRelay.sendPush → relay → FCM or WNS → device
             → PushListeners.handlePushData()
```

`NotificationSessionCoordinator` publishes the boundary: `publishStaff(...)` after every store activator and before `SessionEvents.started()`; `publishPatient(...)` after the patient data load. Logout or a failed restore calls `invalidate()` / `markAbsent()`. **A non-empty login token is not readiness** — wait on `notificationSessions.waitForUsableSession()`. Never await `login.ready` inside `identifyDevice`: it runs inside that same load.

## Windows (WNS) — a separate transport

Phones, Apple platforms and web ride FCM; Windows does not. The app registers a **WNS channel URI** with the relay and receives the same `{"payload": "<PushData JSON>"}` envelope as a raw notification. Everything after that is shared with `handlePushData`.

| Channel | Call / event | Meaning |
|---|---|---|
| `MethodChannel("apexo/windows_push")` | `isSupported` | Build can use WNS |
| | `getChannelUri` | Cached or freshly acquired URI; `{"refresh": true}` forces a real WNS acquisition (a failed forced refresh returns `null`, never the stale URI) |
| | `getLaunchPayload` | `{"payload": …}` when a push launched the app |
| `EventChannel("apexo/windows_push/events")` | `onPush` | One envelope per received push |
| `MethodChannel("apexo/windows_push/lifecycle")` | `exitAfterPush` | Stop the hidden push process after display |

Lifecycle rules:

- Register only after the session boundary; first registration uses `refresh: false`. Resume and a 6-hour periodic check use `refresh: true`, because a cached URI cannot reveal early revocation.
- Registration retries (2/4/8/16/32 s) then logs once and waits for the next resume or start — never an infinite loop.
- `putDevice` succeeds only on `200 ok`; `400`/`5xx`/timeout is a failure to retry.
- One captured session snapshot per attempt, re-checked after every await, so account A cannot write account B's token. A request during a refresh coalesces into one follow-up pass.
- Logout forgets the tuple (URI, server, key, account, staff-vs-patient), cancels retries and ignores an in-flight refresh.
- A raw push or launch payload displays (`openedFromNotification: false`); only a toast click or launch-details activation navigates (`true`) and promotes the hidden window. A raw push must not navigate.
- WNS has no delivery receipt and `PushData` has no event id: duplicates cannot be detected. The only suppression is the launch payload vs. the same stream envelope within `staticNotificationDedupeWindow`; two identical stream pushes are both delivered.
- Native activation must attach `PushReceived`, then `Register()`, then read `GetActivatedEventArgs()` — a push that started the process is missed otherwise.
- Never call `PushNotificationManager::Unregister()`/`UnregisterAll()` on exit; revoke only the `PushReceived` token.

## Registration and delivery per platform

`POST /put-device` takes `{clinicServer, clinicKey, deviceToken, accountId, platform?}`. Only these `platform` values are accepted; anything else is `400 invalid platform`.

| Build | `platform` | Relay sends | Displayed by |
|---|---|---|---|
| Windows | `wns` | raw WNS (`X-WNS-Type: wns/raw`, `X-WNS-TTL: 86400`) | the app's Windows service |
| iOS | `ios` | APNs **alert** (`apns-priority: 10`, no `content-available`) | iOS itself, even force-quit; tap navigates |
| macOS | `macos` | APNs **background** (`content-available: 1`) | the app, only while running |
| Android | `android` | FCM data, high priority | the app |
| Web | `web` | FCM data | the service worker |
| Linux / unknown | omitted | relay default `fcm` | — |

Never invent a platform; a build that cannot identify itself omits the value. Every push also carries `alert: {title, body}` built by the **sender** (`displayTuple()`), so the text is in the sender's language.

## Packaging a push-capable MSIX

`msix:build` regenerates `AppxManifest.xml` and `msix:create` does build+pack, so a post-generation patch can never survive it. Use:

```powershell
powershell -ExecutionPolicy Bypass -File tools/patch_msix_manifest.ps1
```

It runs `flutter build windows --release` → `dart run msix:build --sign-msix false` → patch → `--verify` → `msix:pack --sign-msix false` → extract and verify again. `-SkipBuild`, `-SkipPack` (read-only verification), `-SkipFlutterBuild` (after `shorebird release windows`) and `-Store` exist. Flutter builds for the host architecture, so the script refuses a configured architecture that differs.

- `--sign-msix false` is required: without a certificate `msix` substitutes its test-certificate subject as `publisher`, changing the package family name and breaking the notification AUMID.
- Three different identifiers, never interchangeable: Azure **application (client) ID** `8f4d5ac1-5142-44fb-928a-6ce05c641dd0` (`CreateChannelAsync` `remoteId` and the push `com:Class Id`), local-toast **CLSID** `51fc2ec1-f21e-4b3c-9f2b-71c28c7b0f7e` (`WindowsNotificationIdentity.activationGuid`), and the **AUMID** `alisaleem.apexo.app_e460fpmm323ja!apexo`. Passing an object ID to `CreateChannelAsync` still yields a URI, but every WNS send then fails with `403`.
- `--verify` proves manifest consistency only (identity, AUMID, runtime dependency, both class ids, capabilities). It does not prove installation, activator registration or delivery. PFN is confirmed separately against an installed package via `Get-AppxPackage`.
- Windows package restore is part of `windows/CMakeLists.txt` configure (`windows/restore_windows_packages.ps1`), so a plain `flutter build windows` works from a clean checkout.

## Triggering and model hooks

`Store` checks each changed document for `pushOnCreation`, `pushIfChanged` and `targetsToPushTo`, then `PushRelay.sendPush()` posts to the relay, which resolves device tokens and fans out.

```dart
@override
bool get pushOnCreation => true;
@override
List<String> get pushIfChanged => ["status", "assignedTo"];
@override
List<String> get targetsToPushTo => [assignedToID];
@override
Map<String, dynamic> get jsonCopyForPush => {"status": status, "assignedTo": assignedTo};
```

Offline pushes are queued with `deferredPush.putBulk(...)` and replayed later (`getByID`, `clearByIDs`, `clearByStore`). Anything that changes `push_data.dart`, `push_interpretation.dart` or the locale texts **must** be mirrored in `web/fcm/push_data.js`.

Relay: `https://apexo-notifications-relay.alisaleem.workers.dev`, endpoints `/put-device`, `/replace-token`, `/push`, authenticated by the clinic key stored in PocketBase collection `data` under `notifications_k` (`PushRelay.ensureKey()`).

## In-app notifications

`_NotificationsService` (`static_notifications.dart`) computes `todayAppointmentsForYou`, `dueLabworks`, `notDeliveredLabworks`, `incomingPendingNotes`, `outgoingPendingNotes`, driving the header bell. `dispatchStaticNotification` adds a received push to the list, keyed by `staticNotificationKey` (`store|id|create-or-update|sorted field/old/new tuples`) for `staticNotificationDedupeWindow`; `resetStaticNotificationDedupe()` on logout. The list entry is deduplicated; a local toast is not.

## Common mistakes

| Mistake | Fix |
|---|---|
| Assigning `window.lang` from `fcm.js`'s `lang` setter | Re-enters the setter until the stack overflows — write `this.config.lang` |
| Editing `push_data.dart` / `push_interpretation.dart` only | Mirror `web/fcm/push_data.js` |
| Assuming Windows uses Firebase | It uses WNS + the Windows App SDK |
| Treating a raw WNS launch payload as a toast click | Raw delivery displays; only a click navigates |
| Awaiting `login.ready` in `identifyDevice` | Waits on itself — use `notificationSessions.waitForUsableSession()` |
| Treating a login token as proof stores are ready | Publish the boundary after activation / patient load |
| Registering a non-`https://*.notify.windows.com` URI | Relay answers `400 invalid WNS channel url` |
| Trusting a cached channel URI | Refresh with `refresh: true` on resume / periodic check |
| Reusing process-local notification ids | Use `WindowsNotificationIdAllocator` (the id is the toast Tag) |
| Reusing `activationGuid` as the push CLSID | Different identifiers |
| `getToken(vapidKey: …)` on native | `vapidKey` is web-only |
| `getToken()` on iOS/macOS before an APNs token | Throws — `waitForAPNSToken()` first, `onTokenRefresh` catches late tokens |
| Expecting a Mac notification while the app is closed | macOS gets a silent push; iOS gets an alert |
| `putDevice` fire-and-forget | It returns `true` only on `200 ok` |
| Packaging with `msix:create` after patching | Regenerates and drops the push contract |
| Measuring the WNS payload limit against `PushData` alone | The relay wraps it in `JSON.stringify`, which grows it |

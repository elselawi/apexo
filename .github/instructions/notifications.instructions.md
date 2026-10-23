---
description: Notifications architecture for Apexo — Firebase Cloud Messaging, Windows WNS via the Windows App SDK, local notifications, push relay via Cloudflare Worker, deferred push queue, and static in-app notifications. Applies when working with push notifications, FCM, WNS, notification listeners, the Windows push runner, MSIX packaging, or the relay server.
applyTo: "{lib/services/notifications/**,windows/runner/push_*,windows/runner/main.cpp,windows/runner/flutter_window.cpp,tools/patch_push_manifest.dart,tools/patch_msix_manifest.ps1,web/fcm/**}"
---

# Apexo Notifications Architecture

## Overview

Apexo has a **multi-layered push notification system** that works across Android, iOS, macOS, Windows, and Web:

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
| **Platform Identity** | `lib/services/notifications/push_platform.dart` | The `platform` value a device registers (`wns`, `ios`, `macos`, `android`, `web`, or `fcm`) — one place that decides it |
| **Windows Push** | `lib/services/notifications/windows_push.dart`, `windows_push_service.dart`, `windows_push_platform_*.dart` | Windows Notification Services transport: channel URI registration, `onPush` dispatch, launch payload, forced resume/periodic refresh. Conditional import keeps non-Windows builds free of the channel code |
| **Notification Session** | `lib/services/notifications/notification_session.dart` | Explicit restoring/active/absent boundary shared by login, patient side, WNS registration and toast clicks. A token alone is not readiness |
| **Windows Toast IDs** | `lib/services/notifications/windows_notification_id_allocator.dart` | Persistent positive 31-bit toast ids so separate hidden processes do not reuse the plugin's tag zero |
| **Windows Identity** | `lib/services/notifications/windows_notification_identity.dart` | App name, MSIX AUMID and the toast-activation GUID shared with the packaging task |
| **Local Notifications** | `lib/services/notifications/core_local_notification.dart` | `flutter_local_notifications` — displays OS-level notifications on Android/iOS/macOS/Windows |
| **APNs Token Wait** | `lib/services/notifications/apns_token.dart` | `waitForAPNSToken()` — bounded retry for the APNs token iOS/macOS need before FCM issues a token |
| **Static Notifications** | `lib/services/notifications/static_notifications.dart` | In-app notification list — today's appointments, due labworks, pending notes, and received push notifications |
| **Initializer** | `lib/services/notifications/core_notifications_initializer.dart` | Orchestrates setup — calls Firebase init, FCM init, local notification init, device identification |
| **Listeners & Dispatch** | `lib/services/notifications/listeners.dart` | `handlePushData()` is the transport-neutral core (sync, notice, local notification or navigation); `foregroundMsg`, `causedTheAppToOpen` and the Windows service all route into it. Also deduplicates notices across transports and sync |

## Initialization Flow

```
main() → Messaging.initializeReceiving()
  ├── Windows → LocalNotifications.init() → WindowsPush.startReceiving()
  │     └── native support probe, onPush subscription, launch-payload capture
  ├── Platform.isAndroid/iOS/macOS → Firebase.initializeApp() → FCM.init() → LocalNotifications.init()
  ├── FCM.init(): requestPermission() → foreground/background/tap listeners
  │     └── iOS/macOS: waitForAPNSToken() (10 reads, 500 ms apart) → getToken()
  │     └── Android: getToken()
  │     └── the token fetch is not awaited, so it never delays the first frame
  │     └── no APNs token / empty token: logged, not stored; onTokenRefresh registers the device later
  └── Web → handled by fcm/fcm.js (JS bridge)

After login → Messaging.identifyDevice()
  ├── PushPlatform.current decides the branch first:
  │     ├── wns   → WindowsPush.requestRegistration(isPatient) — returns immediately;
  │     │           the service waits for a published notification session and
  │     │           performs relay-key + channel + /put-device work in the background
  │     ├── web   → PushRelay.ensureKey() → JSBridge.setGlobalVariable() → fcm.js
  │     └── ios/macOS/android → PushRelay.ensureKey() → putDevice(platform: …)
  └── an unknown platform (null, e.g. Linux) omits the field; the relay keeps "fcm"

Session boundary → notificationSessions.publishStaff(...) / publishPatient(...)
  └── staff: after every store activator, before SessionEvents.started()
      patient: after data load/persist and launch.open(Open.patient)
  └── logout or a failed restore → notificationSessions.invalidate()/markAbsent()
```

`getToken()` is called without a `vapidKey` on native platforms — the VAPID key identifies a
web push subscription and lives in `web/fcm/constants.js` for `fcm.js`.

## Windows (WNS) — a transport of its own

Phones, Apple's platforms and the web all ride **FCM**; Windows does not. The Windows app
registers a **WNS channel URI** with the relay and receives the same
`{"payload": "<PushData JSON>"}` envelope as a raw notification. Everything after that is
shared: `PushListeners.handlePushData` turns the payload into a notice, a local notification
or navigation, regardless of transport.

### Native channel contract (implemented outside Dart)

| Channel | Call / event | Type | Meaning |
|---|---|---|---|
| `MethodChannel("apexo/windows_push")` | `isSupported` | `bool` | Whether this build can use WNS at all |
| | `getChannelUri` | `String?` | The WNS channel URI. No argument / `{"refresh": false}` returns an unexpired cached URI or acquires one; `{"refresh": true}` asks WNS for a fresh channel even when the cache is unexpired. A failed forced acquisition returns `null`, not the old URI presented as a renewal |
| | `getLaunchPayload` | `String?` | The `{"payload": …}` JSON when a push launched the app |
| `EventChannel("apexo/windows_push/events")` | `onPush` | `Stream<String>` | One `{"payload": …}` JSON per received push |
| `MethodChannel("apexo/windows_push/lifecycle")` | `exitAfterPush` | `bool` | Additive and optional: ends the hidden process Windows started for a push, once Dart finished displaying the payload. Ignored unless the process is still a hidden push activation |
| | `promoteToInteractive` | `bool` | Additive and optional: reveals a hidden push process, restores/foregrounds it, cancels timers and invalidates an already-queued exit |

Missing implementations are normal: a build without them answers `MissingPluginException`,
the service logs once and stays inert. `WindowsPushService` never logs the channel URI, the
device token or a payload — only the operation that failed and the error type.

### Native implementation (`windows/runner/push_notifications.*`)

- **Support gate**: `GetCurrentPackageFullName` → `PushNotificationManager::IsSupported()`.
  A build without package identity reports unsupported and never touches the Windows App SDK.
  This is an Apexo policy: the feature includes background/terminated activation, which needs
  identity and COM activation (Microsoft documents limited unpackaged push, not none).
- **Registration order**: attach `PushReceived` → `Register()` exactly once → only then
  `AppInstance::GetCurrent().GetActivatedEventArgs()`.
- **Channel**: `CreateChannelAsync(<Entra Object ID>)` on an owned MTA worker, bounded at **5
  minutes** (the official sample's limit) and then cancelled. That bound is shorter than the
  SDK's internal retry window; a later launch, resume or `getChannelUri` starts a fresh
  attempt. Requests coalesce; `null` on unsupported/unconfigured/failed/expired/timeout.
- **Threading**: only the platform thread touches the messenger. WNS callbacks and the worker
  post window messages. Validated callbacks that arrive before the HWND is attached wait in a
  separate bounded pre-window buffer; the pre-listen buffer holds at most 16 payloads after
  that (oldest dropped). Dart also bounds pushes waiting for a restoring session at 16; when
  full it drops the newest queued delivery because an older waiter has no cancellation handle.
- **Payloads**: one shared acceptance boundary (`IsAcceptedPayload`) enforces the size/UTF-8
  rules for both raw stream callbacks and launch bytes before either becomes a Flutter
  `String`; malformed payloads are dropped (logged by kind only, never content).
- **Shutdown**: a hidden activation destroys the window before the process exits, so
  `Shutdown` revokes the `PushReceived` token, joins the owned worker, removes queued owned
  messages, completes every pending method result and releases the messenger/sink while the
  HWND and engine still exist. `Unregister()`/`UnregisterAll()` are deliberately **not**
  called — 1.7 documents them as removing the registration, which would stop the next
  background activation after the app closes.
- **Ordinary second launch**: the duplicate forwards a registered promotion message to the
  primary window before starting push registration, and exits only after the primary
  acknowledges. A notification COM server skips that gate so its activation payload is not
  discarded.

### Hidden push activation

A process started by a push (`ExtendedActivationKind::Push`) runs the Flutter engine **without
showing the window**. Dart captures `getLaunchPayload` as soon as receiving starts (independently
of login), waits for a usable session, and dispatches it with
`openedFromNotification: false` so `handlePushData` posts the localized toast; it never treats
raw delivery as a click or navigates. `exitAfterPush` is called only after the display work
completes. Shutdown is bounded: 2 s after Dart acknowledged it, 60 s after the payload was read
if Dart never calls back (long enough for the 60 s session wait), and a 90 s hard cap. The
activation deferral is completed exactly once.

A genuine toast click follows the other path: the local-notifications callback or its
launch-details recovery promotes/reveals the window first (when this is the hidden push
process), waits for the session, then calls `handlePushData(..., openedFromNotification: true)`
to navigate without showing a second toast. A cold click is retained rather than dropped while
the session restores, and the callback vs. launch-details recovery is deduplicated.

### Windows lifecycle

| Moment | What happens |
|---|---|
| Startup (`initializeReceiving`) | Local notifications + `WindowsPush.startReceiving`; native support, stream subscription and launch-payload capture. No Firebase and no registration |
| After login (`identifyDevice`) | `requestRegistration` only; the service waits for the session boundary, then resolves the relay key, calls `getChannelUri` (`refresh: false` on first registration), and POSTs `/put-device` with `platform: "wns"` when the URI or its context changed |
| Foreground/raw push (stream or launch payload) | Parsed with `tryParsePushEnvelope`, dispatched as `handlePushData(…, openedFromNotification: false)`; a raw launch acknowledges `exitAfterPush` only after that display future completes |
| Toast click | Promotes a hidden instance, waits for the session, dispatches `handlePushData(…, openedFromNotification: true)`; never posts a second toast |
| App resume | `getChannelUri` with `{"refresh": true}`; WNS is asked again even if the cached URI is unexpired, and a replacement URI is registered |
| While the app runs | The same forced re-check every 6 hours, so an early-revoked URI is replaced without waiting for a restart |
| Channel missing or registration refused | Retried at most `WindowsPushService.registrationRetryDelays` (2 s, 4 s, 8 s, 16 s, 32 s), then logged once and left to the next resume or app start — no infinite loop, no silent failure |
| Logout / account switch | `notificationSessions.invalidate()` resolves waiters as absent and stops session work. The registration tuple (URI, clinic server, clinic key, account, patient-vs-staff) is forgotten, every retry is cancelled, and an in-flight refresh is ignored when it completes. Works for staff and patient logout |
| Repeated `identifyDevice` | Records the latest requested session kind; one subscription, one lifecycle observer, and coalesced registration |

`PushRelay.registerDeviceSnapshot` returns whether the relay answered `200 ok`; a `400` (wrong
clinic key, invalid WNS channel URL), a `5xx` or an unexpected body is a failure the Windows
service retries. Network errors and the bounded request timeout are retried the same way. The
registration uses one captured session snapshot and checks that session is still current after
every await, so a completion for account A cannot write account B's token or tuple. A request
that arrives while a refresh is running is coalesced into one follow-up pass, not lost.

`login.ready` is **not** awaited by the Windows service. `identifyDevice` runs inside that very
load, so awaiting it there would wait on itself. Pushes and cold clicks wait on the explicit
`NotificationSessionCoordinator` boundary, which is published only after the store activators
(staff) or the patient data load (patient) finish, or completed as absent on logout/failure.

### Expiry, revocation and delivery guarantees

- The native side drops a cached URI whose `ExpirationTime` has passed and requests a new one;
  the in-memory cache means every app start asks WNS again.
- A resume or the 6-hour check calls `getChannelUri` with `refresh: true`, which performs an
  actual WNS acquisition even when the cached URI is unexpired. A revoked-but-unexpired URI is
  therefore replaced on the next trigger; reading the native cache alone would not detect it.
  The relay still has to learn that the old URI is invalid from its own WNS send (for example a
  `410`), and the device cannot observe that directly.
- There is no delivery receipt or at-least-once guarantee: WNS may drop a notification while the
  device is offline (the relay uses a 24 h TTL), and a duplicate cannot be detected because
  `PushData` carries no event id.

### Deduplication

`PushData` has no notification id, so identical payloads can be legitimate. The Windows
service suppresses exactly one case: the launch payload and a stream event that carry the
same envelope within `staticNotificationDedupeWindow`, in either arrival order (launch first,
or the stream winning the race). Two identical stream-only pushes are both delivered.

The **in-app notice** is deduplicated separately: `dispatchStaticNotification` keys on
`staticNotificationKey` (`store|id|create-or-update|sorted fields`) for
`staticNotificationDedupeWindow`, so a redelivery does not add a second list entry. The **local
toast** is not deduplicated — a genuine redelivery shows a second toast. Suppressing that would
need an event id in the wire format, which the payload does not have.

## Registration platform values

`POST /put-device` takes `{clinicServer, clinicKey, deviceToken, accountId, platform?}`. The
relay accepts only these `platform` values; anything else is `400 invalid platform`.

| Build | `platform` sent | Transport |
|---|---|---|
| Windows | `wns` | raw WNS notification |
| iOS | `ios` | FCM, shaped into an APNs alert |
| macOS | `macos` | FCM, shaped into a silent APNs background push |
| Android | `android` | FCM data, high priority |
| Web | `web` (posted by `fcm.js`) | FCM data |
| Linux / unknown | **omitted** | relay default `fcm` |

`fcm` also stays the `putDevice` default for callers that do not name a platform, and omitting
the field is the same to the relay. Never invent an OS: a build that cannot identify itself
omits the value rather than claiming one. `replaceToken` keeps its old behaviour, including
recording the current platform when the old token was empty.

## What the Relay Sends Per Platform

`putDevice` records `platform` with the token, and `/push` shapes the message from it. Every
push also carries `alert: {title, body}`, rendered on the sending device by
`displayTuple()` — the relay has no text of its own, so it is in the **sender's** language.

| Token platform | Message | Displayed by |
|---|---|---|
| `wns` | raw WNS notification (`X-WNS-Type: wns/raw`, `application/octet-stream`, `X-WNS-TTL: 86400`), body `JSON.stringify(data)` | the app's Windows service → `handlePushData` |
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
4. The relay Worker looks up device tokens for target users and sends via FCM (or WNS for a
   `wns` device)

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
| **Windows** | ❌ (WNS instead) | ✅ via `flutter_local_notifications` | WNS raw notification → `WindowsPushService` → `handlePushData` → local notification or navigation |
| **macOS** | ✅ via `firebase_messaging` | ✅ via `flutter_local_notifications` | APNs → FCM → local notification |

## Windows notification identity and activation contracts

Four identifiers are involved. They are different values with different jobs and must never
be substituted for one another:

| Identifier | Value | Used by |
|---|---|---|
| Entra **Object ID** | `431f890b-3a77-4d0b-b52a-aa684ffed80d` (`APEXO_WNS_OBJECT_ID`) | `CreateChannelAsync` only |
| Azure **application (client) ID** | `8f4d5ac1-5142-44fb-928a-6ce05c641dd0` (`APEXO_WNS_APP_ID`) | push COM `com:Class Id`, and the PFN→AppId mapping request to Microsoft |
| Local-toast **CLSID** | `51fc2ec1-f21e-4b3c-9f2b-71c28c7b0f7e` (`WindowsNotificationIdentity.activationGuid`) | `flutter_local_notifications_windows` + `msix_config.toast_activator` |
| **AUMID** | `alisaleem.apexo.app_e460fpmm323ja!apexo` | `<PackageFamilyName>!<Application Id>` |

Both activation servers use the same executable but different contracts:

| Contract | `Arguments` | `com:Class Id` | Generated by |
|---|---|---|---|
| Local toast | `----AppNotificationActivationServer` | toast CLSID | `msix` (`toast_activator` in `pubspec.yaml`) |
| WNS push | `----WindowsAppRuntimePushServer:` | application (client) ID | `tools/patch_push_manifest.dart` |

## Packaging a push-capable MSIX (verified against `msix` 3.16.13)

`msix:build` **regenerates** `AppxManifest.xml` from `pubspec.yaml`, and `msix:pack` only packs
what is on disk (it also deletes the manifest afterwards). `msix:create` is build + pack in one
step, so **a post-generation patch can never survive `msix:create`** — use this instead:

```powershell
powershell -ExecutionPolicy Bypass -File tools/patch_msix_manifest.ps1
```

The script enters the repository root for every command (and restores the caller's directory in
a `finally`), fails on the first non-zero exit, and runs `flutter build windows --release` →
`dart run msix:build --sign-msix false --architecture <architecture>` → patch → `--verify` →
`dart run msix:pack --sign-msix false --architecture <architecture>` → extract → `--verify` the
packaged manifest. Flutter's Windows build has no architecture flag — it builds the host
architecture — so the script refuses a configured architecture different from the host rather
than silently packing the wrong target. The build folder is resolved **after** generation, and
a normal run only accepts a `.msix` newer than the run start and newer than the patched
manifest.

- `-SkipBuild` reuses the build folder and still patches/packs; it requires the manifest to be
  newer than the executable.
- `-SkipPack` is a **read-only verification branch**: it never runs Flutter, `msix:build` or the
  patcher, never rewrites/deletes the package or its inputs, and never compares against a
  manifest time. It requires the existing package at the configured output path, extracts and
  verifies the packaged manifest, and reports that it reused the package because reuse does not
  prove the artifact matches current sources.
- `-SkipFlutterBuild` skips only the Flutter step; manifest generation and packing still run.
  This is the mode to use after `shorebird release windows`: it packages the Shorebird build
  output instead of overwriting it with the local Flutter SDK.
- `-Store` passes `--store` to the `msix` tool (unsigned Store package with the configured
  Partner Center identity) instead of the local `--sign-msix false` mode.

`msix:create` must not be used for a patched package.

### `--sign-msix false` is not optional here

With signing enabled and no `certificate_path`, `msix` falls back to its bundled
**test certificate** and rewrites `publisher` with that certificate's subject
(`CN=Msix Testing, …`). The publisher decides the package family name, so the resulting package
would **not** be `alisaleem.apexo.app_e460fpmm323ja` and the notification AUMID would point at a
package that does not exist. `--sign-msix false` keeps `msix_config.publisher`, which is why the
development flow uses it. Release signing is a separate concern: a real certificate whose subject
is exactly `CN=275027E7-AE47-4DEE-B3D6-0BE5AF8D773E` produces the same publisher automatically.

A missing local certificate is never a reason to change the configured publisher.

### What `--verify` proves, and what it does not

`--verify` proves **manifest consistency**: `Identity` name and publisher match `pubspec.yaml`,
`Application/@Id` and the AUMID agree, the runtime dependency is
`Microsoft.WindowsAppRuntime.1.7` / `7000.498.2246.0` / Microsoft's publisher, the toast CLSID is
the value in `windows_notification_identity.dart` and `msix_config.toast_activator.clsid`, the push
class id is the Azure application id, and `internetClient` + `rescap:runFullTrust` are declared.

It does **not** recompute the package family name. The Windows publisher hash is not reproducible
from published material, so the script confirms it separately against an **installed** package:
`Get-AppxPackage -Name alisaleem.apexo.app` filtered to the expected publisher, highest version
first. No installed package (or none with that publisher) prints `PFN not confirmed` and the
pipeline still succeeds, so clean machines work; a matching publisher whose family hash differs is
a real contradiction and fails.

Neither of those proves the package installs, that Windows registers the activators, or that WNS
delivers anything — and `Get-AppxPackageManifest` only works on an installed package. Those are
separate integration tests.

The dependency values come from the Windows App SDK NuGet package itself
(`tools/MSIX/win10-x64/Microsoft.WindowsAppRuntime.1.7.msix` inside
`windows/packages/Microsoft.WindowsAppSDK`, cross-checked with `WindowsAppSDK-VersionInfo.json`),
not from documentation guesswork. `MakeAppx unpack` + `pack` on the extracted tree is **structural**
validation only.

**PFN mapping**: before WNS delivers a single notification, Microsoft must map the package family
name to the application id (email Win_App_SDK_Push@microsoft.com — processed weekly). Until then
`CreateChannelAsync` fails and `getChannelUri` stays `null`.

### Building the native side

`windows/restore_windows_packages.ps1` validates the pinned packages from
`windows/packages.config` (Windows App SDK `1.7.250513003`, C++/WinRT, SDK BuildTools, WIL)
against their nuspec identity/version and the content the build actually consumes, then restores
only missing/incomplete/mismatched entries into `windows/packages` (git-ignored). The
`windows/CMakeLists.txt` configure step runs this restore, so a direct `flutter build windows`
works from a clean checkout without a separate packaging step; packaging does not duplicate it.
The runner CMake generates the C++/WinRT projections with the Windows SDK's `cppwinrt.exe`,
fingerprints the generator/SDK/package inputs and both required output headers, and regenerates
a partial or stale projection tree. A missing package fails configure with the exact path.

`--diagnose-push` reports `package identity`, `isSupported`, `channel configured` and
`registered` without starting Flutter (and never prints a URI, token or payload).

### Manual checks after installing the packaged app

1. `--diagnose-push` reports `package identity: yes`, `isSupported: true`.
2. Sign in; `/put-device` receives `platform: "wns"` with the channel URI.
3. Send a raw push through the relay: a foreground notice appears, and the in-app list is
   updated once (no duplicate). A raw push must not navigate.
4. Close the app, send a push: the app starts hidden, posts the localized toast, and exits.
5. Click the toast: the app opens the record it is about.
6. Send a push, then launch the app from the Start menu while the hidden process still exists:
   the existing instance is revealed rather than an "already running" error, and no second
   window remains.
7. Click the toast while the hidden process still exists: the window is revealed and navigates;
   the pending hidden exit does not close it.
8. Send two pushes that produce different toasts: both remain in the notification centre (the
   second does not replace the first).
9. After an orderly exit, another push still activates the app (no `Unregister*` call).
10. Reopen after 30 days (or clear the channel) and confirm a new URI re-registers; a resume and
    the periodic check request `refresh: true`.

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
| Assuming Windows uses Firebase | Windows has no Firebase at all: it registers a WNS channel and receives raw payloads through `WindowsPushService` |
| Treating a raw WNS launch payload as a toast click | Raw delivery must display (`openedFromNotification: false`); only a local-toast callback/launch-details click navigates and promotes the hidden window |
| Awaiting `login.ready` inside `identifyDevice`/`WindowsPushService` | `identifyDevice` runs inside that load; awaiting it waits on itself. Use `notificationSessions.waitForUsableSession()` after the activator/patient boundary |
| Treating a nonempty login token as proof stores are ready | Publish session readiness only at the end of staff activation or after patient data load; invalidate on both logout paths |
| Registering a WNS channel with a non-`https://*.notify.windows.com` URI | The relay rejects it with `400 invalid WNS channel url`; only `getChannelUri` values belong there |
| Assuming a cached channel proves WNS did not revoke it | Resume/periodic refresh must pass `refresh: true`; a cache read cannot detect early revocation |
| Reusing the process-local notification id on Windows | The Windows plugin uses the numeric id as the toast Tag; use `WindowsNotificationIdAllocator` so separate hidden processes do not replace tag zero |
| Reusing `activationGuid` as the WinAppSDK push CLSID or an Entra client id | They are different identifiers; see `windows_notification_identity.dart` |
| Comparing manifest activation executables by basename | Verify full normalized package-relative paths for both toast and push servers |
| Removing `com.apple.developer.aps-environment` from the macOS entitlements | Set to `development` in `DebugProfile.entitlements` and `production` in `Release.entitlements`; without it APNs never registers and no FCM token is issued |
| Calling `getToken(vapidKey: ...)` on native platforms | `vapidKey` is web-only — native calls take no key |
| Calling `getToken()` on iOS/macOS when no APNs token exists yet | It throws `apns-token-not-set`; `waitForAPNSToken()` first, and let `onTokenRefresh` pick up a late token |
| Expecting a Mac notification while the app is not running | macOS gets the silent `apns-push-type: background` push, so the app shows the notice itself; iOS gets an alert the system displays |
| Registering a device without `platform` | `putDevice` sends it, and the relay only sends iOS an alert; a token without it keeps the silent push |
| Treating `putDevice` as fire-and-forget | It returns `true` only when the relay answers `200 ok`; a `400`/`5xx` must be retried or the device silently stops receiving |
| Packaging with `msix:create` after patching | It regenerates `AppxManifest.xml` and silently drops the push contract; run `tools/patch_msix_manifest.ps1` |
| Running `msix:build`/`msix:pack` without `--sign-msix false` on a machine without the signing certificate | `msix` substitutes its test certificate subject as `publisher`, which changes the package family name; `--verify` fails with that hint |
| Installing a package only to run `Get-AppxPackageManifest` | That upgrades the user's installed app; verify the extracted manifest instead and query `Get-AppxPackage` for the observed PFN |
| Calling `PushNotificationManager::Unregister()`/`UnregisterAll()` on exit | 1.7 documents both as removing the registration, so the next push can no longer launch the app; only revoke the `PushReceived` token |
| Passing the Azure application (client) ID to `CreateChannelAsync` | It takes the Entra Object ID; the application ID is what the manifest's push `com:Class Id` must match |
| Reading `GetActivatedEventArgs()` before `Register()` | A push that started the process is missed; attach `PushReceived`, register, then read the activation |
| Treating a WNS push body as an XML toast template | The relay sends `Content-Type: application/octet-stream` with `X-WNS-Type: wns/raw`, so the body is the raw `{"payload": …}` JSON — the app builds its own toast |
| Measuring the WNS payload limit against the `PushData` JSON alone | The relay wraps it in `JSON.stringify(data)`, which escapes and grows it; size checks must count the serialized request body |

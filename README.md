# Apexo


Apexo is application intended for simple and easy management of dental clinics. Its free and open source. It supports patient management, appointment management, photo attachments, multiple doctors, multiple users, works offline, synchronizes through multiple devices, multi-lingual, secure, supports backups.

[Website](https://apexo.app) - [Demo](https://demo.apexo.app) - [Download](https://apexo.app/#getting-started) - [Documentation](https://docs.apexo.app)

> The following document is technical documentation for the Apexo project. If you are a user, or would like to use the application please visit the [Apexo website](https://apexo.app), or read through the [manual.md](https://github.com/elselawi/apexo/blob/master/manual.md).

## Contributing

All contribution are welcome, whether as a PR or issue. All I ask is to adhere to Github community standards.

### Members contributed
- [sealine 150, Greek localization](https://github.com/sealine150).
- [Sammy Habta, Spanish localization](https://github.com/dojosgithub)
- [Ar7in, Jalali calendar and Farsi localization](https://github.com/ar7in)

## Technology stack

This project uses [Dart](https://github.com/dart-lang/sdk) and [Flutter](https://github.com/flutter/flutter) to be able to run on multiple platforms from a single codebase. The design language is [Microsoft FluentUI](https://developer.microsoft.com/en-us/fluentui#/), as implemented thankfully [by Bruno D'Luka](https://github.com/bdlukaa).

The backend of this application should be [Pocketbase](https://pocketbase.io/).

I'm saying _"should"_ because I leave it up to the users to host their own backend. However, a cleanly installed pocketbase with a super user credentials would be enough to run this application since the application creates all the required collections and values on first login.

Check the [manual.md](https://github.com/elselawi/apexo/blob/master/manual.md) for how to install PocketBase.

In previous versions of apexo, [in an old github account of mine that I lost access to, and abandoned since then](https://github.com/alexcorvi/apexo), the tech-stack was quite different, Typescript/React to create a single page PWA and CouchDB as backend. However, with usage I have found that the web platform, although great for other application, was limiting for this application. So in summer 2024 I started a whole re-write of apexo and published it to my new github account.

- ___Can you migrate from that application to this one?___
   - __No you can't__, I'm sorry. This is a new release, the versioning isn't even a continuation from the old one.
   - However, I plan to support this version so that it will always be backwards compatible.

## Available platforms

- __Windows__: All features should/are tested and works (available on [Microsoft Store](https://apps.microsoft.com/detail/9n2j1h8dz6mt)).
- __Android__: All features should/are tested and works (available on [Google Play](https://play.google.com/store/apps/details?id=app.apexo.mobile)).
- __Web__: All features should/are tested and works (available on [web.apexo.app](https://web.apexo.app)).
- __iOS__: All features should/are tested and works (available on [App Store](https://apps.apple.com/us/app/apexo-app/id6767690393)).
- __MacOS__: All features should/are tested and works (available to [Download](https://apexo.app/#download)).

## Architecture and ownership

Apexo retains its custom observables, feature singletons, Hive storage and PocketBase protocol. The data infrastructure is organized by dependency and resource ownership:

| Location | Responsibility |
|---|---|
| `lib/core/model.dart` | Model identity/serialization and existing presentation metadata |
| `lib/core/reactive/observable_base.dart` | Standalone observable values and observer dispatch; Dart-only, no persistence or application imports |
| `lib/core/reactive/observable.dart` | Model dictionaries, immutable snapshots and JSON change detection |
| `lib/core/persistence/` | Hive/PocketBase adapters, persisted observable objects and the serial operation queue |
| `lib/core/synchronization/` | Pure conflict/deferred-key policy, push wire data, document loading and the store's application-effects contract |
| `lib/core/lifecycle/` | Session-owned callback registrations and drainable realtime subscriptions |
| `lib/core/store.dart` | Public document façade and synchronization orchestration |
| `lib/app/data/` | Application composition: concrete store effects, clinic-aware model loading, login binding and store initialization |
| `lib/features/<feature>/` | Feature models, queries/caches, screens and panel openers |
| `lib/services/notifications/` | Payload interpretation, outbox/relay delivery and platform/in-app notification presentation |
| `lib/utils/` | Existing platform adapters and shared helpers; not broadly relocated by this refactor |

**Dependency direction:** features/application composition depend on core; core does not import login, settings, notification delivery, error dialogs or application logging. A standalone `Store` has inert `StoreEffects` and a default model loader. Production feature stores explicitly supply `applicationStoreEffects` and `loadApplicationDocuments`; tests can supply recording effects/loaders without initializing login/settings. The app installs observable diagnostic callbacks at startup; primitive users can override reporters per instance.

**Resource owners:** each store has one `SerialOperationQueue` for document writes, sync passes and attachment operations. Caller-visible failures do not poison later operations, and draining includes work appended during completion. `RealtimeSubscription` owns pending registration, cancellation and the active subscription. The PocketBase adapter owns its connectivity retry timer. `StoreSessionBinding` serializes adapter replacement, invalidates the old session, drains store work before closing Hive, and owns the login/logout registration. A per-activation `SessionCallbacks` removes sync/reconnect/network callbacks on stop; callbacks copied by a dispatcher become inert, and old teardown cannot remove a successor's registration. Online second-stage callbacks check their activation identity before publishing registrations. Feature-specific demo seeding and post-sync work remain explicit callbacks rather than a generic feature template.

**Store correctness:** dictionary mutations synchronously register pending writes and update archive membership; public observers remain asynchronous. Logout snapshots pending documents into the old adapter's serial lane and journals them for the next synchronization before that adapter can be closed. Pulled rows are published into memory without replacing concurrently edited rows, so advancing the cursor does not leave unrelated remote updates invisible.

**Adding a persistent feature:** extend `Model`, retain the existing JSON format, extend `Store` with explicit production effects/loader, and own one `StoreSessionBinding` with the collection namespace, loading text and optional demo seed. Call its idempotent `install()` from `init()`, add feature-local caches/queries, and register the singleton in `lib/app/data/initialize_stores.dart`. For a standalone controller, import the observable base rather than a persisted object. For a new service, keep transport/platform effects out of reactive primitives; inject only the effects needed by independently tested logic.

**Panels:** `RowPanel` owns one independent `RowDraft`; `DelegatedPanel` delegates persistence and pending-edit checks to caller-managed drafts. Both implement the shared `Panel` host contract. This refactor leaves that existing separation and draft isolation unchanged.

**Compatibility and limits:** no Hive box/key, model JSON, deferred FILE encoding, PocketBase schema/cursor or push payload changes are required. All old import paths are replaced directly, with no compatibility barrels. The façade still orchestrates attachment reconciliation and conflict I/O; models still expose UI metadata and feature-specific authorization. Login, the notification outbox and AI token foundation remain application services with singleton coupling. Conflict resolution has no three-way baseline: prescriptions, tags and annotation maps use the timestamp winner's complete snapshot, preserving deletions but not losing-only additions. Operator unions and attachment reconciliation retain their specialized policies. Remote pulls use a fixed upper timestamp and `(updated, id)` keyset pagination within each pull; the persisted cursor remains a strict timestamp, so later writes sharing an already-saved timestamp still have the existing timestamp-cursor limitation. This is a bounded architecture refactor, not a new persistence/session protocol.

Dependency-boundary and owned-lifecycle tests in `test/unit/core/` prevent reintroducing application imports into core, persistence into primitive reactivity, and feature-local callback registration.

## Testing

### Unit tests

Run the deterministic suite serially, excluding live backends:

```powershell
flutter test test --exclude-tags live_backend -j 1
```

For the smaller deterministic unit partition:

```powershell
flutter test test\unit --exclude-tags live_backend -j 1
```

Tests share Hive and application singletons; use `-j 1`, including tests without a `serial` tag. Persistence tests should use isolated directories from `test/helpers/hive_setup.dart`.

Live-backend tests are separate and must be explicitly requested/configured. They require local credentials in `test/secret.dart` (based on `test/secret.dart.example`) and the `live_backend` tag; they are never part of the deterministic command above.

## Building & Distribution

- For the web:
   - Build with the command: `flutter build web --release`
   - deploy to wrangler: `wrangler pages deploy build/web --project-name=apexo-web`

- For android:
   - Run: `shorebird release --platforms android -- --build-number=X` (replace X with build number, check on shorebird: https://console.shorebird.dev/orgs/44512/apps/34dc240a-bfe8-40d0-937e-f069465f0165)
   - Upload: `build/app/outputs/bundle/release/app-release.aab` to play console.

- For MacOS
   - build with: `shorebird release --platforms macos -- --release`
   - then run: `cd macos && pod install` ("2 dependencies from the Podfile" and the "CocoaPods did not set the base configuration" warnings are expected: `printing` is the only plugin left on CocoaPods, everything else resolves through Swift Package Manager, and the Pods xcconfig is already included through `Flutter/Flutter-Debug.xcconfig` and `Flutter/Flutter-Release.xcconfig`, so nothing needs to be changed)
   - then open the macOS workspace from the repo root: `open macos/Runner.xcworkspace` (never `Runner.xcodeproj`, and never the workspace under `ios/`)
   - then go to product -> archive
   - after build finishes it will open a new window -> Distribute -> direct distribute (for notarization)
   - wait for the notification
   - export it (from the same window of "archives")
   - staple: `xcrun stapler staple apexo.app`
   - make sure it was successful: `spctl --assess --verbose apexo.app`
   - create a dmg: `create-dmg --volname "Apexo Installer" --window-pos 200 120 --window-size 800 400 --icon-size 100 --icon "Apexo.app" 200 190 --hide-extension "Apexo.app" --app-drop-link 600 185 "apexo-installer.dmg" "apexo.app"`
   - Notarize DMG: `xcrun notarytool submit apexo-installer.dmg --apple-id "ali.a.saleem@outlook.com" --team-id "8T5VB3M83P" --password "APP_SPECIFIC_PASSWORD" --wait` (replace app specific password with the app specific password from macos directory).
   - staple dmg: `xcrun stapler staple apexo-installer.dmg`
   - Upload it: `wrangler r2 object put apexo-releases/releases/0.10.6/Apexo-Installer.dmg --file=Apexo-Installer.dmg --remote`
   - Update the `metadata.json` and upload it: `wrangler r2 object put apexo-releases/metadata.json --file=metadata.json --remote`
   - troubleshooting:
      - `error: The sandbox is not in sync with the Podfile.lock` with `diff: .../Pods/Manifest.lock: No such file or directory`: look at the directory the error prints. A path under `ios/` (and a `Release-iphoneos` intermediate) means the **iOS** workspace was archived - close it and archive `macos/Runner.xcworkspace` instead.
      - `Multiple commands produce .../Sentry.framework` or `Target 'Runner' has copy command from ...`: the leftover `macos/Pods` was generated before the Swift Package Manager migration, so the old pods and Swift Package Manager both embed the same framework. Fix it with `rm -rf macos/Pods` (keep `Podfile.lock`) and re-run `flutter pub get`, `pod install` and the build.
      - `xcodebuild: error: Could not resolve package dependencies`: a dropped GitHub clone leaves a half-cloned repository in `build/macos/SourcePackages`. Re-run the build (repositories are cached in `~/Library/Caches/org.swift.swiftpm`), and if the big clones keep failing, set `git config --global http.version HTTP/1.1`.
      - after moving/renaming the project folder, Xcode keeps state pointing at the old location: delete the project's stale `~/Library/Developer/Xcode/DerivedData/Runner-*` folders and reopen the workspace (a build folder clean from Xcode is enough for the app products).

- For windows: (On a windows machine)
   - build with `shorebird release --platforms windows`
   - build msix: `dart run msix:create --store`
   - upload to ms store through microsoft partner
   
- For iOS:
   - build with `flutter build ipa --release --export-method app-store`
   - upload with transporter (build/ios/ipa) and deliver
   - continue on appstoreconnect `https://appstoreconnect.apple.com/apps/6767690393/distribution/ios/version/inflight`


## Support

Currently I'm not accepting any financial support for the development of this project. I'm developing it on my free time and using it in my own clinic.

If you insist to help:

- You can report issues or bugs.
- Submit PR request to improve the project.
- Pray for peace and better future in the middle east.


#### Built with ❤️ in Mosul, Iraq.

## License
GNU General Public License v3.0.
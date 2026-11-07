import 'package:apexo/core/persistence/observable_persisting_object.dart';
import 'dart:async';
import 'dart:convert';

import 'package:apexo/app/app_context.dart';
import 'package:apexo/services/session_events.dart';
import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/dialogs/dialog_styling.dart';
import 'package:apexo/features/accounts/accounts_controller.dart';
import 'package:apexo/features/login/login_controller.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/launch.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/network.dart';
import 'package:apexo/utils/constants.dart';
import 'package:apexo/utils/encode.dart';
import 'package:apexo/services/notifications/core_notifications_initializer.dart';
import 'package:apexo/services/notifications/listeners.dart';
import 'package:apexo/services/notifications/notification_session.dart';
import 'package:apexo/services/notifications/push_deferring.dart';
import 'package:apexo/services/notifications/static_notifications.dart';
import 'package:apexo/utils/init_pocketbase.dart';
import 'package:apexo/utils/logger.dart';
import 'package:apexo/utils/js/js_bridge.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:pocketbase/pocketbase.dart';

/// Callbacks invoked during [Login.logout], before credentials are cleared.
///
/// Services that need to tear down session-scoped resources (e.g. the DICOM
/// periodic timer) can register here without creating circular imports
/// between `lib/services/` and `lib/features/`.
final List<void Function()> onLogoutCallbacks = [];

class _LoginService extends ObservablePersistingObject {
  _LoginService(super.identifier);

  String url = "";
  String email = "";
  List<int> savedPermissions = Perm.zeroes;
  String token = "";
  String adminCollectionId = "__UNDEFINED__";
  String pushNotificationsToken = "";
  bool didAskForLoginAgain = false;

  // Tracks logout only: sync/reconnect callbacks stop when the user logs out.
  int _logoutRevision = 0;
  int get logoutRevision => _logoutRevision;

  /// Identifies the newest [activate] call.
  ///
  /// Incremented by every activation and by [logout]. Work that belongs to an
  /// older generation must stop before it mutates login state, the shared auth
  /// store, or the login screen — a late authentication response must never
  /// reopen a session that was logged out (or replaced by a newer login).
  int _activationGeneration = 0;

  bool _isCurrentActivation(int generation) =>
      generation == _activationGeneration;

  String get currentAccountID {
    if (launch.isDemo) {
      return accounts.list().isEmpty ? "" : accounts.list().first.id;
    }
    final findByEmail =
        accounts.list().where((x) => x.getStringValue("email") == email);
    if ((token.isEmpty || pb == null || pb!.authStore.record == null) &&
        findByEmail.isNotEmpty) {
      return findByEmail.first.id;
    } else if (pb != null && pb!.authStore.record != null) {
      return pb!.authStore.record!.id;
    } else {
      return "";
    }
  }

  // PocketBase instance
  PocketBase? pb;

  String get currentName {
    if (accounts.list().isEmpty) return "";
    final account = accounts.list().where((x) => x.id == currentAccountID);
    if (account.isEmpty) return "";
    return accounts.name(account.first);
  }

  List<int> get _permissions {
    if (launch.isDemo) return Perm.full;
    if (isAdmin) return Perm.full;
    if (network.isOnline()) {
      final currentAccountCandidates =
          accounts.list().where((r) => r.id == currentAccountID);
      if (currentAccountCandidates.isEmpty) return Perm.pad(savedPermissions);
      return Perm.parse(
          currentAccountCandidates.first.getStringValue("permissions"));
    }
    return Perm.pad(savedPermissions);
  }

  /// Fluent permission check — preferred over `permissions[index]`.
  ///
  /// ```dart
  /// login.perm(Perm.photos).none       // == 0
  /// login.perm(Perm.photos).some       // > 0
  /// login.perm(Perm.photos).full       // >= 2
  /// login.perm(Perm.expenses).exact(1) // == 1
  /// login.perm(Perm.patients).min(2)   // >= 2
  /// login.perm(Perm.appointments).not(2) // != 2
  /// ```
  PermLevel perm(int slot) => _permissions.perm(slot);

  bool get currentLoginIsOperator {
    final findByEmail =
        accounts.list().where((x) => x.getStringValue("email") == email);
    if (findByEmail.isEmpty) return false;
    return findByEmail.first.getIntValue("operate") == 1;
  }

  bool get isAdmin {
    final tokenSegments = token.split(".");
    if (tokenSegments.length == 3 &&
        decode(tokenSegments[1]).contains(adminCollectionId)) {
      return true;
    }

    if (pb == null) return false;
    if (pb!.authStore.isValid == false) return false;
    if (pb!.authStore.record == null) return false;
    return pb!.authStore.record!.collectionName == "_superusers";
  }

  void askForLoginAgain(Object e) {
    if (network.isOnline() == false) return;
    if (didAskForLoginAgain) return;
    if (launch.isDemo) return;
    if (launch.open() == Open.login) return;
    final strErr = e.toString();
    final authError = strErr.contains("401") ||
        strErr.contains("402") ||
        strErr.contains("403");
    if (e is ClientException && authError) {
      didAskForLoginAgain = true;
      unawaited(showDialog(
        context: bContext,
        barrierDismissible: false,
        dismissWithEsc: false,
        builder: (context) {
          return ContentDialog(
            style: dialogStyling(context, false),
            title: Txt(txt("loginRequired")),
            content: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: Txt(txt("loginRequiredDesc")),
            ),
            actions: [
              Button(
                child: ButtonContent(FluentIcons.signin, txt("login")),
                onPressed: () {
                  Navigator.pop(context);
                  logout(false);
                },
              ),
            ],
          );
        },
      ));
    }
  }

  void logout([bool cleanCredentials = true]) {
    _logoutRevision++;
    // In-flight activations stop at their next await: one may already hold a
    // valid auth response that must not be adopted after this point.
    _activationGeneration++;
    // Invalidate notification work before any state is cleared or a new session
    // can be published. This resolves waiters and stops registration retries.
    notificationSessions.invalidate();
    launch.open(Open.login);
    if (cleanCredentials) {
      url = "";
      email = "";
    }
    token = "";
    localSettings.aiToken = null;
    localSettings.aiTokenServer = '';
    localSettings.aiTokenExpiry = null;
    localSettings.notifyAndPersist();
    if (pb != null) {
      pb!.authStore.clear();
    }
    if (kIsWeb) {
      JSBridge.setGlobalVariable("accountId", "");
      JSBridge.setGlobalVariable("shouldShowPrompt", "no");
    }
    // Let registered services tear down session-scoped resources
    // (e.g. DICOM periodic timer) before we clear state.
    for (final cb in onLogoutCallbacks) {
      cb();
    }
    // The screen is the app's: it resets its route stack, closes its panels and
    // its windows. A service that authenticates a clinic must not know they
    // exist — it announces the end of the session and the app does the rest.
    SessionEvents.ended();
    // Deferred push is keyed by server URL — reset so the next login
    // opens the correct Hive box for the new server.
    deferredPush.reset();
    staticNotifications.clear();
    resetStaticNotificationDedupe();
    notifyAndPersist();
    return loginCtrl.finishedLoginProcess();
  }

  /// A private auth client with the same transport as [shared].
  ///
  /// Authentication runs on its own [PocketBase] (and therefore its own
  /// [AuthStore]) so a response that arrives after [logout], or after a newer
  /// activation, cannot write stale credentials into the shared store. Only
  /// [activate] and [authenticateWithToken] adopt a result, and only while
  /// their session is still current.
  PocketBase _newAuthClient(PocketBase shared) {
    return PocketBase(
      shared.baseURL,
      lang: shared.lang,
      httpClientFactory: shared.httpClientFactory,
    );
  }

  Future<({RecordAuth auth, bool admin})> _authenticateWithPasswordOn(
      PocketBase client, String email, String password) async {
    try {
      final auth = await client
          .collection("_superusers")
          .authWithPassword(email, password);
      return (auth: auth, admin: true);
    } catch (e) {
      final auth =
          await client.collection("users").authWithPassword(email, password);
      return (auth: auth, admin: false);
    }
  }

  Future<({RecordAuth auth, bool admin})> _authenticateWithTokenOn(
      PocketBase client, String inputToken) async {
    client.authStore.save(inputToken, null);
    if (client.authStore.isValid == false) {
      throw Exception("Invalid token");
    }
    try {
      return (
        auth: await client.collection("_superusers").authRefresh(),
        admin: true
      );
    } catch (e) {
      return (
        auth: await client.collection("users").authRefresh(),
        admin: false
      );
    }
  }

  /// Copies a successful authentication into the live session.
  void _adoptAuth({required RecordAuth auth, required bool admin}) {
    final client = pb;
    if (client == null) return;
    client.authStore.save(auth.token, auth.record);
    token = auth.token;
    if (admin) {
      adminCollectionId = auth.record.collectionId;
    } else {
      savedPermissions = Perm.parse(auth.record.getStringValue("permissions"));
    }
  }

  /// Refreshes the credentials of the **current** session.
  ///
  /// The request runs on a private client, so a response that lands after a
  /// logout cannot repopulate [pb]'s auth store. The refreshed credentials are
  /// committed only if the same session (same client, token, and activation)
  /// asked for them; otherwise [inputToken] is returned and nothing changes.
  Future<String> authenticateWithToken(String inputToken) async {
    final client = pb;
    if (client == null) {
      throw StateError('No PocketBase client is available to refresh.');
    }
    final generation = _activationGeneration;
    final result =
        await _authenticateWithTokenOn(_newAuthClient(client), inputToken);
    if (!_isCurrentActivation(generation) ||
        !identical(client, pb) ||
        token != inputToken) {
      return inputToken;
    }
    _adoptAuth(auth: result.auth, admin: result.admin);
    return result.auth.token;
  }

  /// run a series of callbacks that would require the login credentials to be active
  Future<void> activate(
      String inputURL, List<String> credentials, bool online) async {
    final generation = ++_activationGeneration;
    bool stale() => !_isCurrentActivation(generation);

    // A stale activation must not paint the login screen either: its loading
    // text is the only thing between the user and a usable form.
    void loading(String message) {
      if (!stale()) loginCtrl.loadingIndicator(message);
    }

    notificationSessions.beginRestoring();
    if ((pb == null || pb?.baseURL.isEmpty == true) ||
        launch.open() == Open.login) {
      pb = PocketBase(inputURL);
    }

    loading("Connecting to the server");
    if (!stale()) loginCtrl.loginError("");

    if (inputURL.isNotEmpty && !stale()) {
      url = inputURL;
    }

    if (online && launch.isDemo == false) {
      try {
        // Authentication runs on a private client so a response that lands
        // after logout (or after a newer login) cannot repopulate the shared
        // auth store. Only a current activation adopts the result.
        final authClient = _newAuthClient(pb!);

        // email and password authentication
        if (credentials.length == 2) {
          final result = await _authenticateWithPasswordOn(
              authClient, credentials[0], credentials[1]);
          if (stale()) return;
          _adoptAuth(auth: result.auth, admin: result.admin);
          email = credentials[0];
        }
        // token authentication
        if (credentials.length == 1) {
          final result =
              await _authenticateWithTokenOn(authClient, credentials[0]);
          if (stale()) return;
          _adoptAuth(auth: result.auth, admin: result.admin);
          url = inputURL;
        }

        // create database if it doesn't exist
        try {
          try {
            loading("Verifying collections");
            await pb!
                .collection(dataCollectionName)
                .getList(page: 1, perPage: 1);
            if (stale()) return;
            await pb!
                .collection(publicCollectionName)
                .getList(page: 1, perPage: 1);
            if (stale()) return;
          } on ClientException catch (e) {
            if (e.statusCode != 404) rethrow;
            if (stale()) return;
            launch.isFirstLaunch(true);
            if (isAdmin) {
              loading("Creating collections for the first time");
              await initializePocketbase(pb!);
              if (stale()) return;
            } else {
              logger(
                "ERROR: The first login must be done by an admin user. Please contact the admin to create the database.",
                StackTrace.current,
              );
            }
          }
        } catch (e) {
          throw Exception(
              "Error while creating the collection for the first time: $e");
        }

        // create profiles if it doesn't exist
        try {
          try {
            loading("Verifying profiles");
            await pb!
                .collection(profilesCollectionName)
                .getList(page: 1, perPage: 1);
            if (stale()) return;
            await pb!
                .collection(profilesViewCollectionName)
                .getList(page: 1, perPage: 1);
            if (stale()) return;
          } on ClientException catch (e) {
            if (e.statusCode != 404) rethrow;
            if (stale()) return;
            if (isAdmin) {
              loading("Creating profiles collections");
              await initializeProfiles(pb!);
              if (stale()) return;
            } else {
              logger(
                "ERROR: The profiles must be created with a logged-in admin, NOT a regular user!",
                StackTrace.current,
              );
            }
          }
        } catch (e) {
          throw Exception("Error while creating the profile collections: $e");
        }

        // Reconcile the server schema with the app's current collection
        // definitions (rules/fields) when an admin is logged in. This is
        // what ships rule changes to existing clinics. Pure upsert — it can
        // never delete anything, and a failure never blocks login.
        try {
          if (isAdmin) {
            loading("Updating server schema");
            await reconcileSchema(pb!, clinicServer: url);
            if (stale()) return;
          }
        } catch (e, s) {
          logger("Schema reconcile failed (continuing login): $e", s);
        }

        // notifications relay
        loading("Initializing notifications");
        try {
          await Messaging.identifyDevice();
          if (stale()) return;
        } catch (e, s) {
          logger("Could not initialize notifications: $e", s, 2);
        }
      } catch (e, s) {
        if (stale()) return;
        askForLoginAgain(e);

        if (e.runtimeType != ClientException) {
          loginCtrl.loginError("Error while logging-in: $e.");
        } else if ((e as ClientException).statusCode == 404) {
          loginCtrl.loginError(
              "Invalid server, make sure PocketBase is installed and running.");
        } else if (e.statusCode == 400) {
          loginCtrl.loginError("Invalid email or password.");
        } else if (e.statusCode == 0) {
          loginCtrl.loginError(
              "Unable to connect, please check your internet connection, firewall, or the server URL field.");
        } else {
          loginCtrl
              .loginError("Unknown client exception while authenticating: $e.");
        }
        logger("Could not login due to the following error: $e", s, 2);
        notificationSessions.markAbsent();
        return loginCtrl.finishedLoginProcess(loginCtrl.loginError());
      }

      if (stale()) return;
      loginCtrl.proceededOffline(false);
    } else if (!online) {
      // `proceededOffline` means "**this** session is the offline one": the
      // shell's sync action disables itself on it and the errors action becomes
      // a reconnect. It only defaulted to true on a cold start, so a login that
      // *proceeded offline* left it at whatever the last online login made it
      // (`false`) and the shell still offered a sync that could not work
      // (`login 09`).
      loginCtrl.proceededOffline(true);
    }

    if (stale()) return;
    // Initialize deferred push storage unconditionally (online OR offline)
    // so stores can safely defer push notifications before identifyDevice() runs.
    deferredPush.init(inputURL);

    for (var callback in activators.values) {
      if (stale()) return;
      try {
        final secondStage = await callback();
        if (stale()) return;
        if (online && launch.isDemo == false) await secondStage();
        if (stale()) return;
        notifyAndPersist(); // this would persist the data to the disk so we don't have to login again
      } catch (e, s) {
        if (stale()) return;
        logger("Error during running activators: $e", s);
      }
    }

    if (stale()) return;
    didAskForLoginAgain = false;
    launch.open(Open.staff);
    if (stale()) return;
    // Announce notification readiness only after every store activator has run.
    // A token is assigned before this point, so it cannot stand in for a usable
    // session; this publication is the boundary pushes wait on.
    final staffAccountId = currentAccountID;
    if (staffAccountId.isEmpty || pb == null || token.isEmpty || url.isEmpty) {
      notificationSessions.markAbsent();
    } else {
      // The snapshot must not share the mutable auth store of `login.pb`: a
      // background registration that resumes after an account switch would
      // otherwise send the next account's credentials with this snapshot.
      final notificationPb = PocketBase(url)..authStore.save(token, null);
      notificationSessions.publishStaff(
        server: url,
        accountId: staffAccountId,
        pocketBase: notificationPb,
        authToken: token,
        email: email,
      );
    }
    if (stale()) return;
    // The startup check runs from a one-second timer in `ApexoApp.createElement`
    // — *before* the login that creates a clinic can set `launch.isFirstLaunch`,
    // so the welcome dialog was unreachable (`login 12`). The check is idempotent:
    // it shows the changelog for a version the device has not seen, and the
    // welcome dialog only when this launch found no collections at all.
    SessionEvents.started();
    if (stale()) return;
    return loginCtrl.finishedLoginProcess();
  }

  /// activators are a series of callbacks that run after a successful login
  /// each activator function would first connect to local storage then return another callback
  /// the second callback (would be called only when online) connects to the server
  /// and synchronizes the local storage with the server
  Map<String, Future<Future<void> Function()> Function()> activators = {};

  @override
  Future<void> fromJson(Map<String, dynamic> json) async {
    url = json["url"] as String? ?? url;
    email = json["email"] as String? ?? email;
    token = json["token"] as String? ?? token;
    savedPermissions = json["savedPermission"] != null
        ? List<int>.from(
            jsonDecode(json["savedPermission"] as String) as List<dynamic>)
        : savedPermissions;
    adminCollectionId =
        json["adminCollectionId"] as String? ?? adminCollectionId;
    if (pushNotificationsToken.isEmpty) {
      pushNotificationsToken =
          json["pushNotificationsToken"] as String? ?? pushNotificationsToken;
    }
    if (token.isNotEmpty) {
      try {
        await activate(url, [token], true);
      } catch (_) {
        notificationSessions.markAbsent();
        rethrow;
      }
    } else {
      launch.open(Open.login);
      // A patient link can restore after the staff token was found absent. Give
      // that activation a short window to publish before resolving an early
      // launch/click waiter as absent; the capture below also makes sure a
      // login that starts in the meantime is not overwritten.
      final absentRevision = notificationSessions.revision;
      unawaited(Future<void>.delayed(const Duration(seconds: 10), () {
        if (notificationSessions.phase == NotificationSessionPhase.restoring &&
            notificationSessions.revision == absentRevision) {
          notificationSessions.markAbsent();
        }
      }));
    }
  }

  @override
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = {};
    json['url'] = url;
    json['email'] = email;
    json["token"] = token;
    json["savedPermission"] = jsonEncode(savedPermissions);
    json["adminCollectionId"] = adminCollectionId;
    json["pushNotificationsToken"] = pushNotificationsToken;
    return json;
  }
}

final login = _LoginService("main-state");

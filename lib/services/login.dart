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

/// Runs during `login.logout()` so services can tear down session-scoped
/// resources without `lib/services/` importing `lib/features/`.
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

  /// Incremented by every [activate] and by [logout]; work holding an older
  /// generation must stop, so a late auth response cannot reopen a dead session.
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
    _activationGeneration++;
    // Resolves notification waiters before any state changes, stopping registration retries.
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
    for (final cb in onLogoutCallbacks) {
      cb();
    }
    SessionEvents.ended();
    // Deferred push is keyed by server URL; reset so the next login opens the right box.
    deferredPush.reset();
    staticNotifications.clear();
    resetStaticNotificationDedupe();
    notifyAndPersist();
    return loginCtrl.finishedLoginProcess();
  }

  /// An auth client with its own [AuthStore], so a response arriving after
  /// [logout] or a newer activation cannot write stale credentials into [shared].
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

  /// Refreshes the current session's credentials; a response is adopted only if
  /// the same client, token and activation asked for it, else [inputToken] is returned.
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

    // A stale activation must not overwrite the loading text of the current one.
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

        // Ships schema/rule updates to existing clinics: pure upsert that never
        // deletes, and a failure never blocks login.
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
      // Marks this session as the offline one: the shell disables sync and turns
      // the errors action into a reconnect.
      loginCtrl.proceededOffline(true);
    }

    if (stale()) return;
    // Init online or offline so deferred pushes have a box when identifyDevice is skipped.
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
    // Publish readiness only after every activator ran: the token is assigned
    // earlier, so it cannot stand in for a usable session.
    final staffAccountId = currentAccountID;
    if (staffAccountId.isEmpty || pb == null || token.isEmpty || url.isEmpty) {
      notificationSessions.markAbsent();
    } else {
      // Must not share `login.pb`'s mutable auth store, or a registration that
      // resumes after an account switch would send the next account's credentials.
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
    // The startup dialog check runs from a one-second timer, before a login can
    // set `isFirstLaunch`; this session-start announcement is the second trigger.
    SessionEvents.started();
    if (stale()) return;
    return loginCtrl.finishedLoginProcess();
  }

  /// Login activators: each connects local storage, then returns a callback that
  /// syncs with the server and runs only when online.
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
      // A patient link can restore after the staff token was absent; wait 10 s
      // before resolving waiters as absent, unless a newer session changed revision.
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

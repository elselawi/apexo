import 'dart:convert';

import 'package:apexo/app/app.dart';
import 'package:apexo/app/routes.dart';
import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/dialogs/dialog_styling.dart';
import 'package:apexo/features/accounts/accounts_controller.dart';
import 'package:apexo/features/login/login_controller.dart';
import 'package:apexo/features/accounts/accounts_screen.dart';
import 'package:apexo/services/launch.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/network.dart';
import 'package:apexo/utils/constants.dart';
import 'package:apexo/utils/encode.dart';
import 'package:apexo/services/notifications/core_notifications_initializer.dart';
import 'package:apexo/services/notifications/push_deferring.dart';
import 'package:apexo/utils/init_pocketbase.dart';
import 'package:apexo/utils/logger.dart';
import 'package:apexo/utils/js/js_bridge.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import '../core/observable.dart';
import 'package:pocketbase/pocketbase.dart';

class _LoginService extends ObservablePersistingObject {
  _LoginService(super.identifier);

  String url = "";
  String email = "";
  List<int> savedPermissions = zeroPermissions;
  String password = "";
  String token = "";
  String adminCollectionId = "__UNDEFINED__";
  String pushNotificationsToken = "";
  bool didAskForLoginAgain = false;

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
    if (launch.isDemo) return fullPermissions;
    if (isAdmin) return fullPermissions;
    if (network.isOnline()) {
      final currentAccountCandidates =
          accounts.list().where((r) => r.id == currentAccountID);
      if (currentAccountCandidates.isEmpty) return savedPermissions;
      return accounts.parsePermissions(
          currentAccountCandidates.first.getStringValue("permissions"));
    } else {
      return savedPermissions;
    }
  }

  List<int> get permissions {
    // this is to avoid errors when adding new features that would add new slots in the permissions array
    return [..._permissions, 0, 0, 0, 0, 0];
  }

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
    final authError = strErr.contains("400") ||
        strErr.contains("401") ||
        strErr.contains("402") ||
        strErr.contains("403");
    if (e is ClientException && authError) {
      didAskForLoginAgain = true;
      showDialog(
        context: bContext,
        barrierDismissible: false,
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
      );
    }
  }

  void logout([bool cleanCredentials = true]) {
    launch.open(Open.login);
    if (cleanCredentials) {
      url = "";
      email = "";
      password = "";
    }
    token = "";
    if (pb != null) {
      pb!.authStore.clear();
    }
    if (kIsWeb) {
      JSBridge.setGlobalVariable("accountId", "");
      JSBridge.setGlobalVariable("shouldShowPrompt", "no");
    }
    notifyAndPersist();
    routes.panels([]);
    return loginCtrl.finishedLoginProcess();
  }

  Future<String> _authenticateWithPassword(
      String email, String password) async {
    try {
      final auth =
          await pb!.collection("_superusers").authWithPassword(email, password);
      adminCollectionId = auth.record.collectionId;
      return auth.token;
    } catch (e) {
      final auth =
          await pb!.collection("users").authWithPassword(email, password);
      savedPermissions =
          accounts.parsePermissions(auth.record.getStringValue("permissions"));
      return auth.token;
    }
  }

  Future<String> authenticateWithToken(String token) async {
    try {
      final auth = await pb!.collection("_superusers").authRefresh();
      adminCollectionId = auth.record.collectionId;
      return auth.token;
    } catch (e) {
      final auth = await pb!.collection("users").authRefresh();
      savedPermissions =
          accounts.parsePermissions(auth.record.getStringValue("permissions"));
      return auth.token;
    }
  }

  /// run a series of callbacks that would require the login credentials to be active
  Future<void> activate(
      String inputURL, List<String> credentials, bool online) async {
    if ((pb == null || pb?.baseURL.isEmpty == true) ||
        launch.open() == Open.login) {
      pb = PocketBase(inputURL);
    }

    loginCtrl.loadingIndicator("Connecting to the server");
    loginCtrl.loginError("");

    if (inputURL.isNotEmpty) {
      url = inputURL;
    }

    if (online && launch.isDemo == false) {
      try {
        // email and password authentication
        if (credentials.length == 2) {
          token =
              await _authenticateWithPassword(credentials[0], credentials[1]);
          email = credentials[0];
        }
        // token authentication
        if (credentials.length == 1) {
          pb!.authStore.save(credentials[0], null);
          if (pb!.authStore.isValid == false) {
            throw Exception("Invalid token");
          }
          token = await authenticateWithToken(token);
          url = inputURL;
        }

        // create database if it doesn't exist
        try {
          try {
            loginCtrl.loadingIndicator("Verifying collections");
            await pb!
                .collection(dataCollectionName)
                .getList(page: 1, perPage: 1);
            await pb!
                .collection(publicCollectionName)
                .getList(page: 1, perPage: 1);
          } catch (e) {
            launch.isFirstLaunch(true);
            if (isAdmin) {
              loginCtrl
                  .loadingIndicator("Creating collections for the first time");
              await initializePocketbase(pb!);
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
            loginCtrl.loadingIndicator("Verifying profiles");
            await pb!
                .collection(profilesCollectionName)
                .getList(page: 1, perPage: 1);
            await pb!
                .collection(profilesViewCollectionName)
                .getList(page: 1, perPage: 1);
          } catch (e) {
            if (isAdmin) {
              loginCtrl.loadingIndicator("Creating profiles collections");
              await initializeProfiles(pb!);
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

        // notifications relay
        loginCtrl.loadingIndicator("Initializing notifications");
        try {
          await Messaging.identifyDevice();
        } catch (e, s) {
          logger("Could not initialize notifications: $e", s, 2);
        }
      } catch (e, s) {
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
        return loginCtrl.finishedLoginProcess(loginCtrl.loginError());
      }

      loginCtrl.proceededOffline(false);
    }

    // Initialize deferred push storage unconditionally (online OR offline)
    // so stores can safely defer push notifications before identifyDevice() runs.
    deferredPush.init(inputURL);

    for (var callback in activators.values) {
      try {
        final secondStage = await callback();
        if (online && launch.isDemo == false) await secondStage();
        notifyAndPersist(); // this would persist the data to the disk so we don't have to login again
      } catch (e, s) {
        logger("Error during running activators: $e", s);
      }
    }

    didAskForLoginAgain = false;
    launch.open(Open.staff);
    return loginCtrl.finishedLoginProcess();
  }

  /// activators are a series of callbacks that run after a successful login
  /// each activator function would first connect to local storage then return another callback
  /// the second callback (would be called only when online) connects to the server
  /// and synchronizes the local storage with the server
  Map<String, Future<Future<void> Function()> Function()> activators = {};

  @override
  fromJson(Map<String, dynamic> json) async {
    url = json["url"] ?? url;
    email = json["email"] ?? email;
    token = json["token"] ?? token;
    savedPermissions = json["savedPermission"] != null
        ? List<int>.from(jsonDecode(json["savedPermission"]))
        : savedPermissions;
    adminCollectionId = json["adminCollectionId"] ?? adminCollectionId;
    pushNotificationsToken =
        json["pushNotificationsToken"] ?? pushNotificationsToken;
    loginCtrl.urlField.text = url;
    loginCtrl.emailField.text = email;
    if (token.isNotEmpty) {
      await activate(url, [token], true);
    } else {
      launch.open(Open.login);
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

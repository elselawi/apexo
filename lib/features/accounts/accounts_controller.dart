import 'dart:convert';

import 'package:apexo/core/observable.dart';
import 'package:apexo/services/launch.dart';
import 'package:apexo/utils/constants.dart';
import 'package:apexo/utils/demo_generator.dart';
import 'package:apexo/utils/logger.dart';
import 'package:apexo/services/login.dart';
import 'package:pocketbase/pocketbase.dart';

class _Accounts extends ObservablePersistingObject {
  final list = ObservableState(
      List<RecordModel>.from(launch.isDemo ? demoAccounts(10) : []));
  final loaded = ObservableState(false);
  final loading = ObservableState(false);
  final creating = ObservableState(false);
  final errorMessage = ObservableState("");
  final updating = ObservableState(Map<String, bool>.from({}));
  final deleting = ObservableState(Map<String, bool>.from({}));

  String _collName(bool isAdmin) {
    return isAdmin ? "_superusers" : "users";
  }

  Future<void> newAccount({
    required bool isAdmin,
    required String email,
    required String password,
    required String name,
    required List<int> permissions,
    required bool operates,
  }) async {
    errorMessage("");
    creating(true);
    try {
      final created =
          await login.pb!.collection(_collName(isAdmin)).create(body: {
        "email": email,
        "password": password,
        "passwordConfirm": password,
        "verified": true,
      });
      final id = created.id;
      await login.pb!.collection(profilesCollectionName).create(body: {
        "account_id": id,
        "name": name,
        "permissions": jsonEncode(permissions),
        "operate": operates
      });
    } catch (e) {
      errorMessage((e as ClientException).response.toString());
    }

    await reloadFromRemote();
    creating(false);
  }

  Future<void> delete({required bool isAdmin, required String id}) async {
    errorMessage("");
    deleting(deleting()..addAll({id: true}));
    await login.pb!.collection(_collName(isAdmin)).delete(id);
    deleting(deleting()..remove(id));
    await reloadFromRemote();
  }

  Future<String> _getProfileIdByAccountID(String userID) async {
    try {
      final record = await login.pb!
          .collection(profilesCollectionName)
          .getFirstListItem('account_id = "$userID"');
      return record.id;
    } catch (e) {
      return "";
    }
  }

  Future<void> update({
    required String id,
    required bool isAdmin,
    required String email,
    required String password,
    required String name,
    required List<int> permissions,
    required bool operates,
  }) async {
    errorMessage("");
    updating(updating()..addAll({id: true}));
    try {
      await login.pb!.collection(_collName(isAdmin)).update(id, body: {
        "email": email,
        "verified": true,
        if (password.isNotEmpty) "password": password,
        if (password.isNotEmpty) "passwordConfirm": password,
      });

      final profileBody = {
        "account_id": id,
        "name": name,
        "permissions": jsonEncode(permissions),
        "operate": operates
      };
      final profileId = await _getProfileIdByAccountID(id);
      if (profileId.isEmpty) {
        await login.pb!
            .collection(profilesCollectionName)
            .create(body: profileBody);
      } else {
        await login.pb!
            .collection(profilesCollectionName)
            .update(profileId, body: profileBody);
      }
    } catch (e) {
      errorMessage((e as ClientException).response.toString());
    }
    updating(updating()..remove(id));
    await reloadFromRemote();
  }

  Future<void> reloadFromRemote() async {
    if (login.pb == null ||
        login.token.isEmpty ||
        login.pb!.authStore.isValid == false) {
      return;
    }
    loading(true);
    try {
      list(
          await login.pb!.collection(profilesViewCollectionName).getFullList());
    } catch (e, s) {
      login.askForLoginAgain(e);
      logger("Error when getting full list of accounts service: $e", s);
    }
    loaded(true);
    loading(false);
    notifyAndPersist();
  }

  List<int> parsePermissions(String str) {
    if (str.isEmpty) str = "[0,0,0,0,0,0,0,0]";
    return List<int>.from(jsonDecode(str))..addAll([0, 0, 0, 0]);
  }

  String name(RecordModel account) {
    final name = account.getStringValue("name");
    if (name.isNotEmpty) {
      return name;
    } else {
      return account.getStringValue("email");
    }
  }

  String nameOrEmailFromID(String id) {
    if (list().isEmpty) return "";
    final filtered = list().where((x) => x.id == id);
    if (filtered.isEmpty) {
      return name(list()
              .where((x) => x.getStringValue("type") == "admin")
              .firstOrNull ??
          list().first);
    }
    return name(filtered.first);
  }

  List<RecordModel> get operators {
    return list().where((e) => e.getIntValue("operate") == 1).toList();
  }

  _Accounts() : super("accounts");

  @override
  fromJson(Map<String, dynamic> json) {
    list(List<Map<String, dynamic>>.from(json["list"])
        .map((e) => RecordModel.fromJson(e))
        .toList());
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      "list": list().map((e) {
        return e.toJson();
      }).toList()
    };
  }
}

final accounts = _Accounts();

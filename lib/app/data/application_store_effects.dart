import 'package:apexo/common_widgets/error_dialog.dart';
import 'package:apexo/core/model.dart';
import 'package:apexo/core/synchronization/document_loading.dart';
import 'package:apexo/core/synchronization/push_data.dart';
import 'package:apexo/core/synchronization/store_effects.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/notifications/listeners.dart';
import 'package:apexo/services/notifications/push_deferring.dart';
import 'package:apexo/services/notifications/push_relay.dart';
import 'package:apexo/utils/logger.dart';
import 'package:apexo/utils/phone_numbers_extractor.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';

const applicationStoreEffects = ApplicationStoreEffects();

class ApplicationStoreEffects extends StoreEffects {
  const ApplicationStoreEffects();
  @override
  String get currentAccountID => login.currentAccountID;
  @override
  Future<void> refreshAuthentication() async {
    await login.authenticateWithToken(login.token);
  }
  @override
  void authenticationFailed(Object error) => login.askForLoginAgain(error);
  @override
  void reportError(Object error, String operation) => showErrorMessage(error, operation);
  @override
  void log(Object error, StackTrace? stack, [int importance = 0]) => logger(error, stack, importance);
  @override
  Future<void> enqueuePushes(List<PushData> pushes) => deferredPush.putBulk(pushes);
  @override
  Future<void> sendPushes(List<PushData> pushes) async { await PushRelay.sendPush(pushes); }
  @override
  Future<PushData?> pendingPush(String id) => deferredPush.getByID(id);
  @override
  Future<void> clearPushes(String store) => deferredPush.clearByStore(store);
  @override
  Future<void> clearPushesByIDs(Iterable<String> ids) =>
      deferredPush.clearByIDs(ids);
  @override
  Future<void> notify(PushData push) async {
    await dispatchStaticNotification(
      push,
      icon: push.isCreation ? WindowsIcons.add : FluentIcons.edit,
      ding: true,
    );
  }
}

/// Only the application loader supplies clinic-specific phone parsing context.
Future<List<Map<String, G>>> loadApplicationDocuments<G extends Model>(
  ModellingFunc<G> modeling,
  Map<String, Map<String, dynamic>> decoded,
) => compute(_modelApplicationDocuments<G>, _ApplicationBatch(DocumentBatch(modeling, decoded), isoCC()));

class _ApplicationBatch<G extends Model> {
  const _ApplicationBatch(this.documents, this.countryCode);
  final DocumentBatch<G> documents;
  final String countryCode;
}

List<Map<String, G>> _modelApplicationDocuments<G extends Model>(_ApplicationBatch<G> batch) {
  setIsoCountryCodeForIsolate(batch.countryCode);
  return modelStoreDocuments(batch.documents);
}

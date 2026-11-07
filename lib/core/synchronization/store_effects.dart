import '../../core/synchronization/push_data.dart';

/// Store side effects. Defaults are inert so isolated stores need no app singletons.
class StoreEffects {
  const StoreEffects();

  String get currentAccountID => '';
  Future<void> refreshAuthentication() async {}
  void authenticationFailed(Object error) {}
  void reportError(Object error, String operation) {}
  void log(Object error, StackTrace? stack, [int importance = 0]) {}
  Future<void> enqueuePushes(List<PushData> pushes) async {}
  Future<void> sendPushes(List<PushData> pushes) async {}
  Future<PushData?> pendingPush(String id) async => null;
  Future<void> clearPushes(String store) async {}
  Future<void> clearPushesByIDs(Iterable<String> ids) async {}
  Future<void> notify(PushData push) async {}
}

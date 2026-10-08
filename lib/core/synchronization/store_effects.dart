import '../../core/synchronization/push_data.dart';

/// Application effects used by a store, independent of authentication and UI.
/// The default is inert so isolated stores need no application singletons.
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
  Future<void> notify(PushData push) async {}
}

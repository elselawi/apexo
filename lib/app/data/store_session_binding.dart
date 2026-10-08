import 'package:apexo/core/lifecycle/session_callbacks.dart';
import 'package:apexo/core/model.dart';
import 'package:apexo/core/persistence/save_local.dart';
import 'package:apexo/core/persistence/save_remote.dart';
import 'package:apexo/core/persistence/serial_operation_queue.dart';
import 'package:apexo/core/store.dart';
import 'package:apexo/features/login/login_controller.dart';
import 'package:apexo/features/network_actions/network_actions_controller.dart';
import 'package:apexo/services/launch.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/network.dart';
import 'package:apexo/utils/hash.dart';

/// Application-owned authentication binding. The store owns its persistence
/// lane and remote resources; this binding owns external callback registrations
/// and serial replacement of its Hive adapter.
class StoreSessionBinding<G extends Model> {
  StoreSessionBinding({
    required this.store,
    required this.name,
    required this.loadingMessage,
    this.seedDemo,
    this.afterSynchronize,
    this.syncAction,
  });

  final Store<G> store;
  final String name;
  final String loadingMessage;
  final List<G> Function()? seedDemo;
  final Future<void> Function(bool Function() isCurrent)? afterSynchronize;
  final SessionCallback? syncAction;
  final SerialOperationQueue _activation = SerialOperationQueue();
  SessionCallbacks? _callbacks;
  bool _installed = false;
  int _generation = 0;

  void install() {
    if (_installed) return;
    _installed = true;
    login.activators[name] = activate;
    onLogoutCallbacks.add(stop);
  }

  void stop() {
    _generation++;
    _callbacks?.stop();
    _callbacks = null;
    store.endSession();
  }

  Future<Future<void> Function()> activate() {
    final server = login.url;
    final pocketBase = login.pb;
    final credential = login.token;
    final demo = launch.isDemo;
    stop();
    final generation = _generation;
    bool isCurrent() => generation == _generation &&
        login.url == server && login.token == credential &&
        identical(login.pb, pocketBase);
    return _activation.run(() async {
      await store.loaded;
      if (!isCurrent()) return () async {};
      await store.deactivatePersistenceSession();
      if (!isCurrent()) return () async {};
      await store.local?.dispose();
      if (!isCurrent()) return () async {};
      store.local = SaveLocal(name: name, uniqueId: simpleHash(server));
      await store.deleteMemoryAndLoadFromPersistence();
      if (!isCurrent()) return () async {};
      if (demo && seedDemo != null) {
        if (store.docs.isEmpty) store.setAll(seedDemo!());
      } else {
        store.remote = SaveRemote(
          pbInstance: pocketBase!, storeName: name,
          onOnlineStatusChange: (current) {
            if (isCurrent() && network.isOnline() != current) network.isOnline(current);
          },
        );
      }
      final callbacks = _callbacks = SessionCallbacks();
      return () async {
        if (!isCurrent()) return;
        loginCtrl.loadingIndicator(loadingMessage);
        await store.synchronize();
        if (!isCurrent()) return;
        callbacks.register(networkActions.syncCallbacks, name, syncAction ?? store.synchronize);
        final remote = store.remote;
        if (remote != null) callbacks.register(networkActions.reconnectCallbacks, name, remote.checkOnline);
        callbacks.register(network.onOnline, name, store.synchronize);
        callbacks.register(network.onOffline, name, store.cancelRealtimeSub);
        await afterSynchronize?.call(isCurrent);
      };
    });
  }
}

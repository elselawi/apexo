import 'dart:async';

typedef SessionCallback = FutureOr<void> Function();

/// Owns registrations for one session. Snapshot-dispatched callbacks become
/// inert immediately on stop, even if a dispatcher has already copied them.
class SessionCallbacks {
  bool _active = true;
  final List<void Function()> _removals = [];

  bool get isActive => _active;

  void register(Map<String, SessionCallback> registry, String key, SessionCallback callback) {
    if (!_active) return;
    Future<void> guarded() async {
      if (_active) await callback();
    }
    registry[key] = guarded;
    _removals.add(() {
      if (identical(registry[key], guarded)) registry.remove(key);
    });
  }

  void stop() {
    if (!_active) return;
    _active = false;
    for (final remove in _removals) { remove(); }
    _removals.clear();
  }
}

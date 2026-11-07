import 'dart:async';

typedef SessionCallback = FutureOr<void> Function();

/// Callbacks reached through an earlier snapshot do nothing after `stop()`.
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

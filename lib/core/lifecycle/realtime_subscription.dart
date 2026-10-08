import 'dart:async';

typedef CancelSubscription = Future<void> Function();

/// Owns both a subscription and pending registration/cancellation work.
/// Invalidated registrations cancel themselves instead of becoming current.
class RealtimeSubscription {
  RealtimeSubscription({required this.onError});
  final void Function(Object, StackTrace) onError;
  CancelSubscription? _cancel;
  Future<void>? _starting;
  final Set<Future<void>> _tasks = {};
  int _generation = 0;

  void start(Future<CancelSubscription> Function() subscribe) {
    if (_cancel != null || _starting != null) return;
    final generation = _generation;
    final task = _track(() async {
      final cancel = await subscribe();
      if (generation == _generation) {
        _cancel = cancel;
      } else {
        await cancel();
      }
    });
    _starting = task;
    unawaited(task.then((_) {
      if (identical(_starting, task)) _starting = null;
    }));
  }

  void cancel() {
    _generation++;
    final cancel = _cancel;
    _cancel = null;
    if (cancel != null) unawaited(_track(cancel));
  }

  Future<void> _track(Future<void> Function() action) {
    final task = Future<void>.sync(action).catchError(onError);
    _tasks.add(task);
    unawaited(task.then((_) => _tasks.remove(task)));
    return task;
  }

  Future<void> drain() async {
    while (_tasks.isNotEmpty) {
      await Future.wait(_tasks.toList());
    }
  }
}

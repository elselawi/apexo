import 'dart:async';
import 'dart:developer' as developer;

typedef ReactiveErrorReporter = void Function(Object error, StackTrace stack);

/// The application installs its diagnostic policy at startup; isolated clients
/// can instead provide a reporter on each observable.
ReactiveErrorReporter reactiveErrorReporter = (error, stack) {
  developer.log('Observable callback failed', error: error, stackTrace: stack);
};

void reportReactiveError(Object error, StackTrace stack) =>
    reactiveErrorReporter(error, stack);

ReactiveErrorReporter reactiveSilentErrorReporter = reportReactiveError;

void reportSilentReactiveError(Object error, StackTrace stack) =>
    reactiveSilentErrorReporter(error, stack);

typedef Observer<S> = void Function(S event);

/// Base observable class
/// the observable functionality of the application is all based on this class
class ObservableBase<S> {
  ObservableBase(
      {this.onError = reportReactiveError,
      this.onSilentError = reportSilentReactiveError}) {
    stream.listen((events) {
      for (final observer in List<Observer<S>>.of(observers)) {
        try {
          observer(events);
        } catch (e, s) {
          onError(e, s);
        }
      }
    });
  }

  final ReactiveErrorReporter onError;
  final ReactiveErrorReporter onSilentError;

  final StreamController<S> _controller = StreamController<S>.broadcast();
  final List<Observer<S>> observers = [];

  /// The stream every listener subscribes to.
  ///
  /// Held rather than handed out by a getter: `StreamController.broadcast()`
  /// returns a **new** stream object on every `.stream` access, so a getter
  /// would make a `streams: [x.stream]` list written inside `build()` look like
  /// it swapped its stream on every rebuild — and re-subscribe every time.
  late final Stream<S> stream = _controller.stream;
  double _silent = 0;
  bool get isSilent => _silent != 0;

  void notifyObservers(S event) {
    if (_silent != 0) return;
    _controller.add(event);
  }

  int observe(Observer<S> callback) {
    final int existing = observers.indexWhere((o) => o == callback);
    if (existing > -1) {
      return existing;
    }
    observers.add(callback);
    return observers.length - 1;
  }

  void unObserve(Observer<S> callback) {
    observers.removeWhere((existing) => existing == callback);
  }

  void dispose() {
    _silent = double.maxFinite;
    observers.clear();
    if (!_controller.isClosed) {
      unawaited(_controller.close());
    }
  }

  void silently(void Function() fn) {
    _silent++;
    try {
      fn();
    } catch (e, s) {
      onSilentError(e, s);
    } finally {
      _silent--;
    }
  }
}

/// Creates a standalone observable value
/// this can be accessed by calling it "()"
/// and can be set by passing a value when calling it "(value)"
class ObservableState<T> extends ObservableBase<T> {
  ObservableState(this._value, {super.onError, super.onSilentError});
  T _value;

  T call([T? newValue]) {
    if (newValue != null) {
      _value = newValue;
      notifyObservers(_value);
    }
    return _value;
  }
}

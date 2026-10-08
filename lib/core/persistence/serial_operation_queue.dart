import 'dart:async';

/// An instance-owned lane for writes, sync passes and attachment operations.
/// Failures are returned to the caller without poisoning subsequent work.
class SerialOperationQueue {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() action) {
    final operation = _tail.then((_) => action());
    _tail = operation.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return operation;
  }

  /// Includes work appended while earlier operations are completing.
  Future<void> drain() async {
    while (true) {
      final tail = _tail;
      await tail;
      if (identical(tail, _tail)) return;
    }
  }
}

import 'dart:async';

import 'package:apexo/core/reactive/observable.dart';
import 'package:apexo/utils/logger.dart';

class _Network {
  _Network() {
    isOnline.observe((online) {
      final callbacks = (online ? onOnline : onOffline).values.toList();
      for (final callback in callbacks) {
        unawaited(Future<void>.sync(callback).catchError((Object e, StackTrace s) {
          logger('Network status callback failed: $e', s);
        }));
      }
    });
  }
  Map<String, FutureOr<void> Function()> onOnline = {};
  Map<String, FutureOr<void> Function()> onOffline = {};
  final isOnline = ObservableState(false);
}

final network = _Network();

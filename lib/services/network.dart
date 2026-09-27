import 'package:apexo/core/observable.dart';

class _Network {
  _Network() {
    isOnline.observe((_) {
      if (isOnline()) {
        for (var cb in onOnline.values) {
          cb();
        }
      } else {
        for (var cb in onOffline.values) {
          cb();
        }
      }
    });
  }
  Map<String, void Function()> onOnline = {};
  Map<String, void Function()> onOffline = {};
  final isOnline = ObservableState(false);
}

final network = _Network();

import 'dart:io';

import 'package:apexo/main.dart' as app;
import 'package:flutter/widgets.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_driver/driver_extension.dart';

/// Profiling entry point. `enableFlutterDriverExtension` must run before any
/// binding exists, and the stderr timing covers what AOT can't report.
void main() {
  final startup = Stopwatch()..start();
  enableFlutterDriverExtension();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    stderr.writeln('APEXO_TIMING first_frame_ms=${startup.elapsedMilliseconds}');
  });
  app.main();
}

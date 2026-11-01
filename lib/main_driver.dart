import 'dart:io';

import 'package:apexo/main.dart' as app;
import 'package:flutter/widgets.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_driver/driver_extension.dart';

/// Profiling entry point: the real app plus the flutter_driver extension, and
/// one timestamp the framework cannot report from AOT code.
///
/// `enableFlutterDriverExtension` has to run before anything else touches a
/// binding: it installs the driver's own binding, and a plain
/// `WidgetsFlutterBinding` created first wins instead (the extension then
/// throws and never answers the driver).
void main() {
  final startup = Stopwatch()..start();
  enableFlutterDriverExtension();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    stderr.writeln('APEXO_TIMING first_frame_ms=${startup.elapsedMilliseconds}');
  });
  app.main();
}

import 'dart:async';
import 'package:logging/logging.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

final log = Logger('ApexoLogger');

/// 1 = severe, 2 = warning, 3 = info
void logger(Object msg, StackTrace? stacktrace, [int importance = 0]) {
  unawaited(Sentry.captureException(msg, stackTrace: stacktrace));
  // What the app itself was doing, on the trail Sentry hands to the next event:
  // an event's own log line says nothing about the ones before it.
  unawaited(Sentry.addBreadcrumb(Breadcrumb(
    category: 'app',
    level: switch (importance) {
      2 => SentryLevel.warning,
      3 => SentryLevel.info,
      _ => SentryLevel.error,
    },
    message: '$msg',
  )));
  switch (importance) {
    case 1:
      log.severe("\x1B[31m$msg\x1B[0m");
      break;
    case 2:
      log.warning("\x1B[33m$msg\x1B[0m");
      break;
    case 3:
      log.info("\x1B[34m$msg\x1B[0m");
      break;
    default:
      log.severe("\x1B[31m$msg\x1B[0m");
      break;
  }
  if (stacktrace != null) log.info("\n\x1B[35mSTACKTRACE:\n$stacktrace\x1B[0m");
}

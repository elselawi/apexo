import 'dart:async';

import 'package:apexo/features/booking/booking_session.dart';
import 'package:apexo/services/session_events.dart';
import 'package:apexo/utils/constants.dart';

/// Starts booking discovery after a session is up and tears the cache down on
/// logout.
///
/// Discovery is non-blocking and silent: an unregistered clinic — or a Worker
/// that is down — never affects ordinary PMS login or store initialization.
void initializeBooking() {
  if (!bookingAvailable) return;
  SessionEvents.onStarted(() => unawaited(booking.initialize()));
  SessionEvents.onEnded(() => booking.reset());
}

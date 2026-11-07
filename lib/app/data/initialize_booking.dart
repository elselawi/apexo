import 'dart:async';

import 'package:apexo/features/booking/booking_session.dart';
import 'package:apexo/services/session_events.dart';
import 'package:apexo/utils/constants.dart';

/// Starts booking discovery on session start, tears its cache down on logout.
/// Discovery is silent and non-blocking, so a failure never affects login.
void initializeBooking() {
  if (!bookingAvailable) return;
  SessionEvents.onStarted(() => unawaited(booking.initialize()));
  SessionEvents.onEnded(() => booking.reset());
}

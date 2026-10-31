@Tags(['serial'])
library;

import 'package:apexo/features/appointments/appointment_start_guess.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('guessAppointmentStart', () {
    test('today starts at the next free quarter of an hour', () {
      final now = DateTime(2026, 5, 4, 10, 7, 30);

      expect(
        guessAppointmentStart(
          day: DateTime(2026, 5, 4),
          now: now,
          busy: const [],
        ),
        DateTime(2026, 5, 4, 10, 15),
      );
    });

    test('a fractional second past a step never guesses into the past', () {
      final now = DateTime(2026, 5, 4, 10, 15, 0, 1);

      expect(
        guessAppointmentStart(day: now, now: now, busy: const []),
        DateTime(2026, 5, 4, 10, 30),
      );
    });

    test('a moment already on the step is not pushed forward', () {
      final now = DateTime(2026, 5, 4, 10, 15);

      expect(
        guessAppointmentStart(day: now, now: now, busy: const []),
        DateTime(2026, 5, 4, 10, 15),
      );
    });

    test('today walks past a visit that is already there', () {
      final now = DateTime(2026, 5, 4, 10, 7);

      expect(
        guessAppointmentStart(
          day: DateTime(2026, 5, 4),
          now: now,
          busy: [
            (
              start: DateTime(2026, 5, 4, 10, 15),
              duration: const Duration(minutes: 30)
            ),
          ],
        ),
        DateTime(2026, 5, 4, 10, 45),
      );
    });

    test('another day starts at the morning hour', () {
      expect(
        guessAppointmentStart(
          day: DateTime(2026, 5, 9),
          now: DateTime(2026, 5, 4, 16, 22),
          busy: const [],
        ),
        DateTime(2026, 5, 9, 9),
      );
    });

    test('another day queues behind the last visit of that day', () {
      expect(
        guessAppointmentStart(
          day: DateTime(2026, 5, 9),
          now: DateTime(2026, 5, 4, 16, 22),
          busy: [
            (
              start: DateTime(2026, 5, 9, 9),
              duration: const Duration(minutes: 30)
            ),
            (
              start: DateTime(2026, 5, 9, 11, 30),
              duration: const Duration(minutes: 45)
            ),
          ],
        ),
        DateTime(2026, 5, 9, 12, 15),
      );
    });

    test('visits of other days do not move the guess', () {
      expect(
        guessAppointmentStart(
          day: DateTime(2026, 5, 9),
          now: DateTime(2026, 5, 4, 16, 22),
          busy: [
            (
              start: DateTime(2026, 5, 10, 9),
              duration: const Duration(hours: 4)
            ),
          ],
        ),
        DateTime(2026, 5, 9, 9),
      );
    });

    test('a visit spilling over midnight keeps the first slot of the day free',
        () {
      // 23:50 the night before, half an hour long: still going at 00:20.
      final now = DateTime(2026, 5, 9, 0, 5);

      expect(
        guessAppointmentStart(
          day: DateTime(2026, 5, 9),
          now: now,
          busy: [
            (
              start: DateTime(2026, 5, 8, 23, 50),
              duration: const Duration(minutes: 30)
            ),
          ],
        ),
        DateTime(2026, 5, 9, 0, 30),
      );
    });

    test('the moment a caller already has is kept', () {
      expect(
        guessAppointmentStart(
          day: DateTime(2026, 5, 9),
          now: DateTime(2026, 5, 4, 16, 22),
          busy: const [],
          preferred: DateTime(2026, 5, 9, 15, 30),
        ),
        DateTime(2026, 5, 9, 15, 30),
      );
    });

    test('that moment still moves when a visit already holds it', () {
      expect(
        guessAppointmentStart(
          day: DateTime(2026, 5, 9),
          now: DateTime(2026, 5, 4, 16, 22),
          preferred: DateTime(2026, 5, 9, 15, 30),
          busy: [
            (
              start: DateTime(2026, 5, 9, 15, 30),
              duration: const Duration(minutes: 30)
            ),
          ],
        ),
        DateTime(2026, 5, 9, 16),
      );
    });

    test('the guess leaves room for the whole visit', () {
      expect(
        guessAppointmentStart(
          day: DateTime(2026, 5, 9),
          now: DateTime(2026, 5, 4, 16, 22),
          duration: 60,
          busy: [
            (
              start: DateTime(2026, 5, 9, 9),
              duration: const Duration(minutes: 30)
            ),
          ],
        ),
        DateTime(2026, 5, 9, 9, 30),
      );
    });

    test('back-to-back visits still take the next step', () {
      expect(
        guessAppointmentStart(
          day: DateTime(2026, 5, 9),
          now: DateTime(2026, 5, 4, 16, 22),
          busy: [
            (
              start: DateTime(2026, 5, 9, 9),
              duration: const Duration(minutes: 45)
            ),
            (
              start: DateTime(2026, 5, 9, 9, 45),
              duration: const Duration(minutes: 15)
            ),
          ],
        ),
        DateTime(2026, 5, 9, 10),
      );
    });
  });
}

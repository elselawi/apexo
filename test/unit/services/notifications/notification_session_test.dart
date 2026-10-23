@Tags(['serial'])
library;

import 'dart:async';

import 'package:apexo/services/notifications/notification_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('publishing resolves a waiter with the active snapshot', () async {
    final sessions = NotificationSessionCoordinator(
      waitTimeout: const Duration(seconds: 1),
    );
    sessions.beginRestoring();
    final waiting = sessions.waitForUsableSession();

    final published = sessions.publishPatient(
      server: 'https://clinic.test',
      accountId: 'patient-1',
      clinicKey: 'key',
    );

    final waited = await waiting;
    expect(waited, isNotNull);
    expect(waited!.generation, published.generation);
    expect(sessions.isCurrent(published), isTrue);
  });

  test('invalidation resolves a waiter with null instead of hanging', () async {
    final sessions = NotificationSessionCoordinator(
      waitTimeout: const Duration(seconds: 5),
    );
    final waiting = sessions.waitForUsableSession();

    sessions.invalidate();

    expect(await waiting, isNull);
    expect(sessions.phase, NotificationSessionPhase.absent);
  });

  test('a waiter times out when the restore never finishes', () async {
    final sessions = NotificationSessionCoordinator(
      waitTimeout: const Duration(milliseconds: 30),
    );

    expect(await sessions.waitForUsableSession(), isNull);
  });

  test('a snapshot from before a switch is not current', () {
    final sessions = NotificationSessionCoordinator();
    final first = sessions.publishPatient(
      server: 'https://clinic.test',
      accountId: 'patient-a',
      clinicKey: 'key',
    );

    sessions.beginRestoring();
    final second = sessions.publishPatient(
      server: 'https://clinic.test',
      accountId: 'patient-b',
      clinicKey: 'key',
    );

    expect(sessions.isCurrent(first), isFalse);
    expect(sessions.isCurrent(second), isTrue);
  });

  test('a login waiter ignores a restore start until a publish or absence',
      () async {
    final sessions = NotificationSessionCoordinator(
      waitTimeout: const Duration(seconds: 1),
    );
    final waiting = sessions.waitForUsableSession();

    sessions.beginRestoring();
    var completed = false;
    unawaited(waiting.then((_) {
      completed = true;
    }));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(completed, isFalse);

    sessions.publishStaff(
      server: 'https://clinic.test',
      accountId: 'account-1',
      pocketBase: null,
      authToken: 'token',
      email: 'test@example.com',
    );
    final result = await waiting;
    expect(result?.isPatient, isFalse);
  });

  test('listeners observe transitions and can be removed', () {
    final sessions = NotificationSessionCoordinator();
    var calls = 0;
    void listener() => calls++;

    sessions.addListener(listener);
    sessions.publishPatient(
      server: 'https://clinic.test',
      accountId: 'patient-1',
      clinicKey: 'key',
    );
    sessions.invalidate();
    expect(calls, 2);

    sessions.removeListener(listener);
    sessions.beginRestoring();
    expect(calls, 2);
  });
}

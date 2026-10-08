import 'dart:async';

import 'package:apexo/core/lifecycle/session_callbacks.dart';
import 'package:apexo/core/lifecycle/realtime_subscription.dart';
import 'package:apexo/core/persistence/serial_operation_queue.dart';
import 'package:apexo/core/reactive/observable_base.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pending realtime registration cancels and drains after invalidation', () async {
    final registration = Completer<CancelSubscription>();
    final cancellation = Completer<void>();
    var subscriptions = 0;
    var cancellations = 0;
    final owner = RealtimeSubscription(onError: (error, stack) => fail('$error'));
    Future<CancelSubscription> subscribe() { subscriptions++; return registration.future; }
    owner.start(subscribe);
    owner.start(subscribe);
    expect(subscriptions, 1);
    owner.cancel();
    var drained = false;
    final draining = owner.drain().then((_) => drained = true);
    registration.complete(() async { cancellations++; await cancellation.future; });
    await Future<void>.delayed(Duration.zero);
    expect(cancellations, 1);
    expect(drained, isFalse);
    cancellation.complete();
    await draining;
    expect(drained, isTrue);
    owner.start(() async => () async { cancellations++; });
    await owner.drain();
    owner.cancel();
    await owner.drain();
    expect(cancellations, 2);
  });

  test('failed realtime registration is isolated and can be retried', () async {
    final errors = <Object>[];
    final owner = RealtimeSubscription(onError: (error, _) => errors.add(error));
    owner.start(() async => throw StateError('subscription failed'));
    await owner.drain();
    expect(errors, hasLength(1));
    var cancelled = false;
    owner.start(() async => () async { cancelled = true; });
    await owner.drain();
    owner.cancel();
    await owner.drain();
    expect(cancelled, isTrue);
  });

  test('serial lane orders work and propagates failure without poisoning later work', () async {
    final queue = SerialOperationQueue();
    final gate = Completer<void>();
    final events = <String>[];
    final first = queue.run(() async {
      events.add('first started');
      await gate.future;
      throw StateError('failed write');
    });
    final failure = expectLater(first, throwsStateError);
    final second = queue.run(() async {
      events.add('second started');
      return 42;
    });
    await Future<void>.delayed(Duration.zero);
    expect(events, ['first started']);
    gate.complete();
    await failure;
    expect(await second, 42);
    await queue.drain();
    expect(events, ['first started', 'second started']);
  });

  test('drain includes work appended by a completing operation', () async {
    final queue = SerialOperationQueue();
    final gate = Completer<void>();
    final appendedGate = Completer<void>();
    var finished = false;
    unawaited(queue.run(() async {
      await gate.future;
      unawaited(queue.run(() async { await appendedGate.future; }));
    }));
    final drain = queue.drain().then((_) => finished = true);
    gate.complete();
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse);
    appendedGate.complete();
    await drain;
    expect(finished, isTrue);
  });

  test('stopped session removes callbacks and invalidates dispatcher snapshots', () async {
    final callbacks = SessionCallbacks();
    final registry = <String, SessionCallback>{};
    var calls = 0;
    callbacks.register(registry, 'store', () => calls++);
    final snapshot = registry.values.toList();
    callbacks.stop();
    callbacks.stop();
    await snapshot.single();
    expect(calls, 0);
    expect(registry, isEmpty);
    callbacks.register(registry, 'later', () => calls++);
    expect(registry, isEmpty);
  });

  test('stopping old registration cannot remove its successor', () async {
    final old = SessionCallbacks();
    final successor = SessionCallbacks();
    final registry = <String, SessionCallback>{};
    var calls = 0;
    old.register(registry, 'store', () => calls += 100);
    successor.register(registry, 'store', () => calls++);
    old.stop();
    await registry['store']!();
    expect(calls, 1);
    successor.stop();
    expect(registry, isEmpty);
  });

  test('multiple callback registries are released by one session owner', () {
    final callbacks = SessionCallbacks();
    final registries = List.generate(4, (_) => <String, SessionCallback>{});
    for (final registry in registries) {
      callbacks.register(registry, 'store', () {});
    }
    callbacks.stop();
    expect(registries.every((registry) => registry.isEmpty), isTrue);
  });

  test('standalone primitive isolates observer failure without app initialization', () async {
    final errors = <Object>[];
    final observable = ObservableState(0, onError: (error, _) => errors.add(error));
    var observed = 0;
    observable.observe((_) => throw StateError('observer failed'));
    observable.observe((value) => observed = value);
    observable(7);
    await Future<void>.delayed(Duration.zero);
    expect(observed, 7);
    expect(errors, hasLength(1));
    observable.dispose();
  });
}

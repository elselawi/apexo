import 'package:apexo/utils/que.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TaskQueue', () {
    test('default delayBetweenTasks is 250ms', () {
      final q = TaskQueue();
      expect(q.delayBetweenTasks, const Duration(milliseconds: 250));
    });

    test('custom delayBetweenTasks', () {
      final q = TaskQueue(delayBetweenTasks: const Duration(milliseconds: 100));
      expect(q.delayBetweenTasks, const Duration(milliseconds: 100));
    });

    test('add returns a Future that completes with task result', () async {
      final q = TaskQueue(delayBetweenTasks: Duration.zero);
      final result = await q.add<int>(() async => 42);
      expect(result, 42);
    });

    test('tasks execute sequentially', () async {
      final q = TaskQueue(delayBetweenTasks: Duration.zero);
      final order = <int>[];

      final f1 = q.add(() async {
        order.add(1);
        await Future<void>.delayed(Duration.zero);
        order.add(2);
      });
      final f2 = q.add(() async {
        order.add(3);
      });

      await Future.wait([f1, f2]);
      expect(order, [1, 2, 3]); // f2 waits for f1 to finish
    });

    test('task throwing error completes with error', () async {
      final q = TaskQueue(delayBetweenTasks: Duration.zero);
      final future = q.add<int>(() async => throw Exception('task error'));

      await expectLater(
        future,
        throwsA(
          predicate<Object>((error) =>
              error is Exception && error.toString().contains('task error')),
        ),
      );
    });

    test('continues processing tasks after a failed task', () async {
      final q = TaskQueue(delayBetweenTasks: Duration.zero);
      final events = <String>[];

      final failed = q.add<void>(() async {
        events.add('failed');
        throw StateError('boom');
      });
      final recovered = q.add<String>(() async {
        events.add('recovered');
        return 'ok';
      });

      await expectLater(failed, throwsStateError);
      expect(await recovered, 'ok');
      expect(events, ['failed', 'recovered']);
    });

    test('a queue with a completed task can accept later tasks', () async {
      final q = TaskQueue(delayBetweenTasks: Duration.zero);

      expect(await q.add(() async => 'first'), 'first');
      expect(await q.add(() async => 'second'), 'second');
    });

    test('rapid adds are all executed in order', () async {
      final q = TaskQueue(delayBetweenTasks: Duration.zero);
      final results = <int>[];

      final futures = <Future>[];
      for (int i = 0; i < 10; i++) {
        final idx = i;
        futures.add(q.add(() async => results.add(idx)));
      }

      await Future.wait(futures);
      expect(results, List.generate(10, (i) => i));
    });

    test('results returned in submission order', () async {
      final q = TaskQueue(delayBetweenTasks: Duration.zero);

      final f1 = q.add<String>(() async {
        await Future<void>.delayed(Duration.zero);
        return 'slow';
      });
      final f2 = q.add<String>(() async => 'fast');

      // f1 completes first in queue but f2 was submitted second
      final result1 = await f1;
      final result2 = await f2;
      expect(result1, 'slow');
      expect(result2, 'fast');
    });

    test('permits tasks to enqueue more tasks while processing', () async {
      final q = TaskQueue(delayBetweenTasks: Duration.zero);
      final events = <String>[];
      late Future<String> nested;

      final first = q.add<String>(() async {
        events.add('first');
        nested = q.add<String>(() async {
          events.add('nested');
          return 'nested result';
        });
        return 'first result';
      });
      final second = q.add<String>(() async {
        events.add('second');
        return 'second result';
      });

      expect(await first, 'first result');
      expect(await second, 'second result');
      expect(await nested, 'nested result');
      // The first task starts immediately, so its re-entrant add is queued
      // before the caller submits the second task.
      expect(events, ['first', 'nested', 'second']);
    });

    test('demoAvatarRequestQue singleton exists', () {
      expect(demoAvatarRequestQue, isNotNull);
      expect(demoAvatarRequestQue, isA<TaskQueue>());
    });
  });
}

import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/core/observable.dart';

Widget _dir(Widget child) => Directionality(
      textDirection: TextDirection.ltr,
      child: child,
    );

void main() {
  group('MStreamBuilder Tests', () {
    testWidgets('should build with initial null values', (tester) async {
      final controller1 = StreamController<int>();
      final controller2 = StreamController<int>();

      List<int?> capturedData = [];

      await tester.pumpWidget(
        MStreamBuilder<int>(
          streams: [controller1.stream, controller2.stream],
          builder: (context, data) {
            capturedData = data;
            return const SizedBox();
          },
        ),
      );

      expect(capturedData.length, 2);
      expect(capturedData, [null, null]);

      unawaited(controller1.close());
      unawaited(controller2.close());
    });

    testWidgets('should update when streams emit values', (tester) async {
      final controller1 = StreamController<String>();
      final controller2 = StreamController<String>();

      List<String?> capturedData = [];

      await tester.pumpWidget(
        MStreamBuilder<String>(
          streams: [controller1.stream, controller2.stream],
          builder: (context, data) {
            capturedData = data;
            return const SizedBox();
          },
        ),
      );

      // `data` is a snapshot taken at build time, so the assertion has to wait for
      // the frame the delivery triggers — not the pump that starts it.
      controller1.add('test1');
      await tester.pumpAndSettle();
      expect(capturedData, ['test1', null]);

      controller2.add('test2');
      await tester.pumpAndSettle();
      expect(capturedData, ['test1', 'test2']);

      unawaited(controller1.close());
      unawaited(controller2.close());
    });

    testWidgets('should handle stream updates in correct order',
        (tester) async {
      final controller1 = StreamController<int>();
      final controller2 = StreamController<int>();
      final controller3 = StreamController<int>();

      List<int?> capturedData = [];

      await tester.pumpWidget(
        MStreamBuilder<int>(
          streams: [
            controller1.stream,
            controller2.stream,
            controller3.stream,
          ],
          builder: (context, data) {
            capturedData = data;
            return const SizedBox();
          },
        ),
      );

      controller2.add(2);
      await tester.pumpAndSettle();
      expect(capturedData, [null, 2, null]);

      controller1.add(1);
      await tester.pumpAndSettle();
      expect(capturedData, [1, 2, null]);

      controller3.add(3);
      await tester.pumpAndSettle();
      expect(capturedData, [1, 2, 3]);

      unawaited(controller1.close());
      unawaited(controller2.close());
      unawaited(controller3.close());
    });

    testWidgets('should cleanup subscriptions on dispose', (tester) async {
      final controller1 = StreamController<int>();
      final controller2 = StreamController<int>();

      await tester.pumpWidget(
        MStreamBuilder<int>(
          streams: [controller1.stream, controller2.stream],
          builder: (context, data) => const SizedBox(),
        ),
      );

      await tester.pumpWidget(const SizedBox());

      // Verify no memory leaks by attempting to add values after disposal
      controller1.add(1);
      controller2.add(2);
      await tester.pump();

      unawaited(controller1.close());
      unawaited(controller2.close());
    });

    testWidgets('handles empty stream list — builder receives empty list',
        (tester) async {
      await tester.pumpWidget(
        _dir(
          MStreamBuilder<int>(
            streams: const [],
            builder: (context, data) {
              return SizedBox(
                key: const Key('empty-builder'),
                child: Text('${data.length}'),
              );
            },
          ),
        ),
      );

      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('handles a single stream — data list has one slot',
        (tester) async {
      final controller = StreamController<String>();
      await tester.pumpWidget(
        _dir(
          MStreamBuilder<String>(
            streams: [controller.stream],
            builder: (context, data) {
              return Text(data.firstOrNull ?? 'null');
            },
          ),
        ),
      );

      expect(find.text('null'), findsOneWidget);
      controller.add('only');
      await tester.pumpAndSettle();
      expect(find.text('only'), findsOneWidget);
      unawaited(controller.close());
    });

    testWidgets('re-emission on the same stream updates only that slot',
        (tester) async {
      final c1 = StreamController<int>();
      final c2 = StreamController<int>();
      await tester.pumpWidget(
        _dir(
          MStreamBuilder<int>(
            streams: [c1.stream, c2.stream],
            builder: (context, data) => Text('${data[0]}-${data[1]}'),
          ),
        ),
      );

      c1.add(1);
      await tester.pumpAndSettle();
      expect(find.text('1-null'), findsOneWidget);
      c1.add(2);
      await tester.pumpAndSettle();
      expect(find.text('2-null'), findsOneWidget);
      c2.add(9);
      await tester.pumpAndSettle();
      expect(find.text('2-9'), findsOneWidget);
      unawaited(c1.close());
      unawaited(c2.close());
    });

    testWidgets('emits values in arrival order across streams', (tester) async {
      final c1 = StreamController<int>();
      final c2 = StreamController<int>();
      final c3 = StreamController<int>();

      await tester.pumpWidget(
        _dir(
          MStreamBuilder<int>(
            streams: [c1.stream, c2.stream, c3.stream],
            builder: (context, data) =>
                Text('${data[0]}.${data[1]}.${data[2]}'),
          ),
        ),
      );

      c3.add(30);
      await tester.pumpAndSettle();
      expect(find.text('null.null.30'), findsOneWidget);
      c2.add(20);
      await tester.pumpAndSettle();
      expect(find.text('null.20.30'), findsOneWidget);
      c1.add(10);
      await tester.pumpAndSettle();
      expect(find.text('10.20.30'), findsOneWidget);
      unawaited(c1.close());
      unawaited(c2.close());
      unawaited(c3.close());
    });

    testWidgets('replacing the widget updates subscriptions for new streams',
        (tester) async {
      final c1 = StreamController<int>();
      final c2 = StreamController<int>();
      final replacement1 = StreamController<int>();
      final replacement2 = StreamController<int>();

      await tester.pumpWidget(
        _dir(
          MStreamBuilder<int>(
            key: const Key('msb'),
            streams: [c1.stream],
            builder: (context, data) => Text('first=${data[0]}'),
          ),
        ),
      );

      // Now swap to entirely new streams. A single-subscription Dart stream
      // cannot be subscribed to again after cancellation.
      await tester.pumpWidget(
        _dir(
          MStreamBuilder<int>(
            key: const Key('msb'),
            streams: [replacement1.stream, replacement2.stream],
            builder: (context, data) => Text('${data[0]}-${data[1]}'),
          ),
        ),
      );

      // Give the previous subscriptions time to cancel before emitting.
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 1));
      replacement1.add(5);
      replacement2.add(6);
      await tester.pumpAndSettle();
      expect(find.text('5-6'), findsOneWidget);
      unawaited(c1.close());
      unawaited(c2.close());
      unawaited(replacement1.close());
      unawaited(replacement2.close());
    });

    testWidgets('preserves data when parent rebuilds with equivalent streams',
        (tester) async {
      final controller = StreamController<int>();
      final stream = controller.stream;
      var builds = 0;

      Widget buildWithFreshList() => MStreamBuilder<int>(
            streams: [stream],
            builder: (context, data) {
              builds++;
              return Text('${data.firstOrNull}');
            },
          );

      await tester.pumpWidget(_dir(buildWithFreshList()));
      controller.add(42);
      await tester.pumpAndSettle();
      expect(find.text('42'), findsOneWidget);
      final buildsBeforeParentRebuild = builds;

      await tester.pumpWidget(_dir(buildWithFreshList()));
      expect(find.text('42'), findsOneWidget);
      expect(builds, greaterThan(buildsBeforeParentRebuild));

      unawaited(controller.close());
    });

    testWidgets('ignores events from old streams during replacement',
        (tester) async {
      final oldController = StreamController<int>.broadcast();
      final newController = StreamController<int>.broadcast();
      final oldStream = oldController.stream;
      final newStream = newController.stream;

      await tester.pumpWidget(
        _dir(MStreamBuilder<int>(
          key: const Key('msb-replacement'),
          streams: [oldStream],
          builder: (context, data) => Text('${data[0]}'),
        )),
      );

      oldController.add(1);
      await tester.pumpAndSettle();
      expect(find.text('1'), findsOneWidget);

      await tester.pumpWidget(
        _dir(MStreamBuilder<int>(
          key: const Key('msb-replacement'),
          streams: [newStream],
          builder: (context, data) => Text('${data[0]}'),
        )),
      );

      // The old stream may still be completing cancellation asynchronously;
      // it must not update the replacement widget.
      oldController.add(2);
      newController.add(3);
      await tester.pumpAndSettle();
      expect(find.text('3'), findsOneWidget);
      expect(find.text('2'), findsNothing);

      unawaited(oldController.close());
      unawaited(newController.close());
    });

    testWidgets('ignores events after the widget is disposed', (tester) async {
      // A broadcast controller can be closed deterministically even when the
      // widget has already cancelled its subscription.
      final controller = StreamController<int>.broadcast();

      await tester.pumpWidget(
        _dir(MStreamBuilder<int>(
          streams: [controller.stream],
          builder: (context, data) => const SizedBox(),
        )),
      );
      await tester.pumpWidget(const SizedBox());

      controller.add(1);
      await tester.pump();
      expect(tester.takeException(), isNull);

      unawaited(controller.close());
    });
    testWidgets('broadcast streams can serve multiple MStreamBuilders',
        (tester) async {
      final controller = StreamController<int>.broadcast();
      await tester.pumpWidget(
        _dir(
          Column(
            children: [
              MStreamBuilder<int>(
                streams: [controller.stream],
                builder: (context, data) => Text('A:${data[0]}'),
              ),
              MStreamBuilder<int>(
                streams: [controller.stream],
                builder: (context, data) => Text('B:${data[0]}'),
              ),
            ],
          ),
        ),
      );

      expect(find.text('A:null'), findsOneWidget);
      expect(find.text('B:null'), findsOneWidget);

      controller.add(42);
      await tester.pumpAndSettle();
      expect(find.text('A:42'), findsOneWidget);
      expect(find.text('B:42'), findsOneWidget);
      unawaited(controller.close());
    });

    testWidgets('a stream that only moves keeps its subscription and value',
        (tester) async {
      final c1 = StreamController<int>.broadcast();
      final c2 = StreamController<int>.broadcast();
      final s1 = c1.stream;
      final s2 = c2.stream;

      Widget build(List<Stream<int>> streams) => _dir(
            MStreamBuilder<int>(
              key: const Key('msb-reorder'),
              streams: streams,
              builder: (context, data) => Text('${data[0]}-${data[1]}'),
            ),
          );

      await tester.pumpWidget(build([s1, s2]));
      c1.add(1);
      c2.add(2);
      await tester.pumpAndSettle();
      expect(find.text('1-2'), findsOneWidget);

      // The same two stream objects, positions swapped: matching by identity
      // means both keep their subscription and the value each already held.
      await tester.pumpWidget(build([s2, s1]));
      expect(find.text('2-1'), findsOneWidget);

      unawaited(c1.close());
      unawaited(c2.close());
    });

    testWidgets('inserting a stream at the head keeps the others',
        (tester) async {
      final c1 = StreamController<int>.broadcast();
      final c2 = StreamController<int>.broadcast();
      final inserted = StreamController<int>.broadcast();

      // A raw controller's `.stream` is a new wrapper on every access, so the
      // instances have to be held for the reconciliation to see them again.
      final s1 = c1.stream;
      final s2 = c2.stream;
      final sInserted = inserted.stream;

      Widget build(List<Stream<int>> streams) => _dir(
            MStreamBuilder<int>(
              key: const Key('msb-insert'),
              streams: streams,
              builder: (context, data) =>
                  Text(data.map((v) => v ?? '_').join('-')),
            ),
          );

      await tester.pumpWidget(build([s1, s2]));
      c1.add(1);
      c2.add(2);
      await tester.pumpAndSettle();
      expect(find.text('1-2'), findsOneWidget);

      // Both existing streams shift one index to the right. They must not be
      // torn down, and their values must move with them.
      await tester.pumpWidget(build([sInserted, s1, s2]));
      expect(find.text('_-1-2'), findsOneWidget);

      inserted.add(0);
      await tester.pumpAndSettle();
      expect(find.text('0-1-2'), findsOneWidget);

      unawaited(c1.close());
      unawaited(c2.close());
      unawaited(inserted.close());
    });

    testWidgets('a stream list mutated in place is still reconciled',
        (tester) async {
      final c1 = StreamController<int>.broadcast();
      final c2 = StreamController<int>.broadcast();
      final s1 = c1.stream;
      final s2 = c2.stream;

      // One list instance, mutated in place: by the time didUpdateWidget runs,
      // `oldWidget.streams` and `widget.streams` are the same object, so the
      // check has to be against the slots that are actually subscribed.
      final streams = <Stream<int>>[s1];
      Widget build() => _dir(
            MStreamBuilder<int>(
              key: const Key('msb-mutate'),
              streams: streams,
              builder: (context, data) =>
                  Text(data.map((v) => v ?? '_').join('-')),
            ),
          );

      await tester.pumpWidget(build());
      c1.add(1);
      await tester.pumpAndSettle();
      expect(find.text('1'), findsOneWidget);

      streams.add(s2);
      await tester.pumpWidget(build());
      expect(find.text('1-_'), findsOneWidget);

      c2.add(2);
      await tester.pumpAndSettle();
      expect(find.text('1-2'), findsOneWidget);

      unawaited(c1.close());
      unawaited(c2.close());
    });

    test('an observable hands out the same stream object every time', () {
      // What makes the identity matching above work: a caller that writes
      // `streams: [x.stream]` inside `build()` must not look like it swapped its
      // stream on every rebuild.
      final state = ObservableState<int>(0);
      expect(identical(state.stream, state.stream), isTrue);
      state.dispose();
    });
  });
}

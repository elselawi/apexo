import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apexo/core/multi_stream_builder.dart';

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

      controller1.close();
      controller2.close();
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

      controller1.add('test1');
      await tester.pump();
      expect(capturedData, ['test1', null]);

      controller2.add('test2');
      await tester.pump();
      expect(capturedData, ['test1', 'test2']);

      controller1.close();
      controller2.close();
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
      await tester.pump();
      expect(capturedData, [null, 2, null]);

      controller1.add(1);
      await tester.pump();
      expect(capturedData, [1, 2, null]);

      controller3.add(3);
      await tester.pump();
      expect(capturedData, [1, 2, 3]);

      controller1.close();
      controller2.close();
      controller3.close();
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

      controller1.close();
      controller2.close();
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
      controller.close();
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
      c1.close();
      c2.close();
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
      c1.close();
      c2.close();
      c3.close();
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
      c1.close();
      c2.close();
      replacement1.close();
      replacement2.close();
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

      await controller.close();
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

      await oldController.close();
      await newController.close();
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

      await controller.close();
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
      controller.close();
    });
  });
}

import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apexo/core/multi_stream_builder.dart';

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

    testWidgets('should handle stream updates in correct order', (tester) async {
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
  });
}

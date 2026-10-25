import 'dart:async';

import 'package:apexo/utils/error_reporting.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  FlutterErrorDetails detailsWith({
    Object exception = 'boom',
    String? library = 'widgets library',
    DiagnosticsNode? context,
    Iterable<DiagnosticsNode> Function()? information,
  }) =>
      FlutterErrorDetails(
        exception: exception,
        library: library,
        context: context,
        informationCollector: information,
      );

  Iterable<DiagnosticsNode> causingWidget(String description) =>
      <DiagnosticsNode>[
        DiagnosticsBlock(
          name: 'The relevant error-causing widget was',
          children: <DiagnosticsNode>[ErrorDescription(description)],
        ),
        ErrorSpacer(),
      ];

  group('errorCausingWidget', () {
    test('returns the widget the framework blames, with its source position',
        () {
      final details = detailsWith(
        information: () =>
            causingWidget('WindowShell (file:///a/window_shell.dart:72:12)'),
      );

      expect(
        errorCausingWidget(details),
        'WindowShell (file:///a/window_shell.dart:72:12)',
      );
    });

    test('is null when the framework collected no widget', () {
      expect(errorCausingWidget(detailsWith()), isNull);
      expect(
        errorCausingWidget(detailsWith(
          information: () => <DiagnosticsNode>[ErrorDescription('no widget')],
        )),
        isNull,
      );
    });

    test('survives a collector that throws', () {
      final details = detailsWith(
        information: () => throw StateError('the failing widget again'),
      );

      expect(errorCausingWidget(details), isNull);
      expect(describeFlutterError(details), contains('boom'));
    });
  });

  group('flutterErrorInformation', () {
    test('includes nested diagnostics as readable text', () {
      final details = detailsWith(
        information: () => causingWidget('WindowShell\n  at app.dart:72'),
      );
      expect(
        flutterErrorInformation(details),
        contains('WindowShell at app.dart:72'),
      );
    });

    test('handles missing and broken collectors', () {
      expect(flutterErrorInformation(detailsWith()), isNull);
      expect(
        flutterErrorInformation(detailsWith(information: () => [])),
        isNull,
      );
      expect(
        flutterErrorInformation(detailsWith(
          information: () => throw StateError('collector failed'),
        )),
        isNull,
      );
    });

    test('bounds the recorded diagnostic text', () {
      final details = detailsWith(
        information: () => [ErrorDescription('x' * 5000)],
      );
      expect(flutterErrorInformation(details)!.length, lessThanOrEqualTo(801));
    });
  });

  group('describeFlutterError', () {
    test('names the context, the error and the widget on one line', () {
      final details = detailsWith(
        exception: 'Null check operator used on a null value',
        context:
            ErrorDescription('thrown while handling a pointer data packet'),
        information: () =>
            causingWidget('WindowsLayer (file:///a/app.dart:245:16)'),
      );

      expect(
        describeFlutterError(details),
        'widgets library · thrown while handling a pointer data packet · '
        'Null check operator used on a null value · '
        'WindowsLayer (file:///a/app.dart:245:16)',
      );
    });

    test('collapses the line breaks the framework writes', () {
      final details = detailsWith(
        context: ErrorDescription('during layout\n  of the tree'),
      );

      expect(
          describeFlutterError(details), contains('during layout of the tree'));
    });

    test('is clamped so it survives a breadcrumb', () {
      final details = detailsWith(exception: 'x' * 5000);

      expect(describeFlutterError(details).length, lessThanOrEqualTo(401));
    });
  });

  group('BreadcrumbLimiter', () {
    late DateTime now;
    late BreadcrumbLimiter limiter;

    setUp(() {
      now = DateTime.utc(2026, 10, 8, 11, 45);
      limiter = BreadcrumbLimiter(clock: () => now);
    });

    Breadcrumb crumb(String message) =>
        Breadcrumb(category: 'flutter.error', message: message);

    test('lets the first of a repeated line through and drops the rest', () {
      expect(limiter.limit(crumb('same'), Hint()), isNotNull);
      expect(limiter.limit(crumb('same'), Hint()), isNull);
      expect(limiter.limit(crumb('same'), Hint()), isNull);
    });

    test('reports the count it swallowed on the next one it lets through', () {
      limiter.limit(crumb('same'), Hint());
      limiter.limit(crumb('same'), Hint());
      limiter.limit(crumb('same'), Hint());

      now = now.add(const Duration(seconds: 3));

      expect(limiter.limit(crumb('same'), Hint())!.message, 'same (×3)');
    });

    test('does not hold back a different line', () {
      limiter.limit(crumb('first'), Hint());

      expect(limiter.limit(crumb('second'), Hint()), isNotNull);
    });

    test('separates lines by category', () {
      limiter.limit(Breadcrumb(category: 'app', message: 'same'), Hint());

      expect(
        limiter.limit(
            Breadcrumb(category: 'flutter.error', message: 'same'), Hint()),
        isNotNull,
      );
    });

    test('also suppresses Flutter debugPrint console duplicates', () {
      final first = Breadcrumb.console(message: 'Another exception was thrown');
      final second =
          Breadcrumb.console(message: 'Another exception was thrown');
      expect(limiter.limit(first, Hint()), isNotNull);
      expect(limiter.limit(second, Hint()), isNull);
    });

    test('preserves repeated SDK breadcrumbs with different data', () {
      for (final route in ['patients', 'appointments']) {
        expect(
          limiter.limit(
            Breadcrumb(category: 'navigation', data: {'to': route}),
            Hint(),
          ),
          isNotNull,
        );
      }
    });

    test('does not suppress an error after an informational app log', () {
      limiter.limit(
        Breadcrumb(category: 'app', message: 'same', level: SentryLevel.info),
        Hint(),
      );
      expect(
        limiter.limit(
          Breadcrumb(
              category: 'app', message: 'same', level: SentryLevel.error),
          Hint(),
        ),
        isNotNull,
      );
    });

    test('retains recent signatures when the cache reaches its limit', () {
      for (var i = 0; i < 101; i++) {
        limiter.limit(crumb('error $i'), Hint());
      }
      expect(limiter.limit(crumb('error 99'), Hint()), isNull);
    });
  });

  group('Sentry scope enrichment', () {
    setUp(() async {
      await Sentry.init((options) {
        options.dsn = 'https://public@localhost/1';
        for (final integration in options.integrations) {
          options.removeIntegration(integration);
        }
        options.beforeSend = (event, hint) => null;
        options.sendClientReports = false;
      });
    });

    tearDown(Sentry.close);

    test('sets context and breadcrumb before the wrapped handler runs',
        () async {
      final original = FlutterError.onError;
      addTearDown(() => FlutterError.onError = original);
      Object? context;
      List<Breadcrumb>? breadcrumbs;
      FutureOr<void>? inspection;
      installFlutterErrorReporting(previous: (_) {
        inspection = Sentry.configureScope((scope) {
          context = scope.contexts['last framework error'];
          breadcrumbs = scope.breadcrumbs.toList();
        });
      });

      FlutterError.onError!(detailsWith(exception: 'boom'));
      await inspection;

      expect(context, isA<Map<String, dynamic>>());
      expect((context! as Map<String, dynamic>)['error'], 'boom');
      expect(breadcrumbs!.single.category, 'flutter.error');
    });

    test('reporting failures do not prevent the original handler', () async {
      final original = FlutterError.onError;
      addTearDown(() => FlutterError.onError = original);
      final seen = <FlutterErrorDetails>[];
      installFlutterErrorReporting(previous: seen.add);
      final details = detailsWith(exception: _BrokenDescription());

      FlutterError.onError!(details);
      await Future<void>.delayed(Duration.zero);

      expect(seen, [details]);
    });
  });

  test(
      'installFlutterErrorReporting hands the error on to the handler it wrapped',
      () {
    final seen = <FlutterErrorDetails>[];
    final original = FlutterError.onError;
    addTearDown(() => FlutterError.onError = original);

    installFlutterErrorReporting(previous: seen.add);
    FlutterError.onError!(detailsWith(exception: 'boom'));

    expect(seen, hasLength(1));
    expect(seen.single.exception, 'boom');
  });
}

class _BrokenDescription {
  @override
  String toString() => throw StateError('description failed');
}

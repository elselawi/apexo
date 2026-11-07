/// Adds readable framework diagnostics to Sentry breadcrumbs and scope context;
/// widget creation sites are debug-only and absent in release builds.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

const String _causingWidgetMarker = 'relevant error-causing widget was';
const int _maxErrorLength = 160;
const int _maxMessageLength = 400;
const int _maxInformationLength = 800;

String describeFlutterError(FlutterErrorDetails details) =>
    _describeFlutterError(details, errorCausingWidget(details));

String _describeFlutterError(FlutterErrorDetails details, String? widget) {
  final context =
      details.context == null ? null : _oneLine(_describe(details.context!));
  final parts = <String>[
    if (details.library?.isNotEmpty ?? false) details.library!,
    if (context != null && context.isNotEmpty) context,
    _clampLines(_oneLine(details.exception.toString()), _maxErrorLength),
    if (widget != null) widget,
  ];
  return _clampLines(parts.join(' · '), _maxMessageLength);
}

/// Creation site of the widget the framework blames, or the chain it was built
/// from; null in release builds, where `debugCreator` and inspector data are absent.
String? errorCausingWidget(FlutterErrorDetails details) {
  final collector = details.informationCollector;
  if (collector == null) return null;
  try {
    String? creator;
    for (final node in collector()) {
      if (_nodeText(node).contains(_causingWidgetMarker)) {
        for (final child in node.getChildren()) {
          final text = _oneLine(_describe(child));
          if (text.isNotEmpty) return text;
        }
        final text = _oneLine(_describe(node));
        if (text.isNotEmpty) return text;
      }
      if (node.name == 'debugCreator') {
        creator ??= _widgetChain(_oneLine(_describe(node)));
      }
    }
    return creator;
  } catch (_) {
    // The collector can fail the same way the widget did; a missing breadcrumb
    // beats a second error thrown inside the error handler.
  }
  return null;
}

String? flutterErrorInformation(FlutterErrorDetails details) {
  final collector = details.informationCollector;
  if (collector == null) return null;
  try {
    final collected = <String>[];
    for (final node in collector()) {
      final text = _oneLine(_allText(node));
      if (text.isNotEmpty) collected.add(text);
    }
    if (collected.isEmpty) return null;
    return _clampLines(collected.join(' | '), _maxInformationLength);
  } catch (_) {
    return null;
  }
}

/// Records [details] on the scope Sentry will attach to its next event.
Future<void> recordFlutterError(FlutterErrorDetails details) async {
  try {
    final widget = errorCausingWidget(details);
    final information = flutterErrorInformation(details);
    final data = <String, dynamic>{
      if (details.library?.isNotEmpty ?? false) 'library': details.library,
      if (information != null) 'information': information,
      if (widget != null) 'causing_widget': widget,
    };
    final message = _describeFlutterError(details, widget);
    final error = _clampLines(
      _oneLine(details.exception.toString()),
      _maxMessageLength,
    );
    // Both run before yielding to Sentry's handler; awaiting the observers first
    // would leave this event without its context.
    final contextUpdate = Sentry.configureScope((scope) {
      return scope.setContexts('last framework error', <String, dynamic>{
        ...data,
        'error': error,
      });
    });
    final breadcrumbUpdate = Sentry.addBreadcrumb(Breadcrumb(
      category: 'flutter.error',
      level: SentryLevel.error,
      message: message,
      data: data,
    ));
    await Future.wait<void>([
      Future<void>.value(contextUpdate),
      breadcrumbUpdate,
    ]);
  } catch (_) {
    // Reporting must not throw or interrupt Flutter's existing error handler.
  }
}

/// Wraps Flutter's current error handler so every framework error is recorded
/// first; install after `SentryFlutter.init` to chain Sentry's handler.
void installFlutterErrorReporting({FlutterExceptionHandler? previous}) {
  final next = previous ?? FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    unawaited(recordFlutterError(details));
    next?.call(details);
  };
}

/// Suppresses repeated app, framework and console breadcrumbs within [window];
/// navigation and other SDK breadcrumbs pass through untouched.
class BreadcrumbLimiter {
  BreadcrumbLimiter({
    this.window = const Duration(seconds: 2),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// How long an identical breadcrumb is suppressed for.
  final Duration window;

  final DateTime Function() _clock;

  /// Bounded at [_maxSignatures], so an app logging unbounded distinct messages
  /// cannot grow this map for the life of the session.
  final Map<(String?, String?, SentryLevel?), _Repeated> _seen = {};

  static const int _maxSignatures = 100;

  Breadcrumb? limit(Breadcrumb? breadcrumb, Hint hint) {
    if (breadcrumb == null) return null;
    if (breadcrumb.category != 'app' &&
        breadcrumb.category != 'flutter.error' &&
        breadcrumb.category != 'console') {
      return breadcrumb;
    }
    final signature = (breadcrumb.category, breadcrumb.message, breadcrumb.level);
    final now = _clock();
    final seen = _seen[signature];
    if (seen != null && now.difference(seen.last) < window) {
      seen.suppressed++;
      return null;
    }
    final suppressed = seen?.suppressed ?? 0;
    _seen.remove(signature);
    if (_seen.length >= _maxSignatures) _seen.remove(_seen.keys.first);
    _seen[signature] = _Repeated(now);
    if (suppressed == 0) return breadcrumb;
    breadcrumb.message = '${breadcrumb.message} (×${suppressed + 1})';
    return breadcrumb;
  }
}

/// The limiter the app installs as `SentryOptions.beforeBreadcrumb`.
final BreadcrumbLimiter breadcrumbLimiter = BreadcrumbLimiter();

class _Repeated {
  _Repeated(this.last);

  final DateTime last;
  int suppressed = 0;
}

String _describe(DiagnosticsNode node) {
  final description = node.toDescription();
  if (description.isNotEmpty) return description;
  // A diagnostics property builds its description inside an `assert`, so release
  // builds read it as empty; its value is still there.
  if (node is DiagnosticsProperty) {
    final value = node.value;
    if (value != null) return value.toString();
  }
  final text = node.toString();
  return text.startsWith('Instance of ') ? '' : text;
}

/// The first few steps of the `A ← B ← C` chain a `debugCreator` node holds.
String _widgetChain(String chain) {
  final steps = chain.split(' ← ');
  if (steps.length <= 3) return chain;
  return '${steps.take(3).join(' ← ')} ← …';
}

String _nodeText(DiagnosticsNode node) {
  final name = node.name ?? '';
  return '$name ${_describe(node)}'.trim();
}

String _allText(DiagnosticsNode node) {
  final children = node.getChildren();
  if (children.isEmpty) return _nodeText(node);
  return [_nodeText(node), children.map(_allText).join(' ')].join(' ');
}

String _oneLine(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

String _clampLines(String text, int limit) =>
    text.length <= limit ? text : '${text.substring(0, limit)}…';

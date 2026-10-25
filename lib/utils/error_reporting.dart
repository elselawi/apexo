/// Adds readable framework diagnostics to Sentry breadcrumbs and scope context.
/// Widget creation sites are included only when Flutter collected them; release
/// builds generally lack the debug-only inspector and creator information.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

const String _causingWidgetMarker = 'relevant error-causing widget was';
const int _maxErrorLength = 160;
const int _maxMessageLength = 400;
const int _maxInformationLength = 800;

/// One line that locates [details]: which library caught it, what was happening,
/// what broke, and the widget that caused it.
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

/// The creation site of the widget the framework blames, or the chain it was
/// built from, e.g. `WindowShell ← LayoutBuilder ← …`, or null when the
/// framework tracked neither.
///
/// The `WidgetInspectorService` block that names the widget's file and line is
/// only added while the inspector runs — in debug and profile builds, with
/// widget creation tracking on. The `debugCreator` chain is also debug-only;
/// without either, the error's context may still name the failing widget.
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
    // The collector is a closure over the failing widget's own state: whatever
    // made it fail can make this fail too. A missing breadcrumb is better than
    // a second error inside the error handler.
  }
  return null;
}

/// Everything the framework collected about [details], on one line: the widget
/// that caused it, the advice for fixing it, the constraints it was given.
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
    // Both mutations happen before yielding to Sentry's error handler. Waiting
    // for breadcrumb observers first would leave this event without its context.
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
    // Error reporting must not create another unhandled error or interrupt
    // Flutter's existing handler when diagnostics or SDK observers fail.
  }
}

/// Sends every framework error through [recordFlutterError] before handing it to
/// the handler already installed — Sentry's own, when called after
/// `SentryFlutter.init`.
void installFlutterErrorReporting({FlutterExceptionHandler? previous}) {
  final next = previous ?? FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    unawaited(recordFlutterError(details));
    next?.call(details);
  };
}

/// Collapses repeated app, framework and console messages within [window].
/// Navigation and other SDK breadcrumbs retain their data and are not filtered.
class BreadcrumbLimiter {
  BreadcrumbLimiter({
    this.window = const Duration(seconds: 2),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// How long an identical breadcrumb is suppressed for.
  final Duration window;

  final DateTime Function() _clock;

  /// Bounded: an app that logs unbounded distinct messages must not grow this
  /// map for the life of the session.
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
  // A diagnostics property builds its description inside an `assert`, so in a
  // release build it reads as empty — its value is still there.
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

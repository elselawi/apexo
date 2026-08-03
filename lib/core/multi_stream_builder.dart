import 'dart:async';
import 'package:flutter/widgets.dart';

/// This widget builder simply builds a widget that depends on a list of streams
class MStreamBuilder<T> extends StatefulWidget {
  final List<Stream<T>> streams;
  final Widget Function(BuildContext context, List<T?> data) builder;

  const MStreamBuilder({
    required this.streams,
    required this.builder,
    super.key,
  });

  @override
  createState() => _MStreamBuilderState<T>();
}

class _MStreamBuilderState<T> extends State<MStreamBuilder<T>> {
  late List<T?> _data;
  late List<StreamSubscription<T>> _subscriptions;
  int _subscriptionGeneration = 0;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  void _subscribe() {
    final generation = ++_subscriptionGeneration;
    _data = List<T?>.filled(widget.streams.length, null);
    _subscriptions = _listenTo(widget.streams, generation);
  }

  List<StreamSubscription<T>> _listenTo(
      List<Stream<T>> streams, int generation) {
    return streams.asMap().entries.map((entry) {
      final index = entry.key;
      final stream = entry.value;
      return stream.listen((value) {
        if (!mounted || generation != _subscriptionGeneration) return;
        setState(() {
          _data[index] = value;
        });
      });
    }).toList();
  }

  @override
  void didUpdateWidget(covariant MStreamBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameStreams(oldWidget.streams, widget.streams)) {
      ++_subscriptionGeneration;
      for (final subscription in _subscriptions) {
        subscription.cancel();
      }
      _subscribe();
    }
  }

  bool _sameStreams(List<Stream<T>> first, List<Stream<T>> second) {
    if (identical(first, second)) return true;
    if (first.length != second.length) return false;
    for (var i = 0; i < first.length; i++) {
      if (first[i] != second[i]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _subscriptionGeneration++;
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _data);
  }
}

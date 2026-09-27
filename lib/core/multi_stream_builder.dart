/// use this class MStreamBuilder in flutter widget
/// to listen to multiple streams, as opposed to Streambuilder
/// which listens to a single one.
library;

import 'dart:async';
import 'package:apexo/utils/logger.dart';
import 'package:flutter/widgets.dart';

/// This widget builder simply builds a widget that depends on a list of streams
class MStreamBuilder<T> extends StatefulWidget {
  const MStreamBuilder({
    required this.streams,
    required this.builder,
    super.key,
  });

  /// The streams to watch
  final List<Stream<T>> streams;
  final Widget Function(BuildContext context, List<T?> data) builder;

  @override
  State<MStreamBuilder<T>> createState() => _MStreamBuilderState<T>();
}

class _MStreamBuilderState<T> extends State<MStreamBuilder<T>> {
  /// One entry per live subscription, always in `data` order.
  final List<_StreamSlot<T>> _slots = [];

  @override
  void initState() {
    super.initState();
    _slots.addAll(widget.streams.map(_subscribe));
  }

  @override
  void didUpdateWidget(covariant MStreamBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_slotsMatch(widget.streams)) _reconcile();
  }

  /// Whether the live subscriptions already line up with [streams], in order.
  bool _slotsMatch(List<Stream<T>> streams) {
    if (streams.length != _slots.length) return false;
    for (var i = 0; i < streams.length; i++) {
      if (!identical(_slots[i].stream, streams[i])) return false;
    }
    return true;
  }

  StreamSubscription<T> _listenTo(_StreamSlot<T> slot) {
    return slot.stream.listen(
      (value) {
        if (!mounted || slot.dropped) return;
        setState(() {
          slot.value = value;
        });
      },
      onError: (Object e, StackTrace s) {
        if (!mounted || slot.dropped) return;
        logger(
            'A stream watched by MStreamBuilder reported an error: $e', s, 2);
      },
    );
  }

  _StreamSlot<T> _subscribe(Stream<T> stream) {
    final slot = _StreamSlot<T>(stream);
    slot.subscription = _listenTo(slot);
    return slot;
  }

  /// Matches the widget's streams to the live subscriptions **by identity**.
  void _reconcile() {
    final unused = List<_StreamSlot<T>>.of(_slots);
    final matched = <_StreamSlot<T>>[];
    final fresh = <_StreamSlot<T>>[];

    for (final stream in widget.streams) {
      final existing = _takeMatching(unused, stream);
      if (existing != null) {
        matched.add(existing);
      } else {
        final slot = _StreamSlot<T>(stream);
        fresh.add(slot);
        matched.add(slot);
      }
    }

    // Whatever is left is not in the list any more.
    for (final slot in unused) {
      slot.cancel();
    }

    // Publish the new list *before* listening: a stream that emits synchronously
    // on `listen` would otherwise write into a slot the current build cannot see.
    _slots
      ..clear()
      ..addAll(matched);

    for (final slot in fresh) {
      slot.subscription = _listenTo(slot);
    }
  }

  /// Removes and returns the first slot in [slots] listening to [stream].
  _StreamSlot<T>? _takeMatching(List<_StreamSlot<T>> slots, Stream<T> stream) {
    for (var i = 0; i < slots.length; i++) {
      if (identical(slots[i].stream, stream)) return slots.removeAt(i);
    }
    return null;
  }

  /// A snapshot of the current values, in `widget.streams` order.
  List<T?> _values() => [for (final slot in _slots) slot.value];

  @override
  void dispose() {
    for (final slot in _slots) {
      slot.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _values());
  }
}

/// One live subscription: the stream it listens to and the value that stream
/// last delivered. Its position in `_slots` *is* its index in `data`.
class _StreamSlot<T> {
  _StreamSlot(this.stream);

  final Stream<T> stream;
  T? value;
  StreamSubscription<T>? subscription;

  /// Set as soon as the slot is dropped, so an event from a subscription whose
  /// `cancel()` has not completed yet is ignored.
  bool dropped = false;

  void cancel() {
    dropped = true;
    unawaited(subscription?.cancel());
  }
}

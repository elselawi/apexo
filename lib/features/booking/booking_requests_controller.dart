import 'dart:async';
import 'dart:math';

import 'package:apexo/core/reactive/observable.dart';
import 'package:apexo/features/booking/booking_api.dart';
import 'package:apexo/features/booking/booking_models.dart';
import 'package:apexo/services/localization/locale.dart';

/// A saved appointment whose inbox update has not reached the Worker yet.
/// Metadata only (never patient fields), replayed inside the same session.
class PendingBookingLink {
  PendingBookingLink({
    required this.requestId,
    required this.expectedVersion,
    required this.appointmentId,
    this.confirmed = true,
  });

  final String requestId;
  final int expectedVersion;
  final String appointmentId;
  final bool confirmed;
}

/// Session-scoped, memory-only cache: there is no certified secure-key store
/// for a per-clinic Hive key, so requests must never be persisted.
class BookingRequestsCache {
  final Map<String, List<BookingRequest>> _byFilter = {};

  List<BookingRequest> forFilter(String filter) =>
      List<BookingRequest>.unmodifiable(_byFilter[filter] ?? const []);

  /// Replaces a filter's contents only after a complete authoritative refresh.
  void replaceFilter(String filter, List<BookingRequest> items) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _byFilter[filter] = items.where((item) => item.expiresAt > now).toList();
  }

  BookingRequest? byId(String requestId) {
    BookingRequest? newest;
    for (final items in _byFilter.values) {
      for (final item in items) {
        if (item.requestId == requestId && !item.isExpired &&
            (newest == null || item.version > newest.version)) {
          newest = item;
        }
      }
    }
    return newest;
  }

  void upsert(BookingRequest request) {
    for (final entry in _byFilter.entries) {
      final index =
          entry.value.indexWhere((item) => item.requestId == request.requestId);
      if (!request.isExpired &&
          (request.status == entry.key || entry.key == "all")) {
        if (index == -1) {
          entry.value.add(request);
        } else {
          entry.value[index] = request;
        }
      } else if (index != -1) {
        entry.value.removeAt(index);
      }
    }
  }

  void remove(String requestId) {
    for (final items in _byFilter.values) {
      items.removeWhere((item) => item.requestId == requestId);
    }
  }

  void purgeExpired() {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final items in _byFilter.values) {
      items.removeWhere((item) => item.expiresAt <= now);
    }
  }

  void clear() => _byFilter.clear();
}

/// Polling and inbox state for one clinic/account session. Async results are
/// generation-bound so a logout or clinic switch cannot publish stale data.
class BookingRequestsController {
  BookingRequestsController({BookingApi? api}) : _api = api;

  BookingApi? _api;
  BookingClinicRecord? _clinic;
  String _sessionKey = "";

  final BookingRequestsCache cache = BookingRequestsCache();

  final filter = ObservableState<String>("pending");
  final items = ObservableState<List<BookingRequest>>(const []);
  final pending = ObservableState<int>(0);
  final refreshing = ObservableState<bool>(false);
  final connected = ObservableState<bool>(true);
  final revoked = ObservableState<bool>(false);
  final stale = ObservableState<bool>(false);
  final lastSuccessfulAt = ObservableState<int?>(null);
  final pendingLinks = ObservableState<List<PendingBookingLink>>(const []);

  Timer? _timer;
  int _generation = 0;
  Future<void>? _refreshInFlight;
  int _stateRevision = 0;
  final Set<String> _transitioned = {};
  final Set<String> _scheduling = {};

  bool beginScheduling(String requestId) => isAttached && _scheduling.add(requestId);

  void finishScheduling(String requestId, int generation) {
    if (generation == _generation) _scheduling.remove(requestId);
  }
  Duration _backoff = const Duration(seconds: 15);
  static const Duration foregroundInterval = Duration(minutes: 15);
  static const Duration staleAfter = Duration(minutes: 30);

  bool get isAttached => _clinic != null && !revoked();

  String get sessionKey => _sessionKey;

  void attach({
    required BookingApi api,
    required BookingClinicRecord clinic,
    required String accountId,
  }) {
    final key = "${api.origin}|${clinic.clinicId}|$accountId";
    final links = key == _sessionKey ? pendingLinks() : <PendingBookingLink>[];
    detach();
    pendingLinks(links);
    _api = api;
    _clinic = clinic;
    _sessionKey = key;
    _generation++;
    _backoff = const Duration(seconds: 15);
    revoked(false);
    connected(true);
    startForegroundPolling();
  }

  void detach() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _clinic = null;
    _refreshInFlight = null;
    _lastRefreshedFilter = null;
    _sessionKey = "";
    lastSuccessfulAt(null);
    connected(true);
    revoked(false);
    items(const []);
    pending(0);
    stale(false);
    refreshing(false);
    cache.clear();
    _transitioned.clear();
    _scheduling.clear();
    pendingLinks(const []);
  }

  int get generation => _generation;

  /// One refresh at a time per session; triggers coalesce.
  Future<void> refresh({String? status}) async {
    final clinic = _clinic;
    final api = _api;
    if (clinic == null || api == null || revoked()) return;
    final generation = _generation;
    final activeFilter = status ?? filter();
    final inFlight = _refreshInFlight;
    if (inFlight != null) {
      await inFlight;
      if (generation == _generation &&
          _lastRefreshedFilter != activeFilter) {
        await refresh(status: activeFilter);
      }
      return;
    }
    final task = _refresh(api, clinic, generation, activeFilter);
    _refreshInFlight = task;
    try {
      await task;
    } finally {
      if (identical(_refreshInFlight, task)) _refreshInFlight = null;
    }
    if (generation == _generation && status == null &&
        activeFilter != "pending" && connected()) {
      await refresh(status: "pending");
    }
  }

  String? _lastRefreshedFilter;

  Future<void> _refresh(BookingApi api, BookingClinicRecord clinic,
      int generation, String activeFilter) async {
    refreshing(true);
    try {
      await _replayPendingLinks(api, clinic, generation);
      if (generation != _generation) return;
      final stateRevision = _stateRevision;
      final collected = <BookingRequest>[];
      int? beforeSeq;
      String? snapshot;
      var pageCount = 0;
      var pagePending = 0;
      while (true) {
        final page = await api.pull(
          clinic.inboxKey,
          status: activeFilter,
          beforeSeq: beforeSeq,
          snapshot: snapshot,
        );
        if (generation != _generation) return;
        collected.addAll(page.items);
        pagePending = page.pending;
        if (page.nextBeforeSeq == null) break;
        if (++pageCount > 200 ||
            (beforeSeq != null && page.nextBeforeSeq! >= beforeSeq)) {
          throw StateError("booking_incomplete_snapshot");
        }
        beforeSeq = page.nextBeforeSeq;
        snapshot = page.snapshot;
      }
      if (stateRevision != _stateRevision) {
        await _refresh(api, clinic, generation, activeFilter);
        return;
      }
      cache.replaceFilter(activeFilter, collected);
      _lastRefreshedFilter = activeFilter;
      if (activeFilter == filter()) items(cache.forFilter(activeFilter));
      pending(pagePending);
      connected(true);
      revoked(false);
      lastSuccessfulAt(DateTime.now().millisecondsSinceEpoch);
      stale(false);
      _backoff = const Duration(seconds: 15);
    } on BookingApiException catch (error) {
      if (generation != _generation) return;
      if (error.keyRevoked) {
        revoked(true);
        connected(false);
        _timer?.cancel();
        return;
      }
      connected(false);
      final retryAfter = error.retryAfter;
      _backoff = _nextBackoff(retryAfter);
    } catch (_) {
      if (generation != _generation) return;
      connected(false);
      _backoff = _nextBackoff(null);
    } finally {
      if (generation == _generation) {
        refreshing(false);
        _markStaleIfNeeded();
        scheduleNextRefresh(connected() ? foregroundInterval : _backoff);
      }
    }
  }

  Duration _nextBackoff(Duration? retryAfter) {
    if (retryAfter != null && retryAfter > Duration.zero) return retryAfter;
    final doubled = _backoff * 2;
    final capped = doubled > const Duration(minutes: 5)
        ? const Duration(minutes: 5)
        : doubled;
    // Jitter prevents every device in a clinic from retrying in lockstep.
    final jitter = (Random().nextDouble() * 0.25 + 0.9);
    return Duration(milliseconds: (capped.inMilliseconds * jitter).round());
  }

  void _markStaleIfNeeded() {
    final last = lastSuccessfulAt();
    if (last == null) {
      stale(true);
      return;
    }
    stale(DateTime.now().millisecondsSinceEpoch - last > staleAfter.inMilliseconds);
  }

  void startForegroundPolling() {
    _timer?.cancel();
    scheduleNextRefresh(foregroundInterval);
  }

  void scheduleNextRefresh(Duration delay) {
    _timer?.cancel();
    if (revoked() || _clinic == null) return;
    final generation = _generation;
    _timer = Timer(delay, () {
      if (generation != _generation) return;
      unawaited(refresh());
    });
  }

  void switchFilter(String value) {
    filter(value);
    cache.purgeExpired();
    items(List.unmodifiable(cache.forFilter(value)));
    unawaited(refresh(status: value));
  }

  /// Applies the local transition and returns the acknowledged version.
  Future<int> markHandled(BookingRequest request, String appointmentId) async {
    final api = _api;
    final clinic = _clinic;
    if (api == null || clinic == null) throw StateError("booking_session_missing");
    final generation = _generation;
    final version = await api.setRequestState(
      clinic.inboxKey,
      requestId: request.requestId,
      expectedVersion: request.version,
      state: "handled",
      linkedId: appointmentId,
    );
    if (generation != _generation) return version;
    final updated = request.copyWith(
      status: "handled",
      version: version,
      handledAt: DateTime.now().millisecondsSinceEpoch,
      linkedId: appointmentId,
    );
    _stateRevision++;
    cache.upsert(updated);
    if (request.isPending && _transitioned.add(request.requestId)) {
      pending(max(0, pending() - 1));
    }
    forgetPendingLink(request.requestId);
    items(List.unmodifiable(cache.forFilter(filter())));
    return version;
  }

  Future<int> decline(BookingRequest request) async {
    final api = _api;
    final clinic = _clinic;
    if (api == null || clinic == null) throw StateError("booking_session_missing");
    final generation = _generation;
    final version = await api.setRequestState(
      clinic.inboxKey,
      requestId: request.requestId,
      expectedVersion: request.version,
      state: "declined",
    );
    if (generation != _generation) return version;
    final updated = request.copyWith(
      status: "declined",
      version: version,
      handledAt: DateTime.now().millisecondsSinceEpoch,
    );
    _stateRevision++;
    cache.upsert(updated);
    if (request.isPending && _transitioned.add(request.requestId)) {
      pending(max(0, pending() - 1));
    }
    items(List.unmodifiable(cache.forFilter(filter())));
    return version;
  }

  /// Remembers an undelivered inbox update. The appointment is already saved,
  /// so the retry must never create another one.
  void rememberPendingLink(BookingRequest request, String appointmentId,
      {bool confirmed = true}) {
    final list = [...pendingLinks()]
      ..removeWhere((link) => link.requestId == request.requestId)
      ..add(PendingBookingLink(
        requestId: request.requestId,
        expectedVersion: request.version,
        appointmentId: appointmentId,
        confirmed: confirmed,
      ));
    pendingLinks(List.unmodifiable(list));
  }

  void forgetPendingLink(String requestId) {
    pendingLinks(List.unmodifiable(
        pendingLinks().where((link) => link.requestId != requestId).toList()));
  }

  Future<void> _replayPendingLinks(
    BookingApi api,
    BookingClinicRecord clinic,
    int generation,
  ) async {
    for (final link in List<PendingBookingLink>.from(pendingLinks())) {
      if (generation != _generation) return;
      if (!link.confirmed) continue;
      try {
        await api.setRequestState(
          clinic.inboxKey,
          requestId: link.requestId,
          expectedVersion: link.expectedVersion,
          state: "handled",
          linkedId: link.appointmentId,
        );
        if (generation != _generation) return;
        forgetPendingLink(link.requestId);
      } on BookingApiException catch (error) {
        if (generation != _generation) return;
        // Erased, expired, or handled elsewhere: stop retrying; the next refresh
        // reconciles.
        if (error.keyRevoked) rethrow;
        if (error.notFound || error.conflict) forgetPendingLink(link.requestId);
      }
    }
  }

  String statusLabel(BookingRequest request) => switch (request.status) {
        "handled" => txt("bookingStatusHandled"),
        "declined" => txt("bookingStatusDeclined"),
        _ => txt("bookingStatusPending"),
      };
}


import 'dart:async';

import 'package:apexo/core/synchronization/push_data.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/notifications/listeners.dart';
import 'package:apexo/services/notifications/notification_session.dart';
import 'package:apexo/services/notifications/push_platform.dart';
import 'package:apexo/services/notifications/push_relay.dart';
import 'package:apexo/utils/logger.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// What made this ingress event exist.
///
/// A raw WNS push and a local-toast click are different user events even though
/// both can carry the same `PushData`: a raw push displays a toast, while a
/// click navigates to the record and must not display a second toast.
enum WindowsPushOrigin { stream, rawLaunch, toastClick }

/// Whether [origin] is a user click.
bool isUserClick(WindowsPushOrigin origin) =>
    origin == WindowsPushOrigin.toastClick;

/// Receives Windows Notification Services pushes and turns them into the same
/// notices the other platforms show.
///
/// The native Windows side owns WNS: it holds the channel URI, keeps the
/// channel alive, and forwards each raw notification. This service reads what
/// that side reports, captures a launch payload as soon as receiving starts, and
/// dispatches through the transport-neutral [PushListeners.handlePushData].
///
/// Receiving never waits for login. Registration is a separate, bounded
/// background job that starts only after a session coordinator publishes a
/// usable staff or patient session.
class WindowsPushService with WidgetsBindingObserver {
  WindowsPushService({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
    MethodChannel? lifecycleChannel,
    Future<void> Function(
      PushData data, {
      required bool openedFromNotification,
    })? onPushData,
    Future<void> Function(Duration)? sleep,
    Duration periodicRefreshInterval = const Duration(hours: 6),
    Duration sessionWaitTimeout = const Duration(seconds: 60),
    NotificationSessionCoordinator? sessions,
    Future<String?> Function({required bool forceRefresh})? readChannel,
  })  : _method = methodChannel ?? const MethodChannel(methodChannelName),
        _events = eventChannel ?? const EventChannel(eventChannelName),
        _lifecycle =
            lifecycleChannel ?? const MethodChannel(lifecycleChannelName),
        _onPushData = onPushData,
        _sleep = sleep ?? ((duration) => Future<void>.delayed(duration)),
        _periodicRefreshInterval = periodicRefreshInterval,
        _sessionWaitTimeout = sessionWaitTimeout,
        _sessions = sessions ?? notificationSessions,
        _readChannel = readChannel;

  /// The method channel the native Windows side implements.
  static const String methodChannelName = "apexo/windows_push";

  /// The event channel carrying raw notification payloads.
  static const String eventChannelName = "apexo/windows_push/events";

  /// The additive channel that lets a hidden activation end itself once the
  /// launch payload has been handled, and lets a click promote it. Optional: an
  /// older runner has no handler.
  static const String lifecycleChannelName = "apexo/windows_push/lifecycle";

  /// A hung native acquisition must not monopolize the one refresh lane
  /// forever. The native side coalesces the next request onto the still-running
  /// worker, so a timeout here is safe.
  static const Duration channelReadTimeout = Duration(seconds: 60);

  /// How long to wait before each attempt to acquire or register the channel
  /// again. Bounded on purpose: a device that cannot register is retried five
  /// times over about a minute, then the next app start or resume tries again.
  static const List<Duration> registrationRetryDelays = [
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 16),
    Duration(seconds: 32),
  ];

  /// The app's single service: one subscription, one lifecycle observer.
  static final WindowsPushService instance = WindowsPushService();

  final MethodChannel _method;
  final EventChannel _events;
  final MethodChannel _lifecycle;

  /// Waits between retries. Tests replace it so backoff does not slow them.
  final Future<void> Function(Duration) _sleep;

  /// How often a running app actually asks WNS for a fresh channel.
  final Duration _periodicRefreshInterval;

  /// How long a push/click waits for the session boundary before it is dropped.
  final Duration _sessionWaitTimeout;

  /// Session state shared with login, patient side and the toast-click handler.
  final NotificationSessionCoordinator _sessions;

  /// Test seam for the native `getChannelUri` contract.
  final Future<String?> Function({required bool forceRefresh})? _readChannel;

  /// Replaces [PushListeners.handlePushData] in tests.
  final Future<void> Function(
    PushData data, {
    required bool openedFromNotification,
  })? _onPushData;

  bool _started = false;
  bool _supported = false;
  bool _unsupportedReported = false;
  bool _observing = false;
  bool _logoutHookAdded = false;
  bool _sessionListenerAdded = false;
  bool _launchResolved = false;
  bool _disposed = false;

  /// The newest session kind the app asked us to register for.
  bool _requestedPatient = false;
  bool _registrationRequested = false;

  /// One refresh at a time. A request that arrives during it is coalesced into
  /// one follow-up pass rather than lost or allowed to register in parallel.
  bool _refreshing = false;
  bool _refreshPending = false;
  bool _refreshPendingForce = false;

  Timer? _refreshTimer;

  /// How many retries of [registrationRetryDelays] have been used.
  int _retryAttempt = 0;
  bool _retryPending = false;
  bool _retryExhaustedReported = false;

  /// Bumped whenever a pending retry is cancelled, so a sleep that is already
  /// running cannot re-register for a session that no longer exists.
  int _retryGeneration = 0;

  StreamSubscription<dynamic>? _subscription;

  /// What the relay was last told for the current session.
  String? _registeredServer;
  String? _registeredKey;
  String? _registeredAccount;
  bool? _registeredAsPatient;

  /// Bounded recent ingress records used to pair one launch payload with its
  /// single stream echo, in either arrival order.
  final List<_IngressDelivery> _deliveries = [];
  static const int _maxDeliveries = 16;

  /// Pushes waiting for a restoring session. The native pre-window/pre-listen
  /// buffers are also bounded at 16; this keeps the Dart-side wait queue from
  /// growing without limit once the stream is already subscribed.
  int _pendingWhileRestoring = 0;

  /// Starts the native receiver and captures the launch payload.
  ///
  /// Deliberately does not wait for login, a relay key or a channel. Repeating
  /// the call keeps one subscription and one observer.
  Future<void> startReceiving() async {
    if (_started) return;
    _started = true;
    _disposed = false;

    try {
      _supported = await _method.invokeMethod<bool>("isSupported") ?? false;
    } catch (_) {
      // No native implementation (or an old one that does not know the call):
      // silence is the whole contract here.
      _reportUnsupported();
      return;
    }
    if (!_supported) {
      _reportUnsupported();
      // Registration failed, but this process may still have been started by a
      // push. Reading the launch payload lets it display and acknowledge instead
      // of staying hidden until the native hard cap.
      unawaited(_handleLaunchPayload());
      return;
    }

    _observe();
    _hookLogout();
    _addSessionListener();
    _startPeriodicRefresh();
    _subscribe();

    // Capture the activation payload without awaiting session restoration or
    // registration. This invocation is started before this method returns.
    unawaited(_handleLaunchPayload());
    _maybeStartRequestedRefresh();
  }

  /// Compatibility entry point for callers that used to start and register in
  /// one call. Registration is requested but never awaited.
  Future<void> initialize({bool isPatient = false, String? clinicKey}) async {
    await startReceiving();
    requestRegistration(isPatient: isPatient);
  }

  /// Asks for registration for [isPatient]. The actual work waits for the
  /// matching session boundary and then runs in the background.
  void requestRegistration({required bool isPatient}) {
    _requestedPatient = isPatient;
    _registrationRequested = true;
    // A repeated identifyDevice is a new bounded attempt, not a continuation of
    // a chain that may already be exhausted.
    _startNewAttempts();
    _maybeStartRequestedRefresh();
  }

  /// Reveals a hidden push process and cancels its pending exit. No-op when the
  /// process was not started by a push or is already interactive.
  Future<void> promoteToInteractive() async {
    try {
      await _lifecycle.invokeMethod<bool>("promoteToInteractive");
    } catch (_) {
      // An older runner has no handler; best effort only.
    }
  }

  /// A resume is the moment Windows can have replaced the channel, so ask WNS
  /// for a fresh one rather than trusting the native cache.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_supported) return;
    _startNewAttempts();
    _requestRefresh(force: true);
  }

  /// Stops listening and observing, and cancels every scheduled retry. Used by
  /// tests; the app keeps the service for its whole lifetime (logout only
  /// forgets the registration).
  Future<void> dispose() async {
    _disposed = true;
    _cancelRetry();
    _refreshTimer?.cancel();
    _refreshTimer = null;
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
    if (_sessionListenerAdded) {
      _sessions.removeListener(_onSessionChanged);
      _sessionListenerAdded = false;
    }
    await _subscription?.cancel();
    _subscription = null;
  }

  @visibleForTesting
  Future<void> resetForTesting() async {
    await dispose();
    if (_logoutHookAdded) {
      onLogoutCallbacks.remove(_forgetRegistration);
      _logoutHookAdded = false;
    }
    _started = false;
    _supported = false;
    _unsupportedReported = false;
    _launchResolved = false;
    _deliveries.clear();
    _pendingWhileRestoring = 0;
    _requestedPatient = false;
    _registrationRequested = false;
    _retryAttempt = 0;
    _retryExhaustedReported = false;
    _refreshing = false;
    _refreshPending = false;
    _refreshPendingForce = false;
    _cancelRetry();
    _forgetRegistration();
  }

  void _reportUnsupported() {
    if (_unsupportedReported) return;
    _unsupportedReported = true;
    logger(
      "Windows push notifications are not available on this build.",
      null,
      3,
    );
  }

  void _observe() {
    if (_observing) return;
    try {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    } catch (error) {
      // No binding means no app to resume: the channel is still registered and
      // the stream still delivers; only the resume re-check is unavailable.
      _logFailure("observing the app lifecycle", error);
    }
  }

  void _hookLogout() {
    if (_logoutHookAdded) return;
    _logoutHookAdded = true;
    onLogoutCallbacks.add(_forgetRegistration);
  }

  void _addSessionListener() {
    if (_sessionListenerAdded) return;
    _sessionListenerAdded = true;
    _sessions.addListener(_onSessionChanged);
  }

  void _onSessionChanged() {
    if (_disposed) return;
    final session = _sessions.active;
    if (session == null) {
      // Absent or restoring: no session-bound work may continue. A request that
      // belonged to the old session is discarded, not delivered to the next.
      _registrationRequested = false;
      _cancelRetry();
      _forgetRegistration();
      return;
    }

    _retryAttempt = 0;
    _retryExhaustedReported = false;
    // A retry sleep from a previous session must not wake up and register into
    // this one.
    _cancelRetry();
    if (_registrationRequested && session.isPatient == _requestedPatient) {
      _requestRefresh();
    }
  }

  /// A different account or clinic must not inherit the previous registration
  /// as if it were current, and must not inherit its retries either.
  void _forgetRegistration() {
    _registeredServer = null;
    _registeredKey = null;
    _registeredAccount = null;
    _registeredAsPatient = null;
    _cancelRetry();
    _retryAttempt = 0;
    _retryExhaustedReported = false;
  }

  /// Re-checks the channel while the app runs. The native side now performs a
  /// real WNS acquisition for a forced refresh; a cached URI is not reused.
  void _startPeriodicRefresh() {
    if (_refreshTimer != null || _periodicRefreshInterval <= Duration.zero) {
      return;
    }
    _refreshTimer = Timer.periodic(_periodicRefreshInterval, (_) {
      if (!_supported || _disposed) return;
      _startNewAttempts();
      _requestRefresh(force: true);
    });
  }

  void _startNewAttempts() {
    _cancelRetry();
    _retryAttempt = 0;
    _retryExhaustedReported = false;
  }

  void _maybeStartRequestedRefresh() {
    if (!_registrationRequested) return;
    final session = _sessions.active;
    if (session == null || session.isPatient != _requestedPatient) return;
    _requestRefresh();
  }

  void _requestRefresh({bool force = false}) {
    if (!_supported || _disposed || !_registrationRequested) return;
    if (_refreshing) {
      _refreshPending = true;
      _refreshPendingForce = _refreshPendingForce || force;
      return;
    }
    unawaited(_refreshRegistration(forceRefresh: force));
  }

  /// Tries again later, at most [registrationRetryDelays] times per failure.
  void _scheduleRetry(NotificationSessionSnapshot snapshot) {
    if (!_supported || _disposed || _retryPending) return;
    if (!_stillCurrent(snapshot) || !_registrationRequested) return;
    if (_retryAttempt >= registrationRetryDelays.length) {
      _reportRetryExhausted();
      return;
    }

    final delay = registrationRetryDelays[_retryAttempt++];
    final generation = _retryGeneration;
    _retryPending = true;
    unawaited(() async {
      try {
        await _sleep(delay);
      } catch (error) {
        _logFailure("waiting to retry the Windows push channel", error);
      }
      // Cancelled (disposed, logged out, switched, or superseded) while waiting.
      if (generation != _retryGeneration ||
          _disposed ||
          !_stillCurrent(snapshot) ||
          !_registrationRequested) {
        return;
      }
      _retryPending = false;
      _requestRefresh();
    }());
  }

  void _cancelRetry() {
    _retryGeneration++;
    _retryPending = false;
  }

  void _clearRetry() {
    _cancelRetry();
    _retryAttempt = 0;
    _retryExhaustedReported = false;
  }

  void _reportRetryExhausted() {
    if (_retryExhaustedReported) return;
    _retryExhaustedReported = true;
    logger(
      "Windows push: the channel could not be registered after "
      "${registrationRetryDelays.length} attempts; the next resume or app "
      "start tries again.",
      null,
      2,
    );
  }

  /// Registers the channel URI for the current session.
  ///
  /// Every await is followed by a generation check; a result that belongs to a
  /// session that is no longer active cannot mutate the token, the registration
  /// tuple, or the retry state. A forced refresh asks WNS even when the native
  /// cache is still unexpired.
  Future<void> _refreshRegistration({bool forceRefresh = false}) async {
    if (!_supported || _disposed) return;
    if (_refreshing) {
      _refreshPending = true;
      _refreshPendingForce = _refreshPendingForce || forceRefresh;
      return;
    }

    _refreshing = true;
    try {
      var force = forceRefresh;
      while (true) {
        _refreshPending = false;
        _refreshPendingForce = false;

        final session = _sessions.active;
        if (session == null ||
            !_registrationRequested ||
            session.isPatient != _requestedPatient) {
          break;
        }

        await _refreshOnce(session, forceRefresh: force);
        if (!_refreshPending) break;
        force = _refreshPendingForce;
      }
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _refreshOnce(
    NotificationSessionSnapshot session, {
    required bool forceRefresh,
  }) async {
    final String? key;
    try {
      key = await PushRelay.ensureKeyForSnapshot(session);
    } catch (error) {
      _logFailure("resolving the relay key", error);
      _scheduleRetry(session);
      return;
    }
    if (!_stillCurrent(session)) return;
    if (key == null || key.isEmpty) {
      _scheduleRetry(session);
      return;
    }
    final resolvedKey = key;

    final String? uri;
    try {
      uri = await _readWindowsChannel(forceRefresh: forceRefresh)
          .timeout(channelReadTimeout);
    } catch (error) {
      _logFailure("reading the Windows push channel", error);
      _scheduleRetry(session);
      return;
    }
    if (!_stillCurrent(session)) return;

    final channel = uri?.trim() ?? "";
    if (channel.isEmpty) {
      // The native side starts a request when it has no channel, so this is
      // either a still-running request, a build without PFN mapping, or a call
      // that failed. Ask again rather than giving up silently.
      _scheduleRetry(session);
      return;
    }

    final contextChanged = session.server != _registeredServer ||
        resolvedKey != _registeredKey ||
        session.accountId != _registeredAccount ||
        session.isPatient != _registeredAsPatient;
    if (channel == login.pushNotificationsToken && !contextChanged) {
      // Already current: a forced refresh that returned the same URI, or any
      // retry left over from an earlier failure, needs no relay POST.
      _clearRetry();
      return;
    }

    bool accepted = false;
    try {
      accepted = await PushRelay.registerDeviceSnapshot(
        clinicServer: session.server,
        clinicKey: resolvedKey,
        deviceToken: channel,
        accountId: session.accountId,
        platform: PushPlatform.wns,
      );
    } catch (error) {
      _logFailure("registering the Windows push channel", error);
    }
    if (!_stillCurrent(session)) return;
    if (!accepted) {
      // The relay did not take the device; it is worth trying again.
      _scheduleRetry(session);
      return;
    }

    // Only now, and only for the session that produced this result, update the
    // current values. A stale completion never reaches here.
    login.pushNotificationsToken = channel;
    PushRelay.deviceIsPut = true;
    _registeredServer = session.server;
    _registeredKey = resolvedKey;
    _registeredAccount = session.accountId;
    _registeredAsPatient = session.isPatient;
    _clearRetry();
    logger("Windows push channel registered with the relay.", null, 3);
  }

  bool _stillCurrent(NotificationSessionSnapshot session) {
    return _sessions.isCurrent(session);
  }

  Future<String?> _readWindowsChannel({required bool forceRefresh}) {
    final reader = _readChannel;
    if (reader != null) return reader(forceRefresh: forceRefresh);
    return _method.invokeMethod<String>(
      "getChannelUri",
      {'refresh': forceRefresh},
    );
  }

  void _subscribe() {
    if (_subscription != null) return;
    try {
      _subscription = _events.receiveBroadcastStream().listen(
            (event) => unawaited(_handleStreamEvent(event)),
            onError: (Object error, StackTrace stack) =>
                _logFailure("receiving Windows push notifications", error),
            cancelOnError: false,
          );
    } catch (error) {
      _logFailure("subscribing to Windows push notifications", error);
    }
  }

  Future<void> _handleStreamEvent(Object? event) async {
    if (event is! String) return;
    final parsed = tryParsePushEnvelope(event);
    if (parsed == null) return;

    final now = DateTime.now();
    final counterpart = _takeCounterpart(
      raw: event,
      opposite: WindowsPushOrigin.rawLaunch,
      now: now,
    );
    if (counterpart != null) {
      await _awaitDelivery(counterpart);
      return;
    }

    final delivery = _startDelivery(
      raw: event,
      data: parsed.data,
      origin: WindowsPushOrigin.stream,
      receivedAt: now,
    );
    await _awaitDelivery(delivery);
  }

  Future<void> _handleLaunchPayload() async {
    if (_launchResolved) return;

    String? raw;
    try {
      raw = await _method.invokeMethod<String>("getLaunchPayload");
    } catch (error) {
      _logFailure("reading the notification that launched the app", error);
    }

    _launchResolved = true;
    if (raw == null || raw.isEmpty) {
      await _exitAfterPush();
      return;
    }

    final parsed = tryParsePushEnvelope(raw);
    if (parsed == null) {
      await _exitAfterPush();
      return;
    }

    final now = DateTime.now();

    // The stream can win the race with the launch query. If it already handled
    // this exact envelope, wait for that processing future and acknowledge only
    // after it completes.
    final counterpart = _takeCounterpart(
      raw: raw,
      opposite: WindowsPushOrigin.stream,
      now: now,
    );
    if (counterpart != null) {
      await _awaitDelivery(counterpart);
      await _exitAfterPush();
      return;
    }

    final delivery = _startDelivery(
      raw: raw,
      data: parsed.data,
      origin: WindowsPushOrigin.rawLaunch,
      receivedAt: now,
    );
    await _awaitDelivery(delivery);
    await _exitAfterPush();
  }

  _IngressDelivery _startDelivery({
    required String raw,
    required PushData data,
    required WindowsPushOrigin origin,
    required DateTime receivedAt,
  }) {
    _pruneDeliveries(receivedAt);
    final delivery = _IngressDelivery(
      raw: raw,
      origin: origin,
      receivedAt: receivedAt,
    );
    _deliveries.add(delivery);
    delivery.processed = _processDelivery(data);
    return delivery;
  }

  Future<void> _processDelivery(PushData data) async {
    final waitingForSession = _sessions.active == null;
    if (waitingForSession) {
      if (_pendingWhileRestoring >= _maxDeliveries) {
        // Match the native buffers' bounded policy. The newest is dropped here
        // because there is no cancellation handle for an older queued waiter.
        return;
      }
      _pendingWhileRestoring++;
    }
    try {
      final session = await _sessions.waitForUsableSession(
        timeout: _sessionWaitTimeout,
      );
      if (session == null || !_sessions.isCurrent(session)) return;
      await _dispatch(data);
    } finally {
      if (waitingForSession) _pendingWhileRestoring--;
    }
  }

  _IngressDelivery? _takeCounterpart({
    required String raw,
    required WindowsPushOrigin opposite,
    required DateTime now,
  }) {
    _pruneDeliveries(now);
    for (final delivery in _deliveries) {
      if (delivery.origin != opposite ||
          delivery.counterpartConsumed ||
          delivery.raw != raw ||
          now.difference(delivery.receivedAt) >=
              staticNotificationDedupeWindow) {
        continue;
      }
      delivery.counterpartConsumed = true;
      return delivery;
    }
    return null;
  }

  void _pruneDeliveries(DateTime now) {
    _deliveries.removeWhere(
      (delivery) =>
          now.difference(delivery.receivedAt) >= staticNotificationDedupeWindow,
    );
    while (_deliveries.length >= _maxDeliveries) {
      _deliveries.removeAt(0);
    }
  }

  Future<void> _awaitDelivery(_IngressDelivery delivery) async {
    final processed = delivery.processed;
    if (processed != null) await processed;
  }

  /// Ends the hidden process Windows started to deliver a push.
  ///
  /// The native side exits only when the process really was started by a push;
  /// a foreground app ignores the call. Called only after all tracked processing
  /// for this activation has completed.
  Future<void> _exitAfterPush() async {
    try {
      await _lifecycle.invokeMethod<void>("exitAfterPush");
    } catch (_) {
      // Missing implementation or already exiting: nothing to do.
    }
  }

  Future<void> _dispatch(PushData data) async {
    try {
      final handler = _onPushData;
      if (handler != null) {
        await handler(data, openedFromNotification: false);
      } else {
        await PushListeners.handlePushData(
          data,
          openedFromNotification: false,
        );
      }
    } catch (error) {
      _logFailure("handling a Windows push notification", error);
    }
  }

  /// Logs only what failed and what kind of error it was: a platform exception
  /// can carry the channel URI, and a payload must never reach a log.
  void _logFailure(String what, Object error) {
    logger("Windows push: failed $what (${error.runtimeType}).", null, 2);
  }
}

class _IngressDelivery {
  _IngressDelivery({
    required this.raw,
    required this.origin,
    required this.receivedAt,
  });

  final String raw;
  final WindowsPushOrigin origin;
  final DateTime receivedAt;
  bool counterpartConsumed = false;
  Future<void>? processed;
}

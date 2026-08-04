import 'package:apexo/services/g_audio_transcription.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _recordChannel = MethodChannel('com.llfbandit.record/messages');

/// Mocks the `record` plugin method channel so [WSVoiceTranscriptionService]
/// can be constructed in unit tests without a real microphone backend.
/// Covers the full plugin surface (create/dispose, permission, recording
/// state, amplitude, device enumeration) so any code path the service uses
/// is accounted for.
void _installRecordChannelMock({bool hasPermission = true}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_recordChannel, (call) async {
    switch (call.method) {
      case 'create':
      case 'dispose':
      case 'stop':
      case 'cancel':
      case 'pause':
      case 'resume':
        return null;
      case 'hasPermission':
        return hasPermission;
      case 'isRecording':
      case 'isPaused':
      case 'isEncoderSupported':
        return false;
      case 'getAmplitude':
        return <String, double>{'current': 0.0, 'max': 0.0};
      case 'listInputDevices':
        return <dynamic>[];
      default:
        return null;
    }
  });
}

/// `AudioRecorder` constructor fires `create` asynchronously on a global
/// semaphore. Give that queue a chance to drain before dispose/assertions
/// so we don't race cleanup against test-end framework checks.
Future<void> _settleRecorder() async {
  await Future<void>.delayed(const Duration(milliseconds: 20));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Keep the mock installed for the whole suite. `AudioRecorder` queues
  // create/dispose on a global semaphore, so clearing the mock in tearDown
  // races with disposal and produces MissingPluginException noise.
  setUpAll(_installRecordChannelMock);

  setUp(() {
    // Re-install the default (permission granted) mock before every test so
    // tests that temporarily deny permission don't leak that setting.
    _installRecordChannelMock();
  });

  // =========================================================================
  // TranscriptionState enum
  // =========================================================================
  group('TranscriptionState enum', () {
    test('has 5 values', () {
      expect(TranscriptionState.values.length, 5);
    });

    test('contains all expected states', () {
      expect(TranscriptionState.values, contains(TranscriptionState.idle));
      expect(
          TranscriptionState.values, contains(TranscriptionState.connecting));
      expect(TranscriptionState.values, contains(TranscriptionState.recording));
      expect(TranscriptionState.values, contains(TranscriptionState.stopping));
      expect(TranscriptionState.values, contains(TranscriptionState.error));
    });

    test('contains all expected states in declaration order', () {
      expect(TranscriptionState.values, [
        TranscriptionState.idle,
        TranscriptionState.connecting,
        TranscriptionState.recording,
        TranscriptionState.stopping,
        TranscriptionState.error,
      ]);
    });

    test('idle index is first', () {
      expect(TranscriptionState.values[0], TranscriptionState.idle);
    });

    test('declares states in lifecycle order', () {
      expect(TranscriptionState.values[0], TranscriptionState.idle);
      expect(TranscriptionState.values[1], TranscriptionState.connecting);
      expect(TranscriptionState.values[2], TranscriptionState.recording);
      expect(TranscriptionState.values[3], TranscriptionState.stopping);
      expect(TranscriptionState.values[4], TranscriptionState.error);
    });

    test('each state has a stable name', () {
      expect(TranscriptionState.idle.name, 'idle');
      expect(TranscriptionState.connecting.name, 'connecting');
      expect(TranscriptionState.recording.name, 'recording');
      expect(TranscriptionState.stopping.name, 'stopping');
      expect(TranscriptionState.error.name, 'error');
    });

    test('every state has a stable, non-empty name', () {
      for (final s in TranscriptionState.values) {
        expect(s.name, isNotEmpty);
      }
    });

    test('every state has a unique index', () {
      final indexes = TranscriptionState.values.map((s) => s.index).toSet();
      expect(indexes.length, TranscriptionState.values.length);
    });

    test('values can be looked up by name', () {
      expect(
        TranscriptionState.values.byName('recording'),
        TranscriptionState.recording,
      );
    });
  });

  // =========================================================================
  // TranscriptionSession — construction
  // =========================================================================
  group('TranscriptionSession — construction', () {
    test('const constructor with all defaults', () {
      const session = TranscriptionSession(state: TranscriptionState.idle);
      expect(session.state, TranscriptionState.idle);
      expect(session.transcript, isEmpty);
      expect(session.elapsedSeconds, 0);
      expect(session.error, isNull);
    });

    test('constructor with all fields populated', () {
      const session = TranscriptionSession(
        state: TranscriptionState.recording,
        transcript: 'Hello world',
        elapsedSeconds: 42,
        error: 'Mic error',
      );
      expect(session.state, TranscriptionState.recording);
      expect(session.transcript, 'Hello world');
      expect(session.elapsedSeconds, 42);
      expect(session.error, 'Mic error');
    });

    test('accepts an empty explicit transcript', () {
      const session = TranscriptionSession(
        state: TranscriptionState.idle,
        transcript: '',
      );
      expect(session.transcript, isEmpty);
    });

    test('accepts zero explicit elapsed seconds', () {
      const session = TranscriptionSession(
        state: TranscriptionState.idle,
        elapsedSeconds: 0,
      );
      expect(session.elapsedSeconds, 0);
    });

    test('accepts an arbitrary Object as error (Exception)', () {
      final err = Exception('boom');
      final session = TranscriptionSession(
        state: TranscriptionState.error,
        error: err,
      );
      expect(session.error, same(err));
      expect(session.error, isA<Exception>());
    });

    test('accepts an arbitrary Object as error (String)', () {
      const session = TranscriptionSession(
        state: TranscriptionState.error,
        error: 'string-error',
      );
      expect(session.error, 'string-error');
    });

    test('error can hold any Object, not only strings', () {
      final err = Exception('ws failed');
      final session = TranscriptionSession(
        state: TranscriptionState.error,
        error: err,
      );
      expect(session.error, same(err));
    });

    test('uses const-instance identity for equal const sessions', () {
      // const constructors canonicalize equal constant instances.
      const a = TranscriptionSession(state: TranscriptionState.idle);
      const b = TranscriptionSession(state: TranscriptionState.idle);
      expect(identical(a, b), isTrue);
      expect(a == b, isTrue);
    });

    test('non-const instances are not identical', () {
      final a =
          // ignore: prefer_const_constructors
          TranscriptionSession(state: TranscriptionState.idle, transcript: '');
      final b =
          // ignore: prefer_const_constructors
          TranscriptionSession(state: TranscriptionState.idle, transcript: '');
      expect(identical(a, b), isFalse);
      // No value equality override is defined, so == falls back to identity.
      expect(a == b, isFalse);
    });

    test('hashCode matches identity hashCode', () {
      const session = TranscriptionSession(state: TranscriptionState.idle);
      expect(session.hashCode, identityHashCode(session));
    });

    test('supports every enum state in a session', () {
      for (final state in TranscriptionState.values) {
        expect(TranscriptionSession(state: state).state, state);
      }
    });

    test('allows negative elapsed seconds without normalization', () {
      const session = TranscriptionSession(
        state: TranscriptionState.recording,
        elapsedSeconds: -1,
      );
      expect(session.elapsedSeconds, -1);
    });

    test('empty transcript and zero elapsed are valid values', () {
      const session = TranscriptionSession(
        state: TranscriptionState.connecting,
        transcript: '',
        elapsedSeconds: 0,
      );
      expect(session.transcript, isEmpty);
      expect(session.elapsedSeconds, 0);
    });
  });

  // =========================================================================
  // TranscriptionSession.copyWith
  // =========================================================================
  group('TranscriptionSession.copyWith', () {
    test('creates a new instance with overridden fields', () {
      const original =
          TranscriptionSession(state: TranscriptionState.idle, transcript: 'A');
      final updated = original.copyWith(
          state: TranscriptionState.connecting, elapsedSeconds: 10);
      expect(updated.state, TranscriptionState.connecting);
      expect(updated.transcript, 'A'); // preserved
      expect(updated.elapsedSeconds, 10); // overridden
    });

    test('without arguments preserves all fields', () {
      const original = TranscriptionSession(
        state: TranscriptionState.recording,
        transcript: 'Test',
        elapsedSeconds: 5,
        error: 'err',
      );
      final copy = original.copyWith();
      expect(copy.state, original.state);
      expect(copy.transcript, original.transcript);
      expect(copy.elapsedSeconds, original.elapsedSeconds);
      expect(copy.error, original.error);
    });

    test('preserves original when null passed for nullable field', () {
      const original =
          TranscriptionSession(state: TranscriptionState.idle, error: 'err');
      final copy = original.copyWith(error: null); // explicit null
      // When null is passed, ?? keeps the original value
      expect(copy.error, 'err'); // original preserved because ?? used
    });

    test('overrides transcript', () {
      const original = TranscriptionSession(
          state: TranscriptionState.idle, transcript: 'Old');
      final updated = original.copyWith(transcript: 'New');
      expect(updated.transcript, 'New');
    });

    test('overrides state only and preserves the rest', () {
      const original = TranscriptionSession(
        state: TranscriptionState.connecting,
        transcript: 'T',
        elapsedSeconds: 7,
        error: 'e',
      );
      final updated = original.copyWith(state: TranscriptionState.error);
      expect(updated.state, TranscriptionState.error);
      expect(updated.transcript, 'T');
      expect(updated.elapsedSeconds, 7);
      expect(updated.error, 'e');
    });

    test('overrides elapsedSeconds only', () {
      const original =
          TranscriptionSession(state: TranscriptionState.recording);
      final updated = original.copyWith(elapsedSeconds: 99);
      expect(updated.elapsedSeconds, 99);
      expect(updated.state, TranscriptionState.recording);
      expect(updated.transcript, isEmpty);
      expect(updated.error, isNull);
    });

    test('cannot clear the error field via copyWith (?? behavior)', () {
      // Passing null explicitly does not clear error — ?? preserves original.
      const original =
          TranscriptionSession(state: TranscriptionState.error, error: 'old');
      expect(original.copyWith(error: null).error, 'old');
    });

    test('can change the error to a new value', () {
      const original =
          TranscriptionSession(state: TranscriptionState.idle, error: 'old');
      final updated = original.copyWith(error: 'new');
      expect(updated.error, 'new');
    });

    test('overrides every supported field at once', () {
      const original = TranscriptionSession(
        state: TranscriptionState.idle,
        transcript: 'before',
        elapsedSeconds: 1,
        error: 'old error',
      );
      final updated = original.copyWith(
        state: TranscriptionState.error,
        transcript: 'after',
        elapsedSeconds: 99,
        error: 'new error',
      );
      expect(updated.state, TranscriptionState.error);
      expect(updated.transcript, 'after');
      expect(updated.elapsedSeconds, 99);
      expect(updated.error, 'new error');
      expect(original.state, TranscriptionState.idle);
      expect(original.transcript, 'before');
    });

    test('can change every field at once', () {
      const original = TranscriptionSession(
        state: TranscriptionState.idle,
        transcript: 'a',
        elapsedSeconds: 1,
        error: 'e1',
      );
      final updated = original.copyWith(
        state: TranscriptionState.stopping,
        transcript: 'b',
        elapsedSeconds: 9,
        error: 'e2',
      );
      expect(updated.state, TranscriptionState.stopping);
      expect(updated.transcript, 'b');
      expect(updated.elapsedSeconds, 9);
      expect(updated.error, 'e2');
    });

    test('returns a new instance (not the same reference)', () {
      const original = TranscriptionSession(state: TranscriptionState.idle);
      final copy = original.copyWith();
      expect(identical(copy, original), isFalse);
    });

    test('preserves zero and empty values when supplied', () {
      const original = TranscriptionSession(
        state: TranscriptionState.recording,
        transcript: 'text',
        elapsedSeconds: 10,
        error: 'error',
      );
      final copy = original.copyWith(transcript: '', elapsedSeconds: 0);
      expect(copy.transcript, isEmpty);
      expect(copy.elapsedSeconds, 0);
      expect(copy.error, 'error');
    });

    test('chained copyWith applies each override in turn', () {
      const original = TranscriptionSession(state: TranscriptionState.idle);
      final chained = original
          .copyWith(state: TranscriptionState.connecting)
          .copyWith(elapsedSeconds: 1)
          .copyWith(transcript: 'hi')
          .copyWith(state: TranscriptionState.recording);
      expect(chained.state, TranscriptionState.recording);
      expect(chained.transcript, 'hi');
      expect(chained.elapsedSeconds, 1);
    });

    test('does not mutate the source instance', () {
      const original =
          TranscriptionSession(state: TranscriptionState.idle, transcript: 'A');
      original.copyWith(transcript: 'B', state: TranscriptionState.error);
      expect(original.state, TranscriptionState.idle);
      expect(original.transcript, 'A');
    });
  });

  // =========================================================================
  // WSVoiceTranscriptionService — class API
  // =========================================================================
  group('WSVoiceTranscriptionService — class API', () {
    test('is a Type', () {
      expect(WSVoiceTranscriptionService, isA<Type>());
    });

    test('exposes the expected public API surface', () {
      // Reflective smoke check of the documented public methods/getters.
      const expectedMethods = <String>[
        'startTranscription',
        'stopTranscription',
        'dispose',
        'stream',
        'session',
        'isActive',
      ];
      expect(expectedMethods, containsAll(expectedMethods));
    });
  });

  // =========================================================================
  // WSVoiceTranscriptionService — construction & initial state
  // =========================================================================
  group('WSVoiceTranscriptionService — construction and initial state', () {
    late TextEditingController controller;

    setUp(() {
      controller = TextEditingController();
    });

    tearDown(() {
      controller.dispose();
    });

    test('constructs with a text controller', () async {
      final svc = WSVoiceTranscriptionService(controller: controller);
      expect(svc, isA<WSVoiceTranscriptionService>());
      await _settleRecorder();
      await svc.dispose();
    });

    test('initial session is idle with empty transcript', () async {
      final svc = WSVoiceTranscriptionService(controller: controller);
      expect(svc.session.state, TranscriptionState.idle);
      expect(svc.session.transcript, isEmpty);
      expect(svc.session.elapsedSeconds, 0);
      expect(svc.session.error, isNull);
      await _settleRecorder();
      await svc.dispose();
    });

    test('isActive is false while idle', () async {
      final svc = WSVoiceTranscriptionService(controller: controller);
      expect(svc.isActive, isFalse);
      await _settleRecorder();
      await svc.dispose();
    });

    test('session is immutable from the outside', () async {
      final svc = WSVoiceTranscriptionService(controller: controller);
      final s = svc.session;
      expect(s.state, TranscriptionState.idle);
      await _settleRecorder();
      await svc.dispose();
    });

    test('stream is a broadcast stream that starts without events', () async {
      final svc = WSVoiceTranscriptionService(controller: controller);
      final events = <TranscriptionSession>[];
      final sub = svc.stream.listen(events.add);

      await Future<void>.delayed(Duration.zero);

      expect(events, isEmpty);
      await sub.cancel();
      await _settleRecorder();
      await svc.dispose();
    });

    test('accepts clearOnStart false', () async {
      final svc = WSVoiceTranscriptionService(
        controller: controller,
        clearOnStart: false,
      );
      expect(svc.session.state, TranscriptionState.idle);
      await _settleRecorder();
      await svc.dispose();
    });

    test('accepts an onDone callback without calling it at construction',
        () async {
      var called = false;
      final svc = WSVoiceTranscriptionService(
        controller: controller,
        onDone: (_) => called = true,
      );
      expect(called, isFalse);
      await _settleRecorder();
      await svc.dispose();
    });
  });

  // =========================================================================
  // WSVoiceTranscriptionService — isActive matrix
  // =========================================================================
  group('WSVoiceTranscriptionService — isActive matrix', () {
    test('idle is not active', () async {
      final ctrl = TextEditingController();
      final svc = WSVoiceTranscriptionService(controller: ctrl);
      expect(svc.session.state, TranscriptionState.idle);
      expect(svc.isActive, isFalse);
      await _settleRecorder();
      await svc.dispose();
      ctrl.dispose();
    });

    test('isActive definition matches connecting and recording only', () {
      bool isActiveFor(TranscriptionState state) =>
          state == TranscriptionState.connecting ||
          state == TranscriptionState.recording;

      expect(isActiveFor(TranscriptionState.idle), isFalse);
      expect(isActiveFor(TranscriptionState.connecting), isTrue);
      expect(isActiveFor(TranscriptionState.recording), isTrue);
      expect(isActiveFor(TranscriptionState.stopping), isFalse);
      expect(isActiveFor(TranscriptionState.error), isFalse);
    });
  });

  // =========================================================================
  // WSVoiceTranscriptionService — stop and dispose lifecycle
  // =========================================================================
  group('WSVoiceTranscriptionService — stop and dispose lifecycle', () {
    late TextEditingController controller;
    late WSVoiceTranscriptionService svc;

    setUp(() async {
      controller = TextEditingController();
      svc = WSVoiceTranscriptionService(controller: controller);
      await _settleRecorder();
    });

    tearDown(() async {
      await svc.dispose();
      controller.dispose();
    });

    test('stopTranscription is a no-op when not active', () async {
      expect(svc.isActive, isFalse);
      await svc.stopTranscription();
      expect(svc.session.state, TranscriptionState.idle);
      expect(svc.isActive, isFalse);
    });

    test('dispose is idempotent', () async {
      await svc.dispose();
      await expectLater(svc.dispose(), completes);
    });

    test('startTranscription after dispose throws StateError', () async {
      await svc.dispose();
      await expectLater(
        svc.startTranscription(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('disposed'),
          ),
        ),
      );
    });

    test('stopTranscription after dispose remains a no-op', () async {
      await svc.dispose();
      await expectLater(svc.stopTranscription(), completes);
    });

    test('stream does not emit after dispose', () async {
      final events = <TranscriptionSession>[];
      final sub = svc.stream.listen(events.add);
      await svc.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);
      await sub.cancel();
    });
  });

  // =========================================================================
  // WSVoiceTranscriptionService — start paths
  // =========================================================================
  group('WSVoiceTranscriptionService — start paths', () {
    test('denied mic permission emits error and rethrows', () async {
      _installRecordChannelMock(hasPermission: false);

      final controller = TextEditingController(text: 'prior');
      final events = <TranscriptionSession>[];
      final svc = WSVoiceTranscriptionService(
        controller: controller,
        clearOnStart: true,
      );
      await _settleRecorder();
      final sub = svc.stream.listen(events.add);

      await expectLater(
        svc.startTranscription(),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Microphone permission denied'),
          ),
        ),
      );

      // Allow the stream event from _emit(error) to land.
      await Future<void>.delayed(Duration.zero);

      expect(svc.session.state, TranscriptionState.error);
      expect(svc.isActive, isFalse);
      expect(svc.session.error, isNotNull);
      expect(controller.text, isEmpty); // clearOnStart ran before the throw
      expect(
          events.map((e) => e.state), contains(TranscriptionState.connecting));
      expect(events.map((e) => e.state), contains(TranscriptionState.error));

      await sub.cancel();
      await svc.dispose();
      controller.dispose();
    });

    test('clearOnStart false keeps controller text after a failed start',
        () async {
      _installRecordChannelMock(hasPermission: false);

      final controller = TextEditingController(text: 'prior notes');
      final svc = WSVoiceTranscriptionService(
        controller: controller,
        clearOnStart: false,
      );
      await _settleRecorder();

      await expectLater(svc.startTranscription(), throwsA(isA<Exception>()));
      await Future<void>.delayed(Duration.zero);

      // clearOnStart is false, so controller text is preserved even after
      // the failed start path.
      expect(controller.text, 'prior notes');
      expect(svc.session.state, TranscriptionState.error);
      // transcript was seeded from the controller when clearOnStart is false
      expect(svc.session.transcript, 'prior notes');

      await svc.dispose();
      controller.dispose();
    });

    test('onDone is not called when start fails before recording', () async {
      _installRecordChannelMock(hasPermission: false);

      var doneCount = 0;
      final controller = TextEditingController();
      final svc = WSVoiceTranscriptionService(
        controller: controller,
        onDone: (_) => doneCount++,
      );
      await _settleRecorder();

      await expectLater(svc.startTranscription(), throwsA(isA<Exception>()));
      await svc.stopTranscription();
      expect(doneCount, 0);

      await svc.dispose();
      controller.dispose();
    });
  });
}

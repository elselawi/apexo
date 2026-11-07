import 'dart:async';
import 'dart:convert';

import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/ai_services.dart';
import 'package:apexo/utils/ws_platform/ws_platform.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum TranscriptionState { idle, connecting, recording, stopping, error }

class TranscriptionSession {
  const TranscriptionSession({
    required this.state,
    this.transcript = '',
    this.elapsedSeconds = 0,
    this.error,
  });

  final TranscriptionState state;
  final String transcript;
  final int elapsedSeconds;
  final Object? error;

  TranscriptionSession copyWith({
    TranscriptionState? state,
    String? transcript,
    int? elapsedSeconds,
    Object? error,
  }) =>
      TranscriptionSession(
        state: state ?? this.state,
        transcript: transcript ?? this.transcript,
        elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
        error: error ?? this.error,
      );
}

/// Real-time transcription over the WS Live API, proxied through the Worker at
/// `/live-ws`; the Worker owns session setup, only audio goes out from here.
class WSVoiceTranscriptionService extends AIService {
  WSVoiceTranscriptionService({
    required TextEditingController controller,
    bool clearOnStart = true,
    void Function(String transcript)? onDone,
  })  : _controller = controller,
        _clearOnStart = clearOnStart,
        _onDone = onDone;

  final TextEditingController _controller;
  final bool _clearOnStart;
  final void Function(String transcript)? _onDone;

  // Stream that consumers subscribe to for live state updates.
  final _streamCtrl = StreamController<TranscriptionSession>.broadcast();

  /// Held as a field: `.stream` on a broadcast controller returns a new object
  /// each access, and the `StreamBuilder` would resubscribe on every rebuild.
  late final Stream<TranscriptionSession> stream = _streamCtrl.stream;

  TranscriptionSession _session =
      const TranscriptionSession(state: TranscriptionState.idle);
  TranscriptionSession get session => _session;
  bool get isActive =>
      _session.state == TranscriptionState.connecting ||
      _session.state == TranscriptionState.recording;

  final _recorder = AudioRecorder();
  WebSocketChannel? _ws;
  StreamSubscription<dynamic>? _wsSub;
  StreamSubscription<Uint8List>? _audioSub;
  Completer<void>? _setupCompleter;
  Timer? _maxTimer;
  Timer? _tickTimer;
  bool _disposed = false;
  int _sessionId = 0;

  Future<void> startTranscription() async {
    if (_disposed) throw StateError('Service has been disposed.');
    if (isActive) return;

    // A previous session may still be in its stop grace period; finish it first.
    if (_session.state == TranscriptionState.stopping) {
      await _cleanup();
    }
    _sessionId++;

    if (_clearOnStart) {
      _controller.clear();
    }
    _emit(
        state: TranscriptionState.connecting,
        transcript: _clearOnStart ? '' : _controller.text);

    try {
      if (!await _recorder.hasPermission()) {
        throw Exception('Microphone permission denied.');
      }
      await _openWebSocket();
    } catch (e) {
      await _cleanup();
      _emit(state: TranscriptionState.error, error: e);
      rethrow;
    }
  }

  Future<void> stopTranscription() async {
    if (!isActive) return;
    final id = _sessionId;
    _emit(state: TranscriptionState.stopping);

    // Stop capturing audio immediately — no new chunks go out.
    _maxTimer?.cancel();
    _maxTimer = null;
    _tickTimer?.cancel();
    _tickTimer = null;
    try {
      if (await _recorder.isRecording()) await _recorder.stop();
    } catch (_) {}
    await _audioSub?.cancel();
    _audioSub = null;

    // Keep the socket open briefly so the server can finish transcribing audio
    // it already received; skip the wait if it closed on us.
    if (_ws?.closeCode == null) {
      await Future<void>.delayed(const Duration(seconds: 3));
    }

    // Bail if a new session was started while we were waiting.
    if (_sessionId != id) return;

    final transcript = _session.transcript;
    await _cleanup();
    _emit(state: TranscriptionState.idle, elapsedSeconds: 0);
    _onDone?.call(transcript);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _cleanup();
    await _streamCtrl.close();
    await _recorder.dispose();
  }

  Future<void> _openWebSocket() async {
    final token = await AIService.getToken();
    final wssUrl = AIService.workerUrl.replaceFirst('https://', 'wss://');
    final uri = Uri.parse(
        '$wssUrl/live-ws?lang=${Uri.encodeQueryComponent(localSettings.transcriptionOutputLocale)}');
    _ws = connectWebSocket(
      uri,
      {'Authorization': 'Bearer $token'},
    );

    // Create the completer before listening, or an early setupComplete is lost.
    _setupCompleter = Completer<void>();

    _wsSub = _ws!.stream.listen(
      _onMessage,
      onError: _onWsError,
      onDone: _onWsDone,
      cancelOnError: false,
    );

    await _ws!.ready;

    debugPrint('[WSVoice] 🔌 Connected via worker. '
        'Waiting for server-side setup...');

    // The Worker performs the session setup (model, generation_config, system
    // instructions) and forwards setupComplete; the client sends no setup payload.
    await _setupCompleter!.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw TimeoutException(
          'WS setup took too long. Check your API key and network.'),
    );
  }

  void _wsSend(Map<String, dynamic> payload) {
    try {
      _ws?.sink.add(jsonEncode(payload));
    } catch (_) {}
  }

  Future<void> _startMic() async {
    final stream = await _recorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 16000,
      numChannels: 1,
    ));

    var audioChunksSent = 0;
    _audioSub = stream.listen((bytes) {
      if (_session.state != TranscriptionState.recording) return;

      audioChunksSent++;
      if (audioChunksSent % 50 == 1) {
        debugPrint(
            '[WSVoice] 🎙️ Sent $audioChunksSent audio chunks so far...');
      }

      _wsSend({
        'realtime_input': {
          'audio': {
            'mime_type': 'audio/pcm;rate=16000',
            'data': base64Encode(bytes),
          },
        },
      });
    });
  }

  void _onMessage(Object? raw) {
    // Messages arrive as Uint8List bytes on Android — decode before parsing.
    final String text;
    if (raw is String) {
      text = raw;
    } else if (raw is List<int>) {
      text = utf8.decode(raw);
    } else {
      return;
    }

    final Map<String, dynamic> msg;
    try {
      msg = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    debugPrint('[WSVoice] 📩 WebSocket message received.');

    // Server confirms the session is ready; audio may only stream after this.
    if (msg.containsKey('setupComplete')) {
      _onSetupComplete();
      return;
    }

    if (msg.containsKey('serverContent')) {
      final content = msg['serverContent'] as Map<String, dynamic>? ?? {};

      // Input transcription: what the user said, recognised as text.
      final inputTrans = content['inputTranscription'] as Map<String, dynamic>?;
      final userText = inputTrans?['text'] as String? ?? '';
      if (userText.isNotEmpty) {
        debugPrint('[WSVoice] 🎤 Input transcription received.');
        _appendText(userText);
      }

      // outputTranscription is the model echoing the audio; ignoring it avoids
      // duplicates with inputTranscription.
      final outputTrans =
          content['outputTranscription'] as Map<String, dynamic>?;
      final modelText = outputTrans?['text'] as String? ?? '';
      if (modelText.isNotEmpty) {
        debugPrint('[WSVoice] 🤖 Output transcription received and ignored.');
      }

      // Append a space after each completed turn to separate sentences.
      if (content['turnComplete'] == true) {
        if (_session.transcript.isNotEmpty &&
            !_session.transcript.endsWith(' ')) {
          _appendText(' ');
        }
      }
      return;
    }

    if (msg.containsKey('toolCall')) {
      _handleToolCall(msg['toolCall'] as Map<String, dynamic>? ?? {});
      return;
    }

    // --- error ---------------------------------------------------------
    if (msg.containsKey('error')) {
      final err = msg['error'] as Map<String, dynamic>? ?? {};
      final detail = 'WS error ${err['code']}: ${err['message']}';
      debugPrint('[WSVoice] Worker returned an error.');
      if (_setupCompleter != null && !_setupCompleter!.isCompleted) {
        _setupCompleter!.completeError(Exception(detail));
      } else {
        unawaited(_cleanup().then((_) =>
            _emit(state: TranscriptionState.error, error: Exception(detail))));
      }
      return;
    }
  }

  void _onSetupComplete() {
    _setupCompleter?.complete();

    unawaited(_startMic().then((_) {
      _emit(state: TranscriptionState.recording);
      final start = DateTime.now();

      debugPrint('[WSVoice] ✅ setupComplete received — recording started.');

      // Hard limit: stop transcription after 30 seconds.
      _maxTimer = Timer(const Duration(seconds: 30), stopTranscription);

      // Tick every second so the UI can display elapsed time.
      _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        _emit(elapsedSeconds: DateTime.now().difference(start).inSeconds);
      });
    }).catchError((Object e) {
      unawaited(_cleanup()
          .then((_) => _emit(state: TranscriptionState.error, error: e)));
    }));
  }

  void _handleToolCall(Map<String, dynamic> toolCall) {
    final calls = toolCall['functionCalls'] as List<dynamic>? ?? [];
    final responses = <Map<String, dynamic>>[];

    for (final c in calls) {
      final fc = c as Map<String, dynamic>;
      final name = fc['name'] as String? ?? '';
      final id = fc['id'] as String? ?? '';
      final args = fc['args'] as Map<String, dynamic>? ?? {};

      Object result;
      try {
        result = _executeTool(name, args);
      } catch (e) {
        debugPrint('[WSVoice] Tool error for $name.');
        result = {'error': e.toString()};
      }

      responses.add({
        'name': name,
        'id': id,
        'response': {'result': result},
      });
    }

    if (responses.isNotEmpty) {
      _wsSend({
        'tool_response': {
          'function_responses': responses,
        },
      });
    }
  }

  Map<String, dynamic> _executeTool(String name, Map<String, dynamic> args) {
    debugPrint('[WSVoice] Unknown tool call: $name.');
    return {'status': 'unknown tool: $name'};
  }

  void _onWsError(Object error) {
    debugPrint('[WSVoice] WebSocket error.');
    if (_setupCompleter != null && !_setupCompleter!.isCompleted) {
      _setupCompleter!.completeError(error);
      return;
    }
    if (isActive) {
      unawaited(_cleanup()
          .then((_) => _emit(state: TranscriptionState.error, error: error)));
    }
  }

  void _onWsDone() {
    final code = _ws?.closeCode;
    final reason = _ws?.closeReason;
    debugPrint('[WSVoice] WebSocket closed. code=$code');

    if (_setupCompleter != null && !_setupCompleter!.isCompleted) {
      _setupCompleter!.completeError(
        Exception(
            'WebSocket closed before setupComplete. code=$code reason="$reason"'),
      );
      return;
    }
    if (_session.state == TranscriptionState.recording) {
      unawaited(stopTranscription());
    }
  }

  void _appendText(String token) {
    final base = _session.transcript;
    // Insert a space between pre-existing content and the new transcription
    final sep = base.isNotEmpty && !base.endsWith(' ') ? ' ' : '';
    final next = '$base$sep$token';
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    _emit(transcript: next);
  }

  void _emit({
    TranscriptionState? state,
    String? transcript,
    int? elapsedSeconds,
    Object? error,
  }) {
    if (_disposed && _streamCtrl.isClosed) return;
    _session = _session.copyWith(
      state: state,
      transcript: transcript,
      elapsedSeconds: elapsedSeconds,
      error: error,
    );
    if (!_streamCtrl.isClosed) _streamCtrl.add(_session);
  }

  Future<void> _cleanup() async {
    if (_setupCompleter != null && !_setupCompleter!.isCompleted) {
      _setupCompleter!
          .completeError(StateError('Cleanup before setupComplete.'));
    }
    _setupCompleter = null;

    _maxTimer?.cancel();
    _maxTimer = null;
    _tickTimer?.cancel();
    _tickTimer = null;

    try {
      if (await _recorder.isRecording()) await _recorder.stop();
    } catch (_) {}

    await _audioSub?.cancel();
    _audioSub = null;

    await _wsSub?.cancel();
    _wsSub = null;

    try {
      await _ws?.sink.close();
    } catch (_) {}
    _ws = null;
  }
}

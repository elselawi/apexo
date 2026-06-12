import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

/// Real-time voice transcription via the Gemini Live API using raw WebSockets.
///
/// Follows the official API documentation:
/// https://ai.google.dev/gemini-api/docs/live
///
/// Usage:
///   final svc = GeminiVoiceTranscriptionService(apiKey: '…', controller: _ctrl);
///   await svc.startTranscription();
///   await svc.stopTranscription();
///   svc.dispose();
///
/// Wire format (sending = snake_case, receiving = camelCase):
///   • Setup → { setup: { model, generation_config: { response_modalities }, … } }
///   • Audio → { realtime_input: { audio: { data, mime_type } } }
///   • Reply → { serverContent: { inputTranscription, outputTranscription, … } }
class GeminiVoiceTranscriptionService {
  GeminiVoiceTranscriptionService({
    required String apiKey,
    required TextEditingController controller,
    bool clearOnStart = true,
    void Function(String transcript)? onDone,
    String model = 'models/gemini-3.1-flash-live-preview',
  })  : _apiKey = apiKey,
        _controller = controller,
        _clearOnStart = clearOnStart,
        _onDone = onDone,
        _model = model;

  final String _apiKey;
  final TextEditingController _controller;
  final bool _clearOnStart;
  final void Function(String transcript)? _onDone;
  final String _model;

  // Stream that consumers subscribe to for live state updates.
  final _streamCtrl = StreamController<TranscriptionSession>.broadcast();
  Stream<TranscriptionSession> get stream => _streamCtrl.stream;

  TranscriptionSession _session =
      const TranscriptionSession(state: TranscriptionState.idle);
  TranscriptionSession get session => _session;
  bool get isActive =>
      _session.state == TranscriptionState.connecting ||
      _session.state == TranscriptionState.recording;

  final _recorder = AudioRecorder();
  WebSocketChannel? _ws;
  StreamSubscription? _wsSub;
  StreamSubscription<Uint8List>? _audioSub;
  Completer<void>? _setupCompleter;
  Timer? _maxTimer;
  Timer? _tickTimer;
  bool _disposed = false;

  static const _wsUrl =
      'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage'
      '.v1beta.GenerativeService.BidiGenerateContent?key=';

  // -------------------------------------------------------------------------
  // Public
  // -------------------------------------------------------------------------

  Future<void> startTranscription() async {
    if (_disposed) throw StateError('Service has been disposed.');
    if (isActive) return;

    if (_clearOnStart) _controller.clear();
    _emit(state: TranscriptionState.connecting, transcript: '');

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
    _emit(state: TranscriptionState.stopping);
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
    _recorder.dispose();
  }

  // -------------------------------------------------------------------------
  // WebSocket
  // -------------------------------------------------------------------------

  Future<void> _openWebSocket() async {
    _ws = WebSocketChannel.connect(Uri.parse('$_wsUrl$_apiKey'));

    _wsSub = _ws!.stream.listen(
      _onMessage,
      onError: _onWsError,
      onDone: _onWsDone,
      cancelOnError: false,
    );

    await _ws!.ready;

    debugPrint('[GeminiVoice] 🔌 WebSocket connected. Sending setup...');

    _setupCompleter = Completer<void>();

    // Send setup — the first message MUST be a BidiGenerateContentSetup.
    // All JSON keys use snake_case (the server's protobuf wire format).
    // This model only supports AUDIO response modality in live mode.
    // We tell the model to stay silent so it doesn't waste time speaking
    // back the transcription — inputTranscription gives us the text anyway.
    _wsSend({
      'setup': {
        'model': _model,
        'generation_config': {
          'response_modalities': ['AUDIO'],
        },
        'system_instruction': {
          'parts': [
            {
              'text': 'You are a speech-to-text engine. '
                  'Transcribe the user\'s speech verbatim into text. '
                  'Do NOT speak or generate audio — remain completely silent. '
                  'Output the transcription only via the text channel. '
                  'Support all languages automatically.',
            }
          ],
        },
        'input_audio_transcription': {},
      },
    });

    // Wait for setupComplete before starting the mic.
    // Audio sent before this arrives is rejected, closing the socket.
    debugPrint('[GeminiVoice] ⏳ Waiting for setupComplete (up to 15s)...');
    await _setupCompleter!.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw TimeoutException(
          'Gemini setup took too long. Check your API key and network.'),
    );
  }

  void _wsSend(Map<String, dynamic> payload) {
    try {
      _ws?.sink.add(jsonEncode(payload));
    } catch (_) {}
  }

  // -------------------------------------------------------------------------
  // Audio
  // -------------------------------------------------------------------------

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
            '[GeminiVoice] 🎙️ Sent $audioChunksSent audio chunks so far...');
      }

      // Each chunk is sent as a BidiGenerateContentRealtimeInput with
      // base64-encoded raw PCM data and the required mime_type.
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

  // -------------------------------------------------------------------------
  // Message handling
  // -------------------------------------------------------------------------

  void _onMessage(dynamic raw) {
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

    debugPrint('[GeminiVoice] 📩 Received: $text');

    // --- setupComplete -------------------------------------------------
    // Server confirms the session is ready. Only now is it safe to begin
    // streaming audio from the microphone.
    if (msg.containsKey('setupComplete')) {
      _onSetupComplete();
      return;
    }

    // --- serverContent -------------------------------------------------
    // The server sends response keys in camelCase:
    //   • inputTranscription  — ASR result (user's speech → text)
    //   • outputTranscription — text version of the model's audio response
    //   • turnComplete        — signals the end of a model turn
    if (msg.containsKey('serverContent')) {
      final content = msg['serverContent'] as Map<String, dynamic>? ?? {};

      // Input transcription: what the user said, recognised as text.
      final inputTrans = content['inputTranscription'] as Map<String, dynamic>?;
      final userText = inputTrans?['text'] as String? ?? '';
      if (userText.isNotEmpty) {
        debugPrint('[GeminiVoice] 🎤 inputTranscription: "$userText"');
        _appendText(userText);
      }

      // Output transcription: the model repeating back — useful for
      // debugging but we don't append it to avoid duplicates with
      // inputTranscription (the real speech-to-text result).
      final outputTrans =
          content['outputTranscription'] as Map<String, dynamic>?;
      final modelText = outputTrans?['text'] as String? ?? '';
      if (modelText.isNotEmpty) {
        debugPrint(
            '[GeminiVoice] 🤖 outputTranscription (ignored): "$modelText"');
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

    // --- toolCall ------------------------------------------------------
    // The model requested one or more function calls.
    // Execute locally and send back a toolResponse per the spec.
    if (msg.containsKey('toolCall')) {
      _handleToolCall(msg['toolCall'] as Map<String, dynamic>? ?? {});
      return;
    }

    // --- error ---------------------------------------------------------
    if (msg.containsKey('error')) {
      final err = msg['error'] as Map<String, dynamic>? ?? {};
      final detail = 'Gemini error ${err['code']}: ${err['message']}';
      debugPrint('[GeminiVoice] $detail');
      if (_setupCompleter != null && !_setupCompleter!.isCompleted) {
        _setupCompleter!.completeError(Exception(detail));
      } else {
        _cleanup().then((_) =>
            _emit(state: TranscriptionState.error, error: Exception(detail)));
      }
      return;
    }
  }

  // ---------------------------------------------------------------------
  // setupComplete handler
  // ---------------------------------------------------------------------

  void _onSetupComplete() {
    _setupCompleter?.complete();

    _startMic().then((_) {
      _emit(state: TranscriptionState.recording);
      final start = DateTime.now();

      debugPrint('[GeminiVoice] ✅ setupComplete received — recording started.');

      // Hard limit: stop transcription after 30 seconds.
      _maxTimer = Timer(const Duration(seconds: 30), stopTranscription);

      // Tick every second so the UI can display elapsed time.
      _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        _emit(elapsedSeconds: DateTime.now().difference(start).inSeconds);
      });
    }).catchError((Object e) {
      _cleanup().then((_) => _emit(state: TranscriptionState.error, error: e));
    });
  }

  // ---------------------------------------------------------------------
  // Tool call handling (per official documentation)
  // ---------------------------------------------------------------------

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
        debugPrint('[GeminiVoice] Tool error ($name): $e');
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

  /// Execute a tool function locally.
  /// Override or extend for custom tool implementations.
  Map<String, dynamic> _executeTool(String name, Map<String, dynamic> args) {
    debugPrint('[GeminiVoice] Unknown tool call: $name($args)');
    return {'status': 'unknown tool: $name'};
  }

  // ---------------------------------------------------------------------
  // WebSocket lifecycle callbacks
  // ---------------------------------------------------------------------

  void _onWsError(Object error) {
    debugPrint('[GeminiVoice] WS error: $error');
    if (_setupCompleter != null && !_setupCompleter!.isCompleted) {
      _setupCompleter!.completeError(error);
      return;
    }
    if (isActive) {
      _cleanup()
          .then((_) => _emit(state: TranscriptionState.error, error: error));
    }
  }

  void _onWsDone() {
    final code = _ws?.closeCode;
    final reason = _ws?.closeReason;
    debugPrint('[GeminiVoice] WS closed. code=$code reason="$reason"');

    if (_setupCompleter != null && !_setupCompleter!.isCompleted) {
      _setupCompleter!.completeError(
        Exception(
            'WebSocket closed before setupComplete. code=$code reason="$reason"'),
      );
      return;
    }
    if (_session.state == TranscriptionState.recording) {
      stopTranscription();
    }
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  void _appendText(String token) {
    debugPrint('[GeminiVoice] ✏️ Appending: "$token"');
    final next = _session.transcript + token;
    debugPrint('[GeminiVoice] 📝 Full transcript now: "$next"');
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

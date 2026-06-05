import 'dart:async';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:record/record.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/utils/audio_platform/audio_platform.dart';

// ============================================================================
//  AudioRecorderButton — a footer-style button that opens a recording dialog.
//  The caller provides [onRecordingComplete] which receives the raw audio
//  bytes + MIME type and is responsible for calling the appropriate AI
//  service (DentalHistory, PostOpNotes, etc.) and updating the model.
// ============================================================================

class AudioRecorderButton extends StatelessWidget {
  const AudioRecorderButton({
    super.key,
    required this.label,
    this.icon = WindowsIcons.microphone,
    this.buttonColor,
    required this.onRecordingComplete,
    this.processingMessage,
  });

  /// Button label text (e.g. "Transcribe your audio").
  final String label;

  /// Icon inside the circle button.
  final IconData icon;

  /// Background color of the circle. Defaults to red.
  final Color? buttonColor;

  /// Called when the user stops recording and audio bytes are ready.
  /// The dialog shows a processing spinner while this future is pending.
  /// Throw inside this callback to surface errors — the dialog will still
  /// close gracefully.
  final Future<void> Function(List<int> audioBytes, String mimeType)
      onRecordingComplete;

  /// Shown while [onRecordingComplete] is running.
  /// Defaults to the localized "transcribingYourAudio".
  final String? processingMessage;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () => _openRecorder(context),
      icon: Row(
        spacing: 8,
        children: [
          Container(
            width: 35,
            height: 35,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: buttonColor ?? Colors.red,
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          Txt(label),
        ],
      ),
    );
  }

  Future<void> _openRecorder(BuildContext context) async {
    final recorder = AudioRecorder();
    final hasPermission = await recorder.hasPermission(request: true);
    recorder.dispose();
    if (!hasPermission) return;
    if (!context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          child: _AudioRecorderDialog(
            onRecordingComplete: onRecordingComplete,
            processingMessage:
                processingMessage ?? txt("transcribingYourAudio"),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
//  _AudioRecorderDialog — the recording bubble, self-contained.
//  Records audio, shows waveform + controls, reads bytes, calls the
//  callback, then closes itself.
// ============================================================================

class _AudioRecorderDialog extends StatefulWidget {
  const _AudioRecorderDialog({
    required this.onRecordingComplete,
    required this.processingMessage,
  });

  final Future<void> Function(List<int> audioBytes, String mimeType)
      onRecordingComplete;
  final String processingMessage;

  @override
  State<_AudioRecorderDialog> createState() => _AudioRecorderDialogState();
}

class _AudioRecorderDialogState extends State<_AudioRecorderDialog> {
  final _recorder = AudioRecorder();
  Timer? _timer;
  Timer? _ampTimer;
  final ValueNotifier<Duration> _elapsed = ValueNotifier(Duration.zero);
  final ValueNotifier<double> _amplitude = ValueNotifier(0);
  bool _processing = false;
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    _startRecording();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ampTimer?.cancel();
    _elapsed.dispose();
    _amplitude.dispose();
    _recorder.dispose();
    super.dispose();
  }

  // ── Recording lifecycle ─────────────────────────────────────────────────

  Future<void> _startRecording() async {
    try {
      // On native: writes to a temp file. On web: path is ignored (the
      // browser's MediaRecorder manages its own buffer).
      await _recorder.start(const RecordConfig(),
          path: AudioPlatform.getTempAudioPath());
    } catch (_) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    _startTimer();
    _startAmplitudeMonitor();
    setState(() {});
  }

  Future<void> _pause() async {
    await _recorder.pause();
    _paused = true;
    _timer?.cancel();
    _ampTimer?.cancel();
    setState(() {});
  }

  Future<void> _resume() async {
    await _recorder.resume();
    _paused = false;
    _startTimer();
    _startAmplitudeMonitor();
    setState(() {});
  }

  Future<void> _cancel() async {
    await _recorder.cancel();
    _timer?.cancel();
    _ampTimer?.cancel();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _stopAndSubmit() async {
    final path = await _recorder.stop();
    _timer?.cancel();
    _ampTimer?.cancel();
    if (path == null) {
      if (mounted) Navigator.of(context).pop();
      return;
    }

    setState(() => _processing = true);

    try {
      final ext = path.split('.').lastOrNull ?? 'm4a';
      final mimeType = 'audio/$ext';
      final bytes = await AudioPlatform.readFileBytes(path);
      await widget.onRecordingComplete(bytes, mimeType);
    } catch (_) {
      // Callback is responsible for its own error handling / user feedback.
      // We just close the dialog.
    }

    if (mounted) Navigator.of(context).pop();
  }

  // ── Timers ──────────────────────────────────────────────────────────────

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _elapsed.value += const Duration(milliseconds: 100);
    });
  }

  void _startAmplitudeMonitor() {
    _ampTimer?.cancel();
    _ampTimer = Timer.periodic(const Duration(milliseconds: 100), (_) async {
      try {
        final amp = await _recorder.getAmplitude();
        _amplitude.value = (amp.current + 60) / 60;
      } catch (_) {}
    });
  }

  String _formatTime(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: FluentTheme.of(context).resources.solidBackgroundFillColorBase,
        borderRadius: BorderRadius.circular(100),
        boxShadow: const [
          BoxShadow(color: Colors.black, blurRadius: 300, spreadRadius: 200),
        ],
      ),
      child: _processing ? _buildProcessing() : _buildControls(),
    );
  }

  Widget _buildProcessing() {
    return SizedBox(
      height: 40,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
              width: 14, height: 14, child: ProgressRing(strokeWidth: 2)),
          const SizedBox(width: 12),
          Txt(widget.processingMessage),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHeader(),
        const SizedBox(height: 12),
        _buildWaveform(),
        const SizedBox(height: 16),
        if (_paused) _buildPausedRow() else _buildRecordingRow(),
      ],
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _paused ? Colors.orange : Colors.red,
          ),
        ),
        const SizedBox(width: 8),
        Txt(
          _paused ? txt("paused") : txt("recording"),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _paused ? Colors.orange : Colors.red,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _buildRecordingRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _smallBtn(WindowsIcons.pause, _pause),
        const SizedBox(width: 24),
        _stopBtn(),
        const SizedBox(width: 24),
        _smallBtn(WindowsIcons.cancel, _cancel),
      ],
    );
  }

  Widget _buildPausedRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _smallBtn(WindowsIcons.play, _resume),
        const SizedBox(width: 24),
        _stopBtn(),
        const SizedBox(width: 24),
        _smallBtn(WindowsIcons.cancel, _cancel),
      ],
    );
  }

  Widget _stopBtn() {
    return GestureDetector(
      onTap: _stopAndSubmit,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _paused ? Colors.blue : Colors.red,
        ),
        child: Icon(
          _paused ? WindowsIcons.upload : WindowsIcons.stop,
          color: Colors.white,
          size: 28,
        ),
      ),
    );
  }

  Widget _smallBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: FluentTheme.of(context).activeColor.withAlpha(100),
        ),
        child: Icon(icon, size: 18, color: Colors.grey),
      ),
    );
  }

  Widget _buildWaveform() {
    return ValueListenableBuilder<Duration>(
      valueListenable: _elapsed,
      builder: (context, dur, _) {
        return ValueListenableBuilder<double>(
          valueListenable: _amplitude,
          builder: (context, amp, _) {
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              spacing: 5,
              children: [
                Txt(_formatTime(dur),
                    style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w300,
                        fontFamily: 'monospace')),
                SizedBox(
                  height: 32,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(40, (i) {
                      final h = _paused
                          ? 4.0
                          : 4.0 + (amp * 28 * ((i % 3 == 0) ? 1.8 : 1.0));
                      return Container(
                        width: 3,
                        height: h.clamp(4.0, 32.0),
                        margin: const EdgeInsets.symmetric(horizontal: 1.5),
                        decoration: BoxDecoration(
                          color: Colors.red.withAlpha(_paused ? 60 : 180),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      );
                    }),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

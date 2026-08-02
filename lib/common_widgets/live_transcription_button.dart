import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/services/g_audio_transcription.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';

class LiveTranscriptionButton extends StatefulWidget {
  const LiveTranscriptionButton({
    super.key,
    required this.textController,
    required this.onDone,
  });
  final TextEditingController textController;
  final void Function(String) onDone;

  @override
  State<LiveTranscriptionButton> createState() =>
      _LiveTranscriptionButtonState();
}

class _LiveTranscriptionButtonState extends State<LiveTranscriptionButton> {
  late WSVoiceTranscriptionService liveTranscriptionService;

  @override
  void initState() {
    super.initState();

    liveTranscriptionService = WSVoiceTranscriptionService(
      controller: widget.textController,
      clearOnStart: false,
      onDone: widget.onDone,
    );
  }

  @override
  void dispose() {
    liveTranscriptionService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: txt("voiceInput"),
      child: StreamBuilder<TranscriptionSession>(
          stream: liveTranscriptionService.stream,
          builder: (context, _) {
            final session = liveTranscriptionService.session;
            final state = session.state;
            final elapsed = session.elapsedSeconds;

            // ── Idle / Error / Stopping: grey mic ────────────────
            if (state == TranscriptionState.idle ||
                state == TranscriptionState.error ||
                state == TranscriptionState.stopping) {
              return IconButton(
                icon: const Icon(WindowsIcons.microphone, size: 16),
                onPressed: () => liveTranscriptionService.startTranscription(),
              );
            }

            // ── Connecting: orange spinner ────────────────────────
            if (state == TranscriptionState.connecting) {
              return IconButton(
                style: filledButtonStyle(Colors.white),
                icon: const SizedBox(
                  width: 14,
                  height: 14,
                  child: ProgressRing(
                    strokeWidth: 2,
                    activeColor: Colors.grey,
                  ),
                ),
                onPressed: () {},
              );
            }

            // ── Recording: red dot + seconds ──────────────────────
            final remaining = 30 - elapsed;
            final warn = remaining <= 10;
            final color = warn ? Colors.orange : Colors.red;
            return IconButton(
              style: filledButtonStyle(color),
              icon: Row(
                spacing: 5,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 13,
                    width: 13,
                    child: ProgressRing(
                      strokeWidth: 2,
                      value: (remaining / 30) * 100,
                      backgroundColor: Colors.white.withAlpha(150),
                      activeColor: Colors.white,
                    ),
                  ),
                  Text(
                    '$remaining',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              onPressed: () => liveTranscriptionService.stopTranscription(),
            );
          }),
    );
  }
}

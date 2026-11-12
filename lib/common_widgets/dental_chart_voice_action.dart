import 'package:apexo/common_widgets/audio_recorder.dart';
import 'package:apexo/common_widgets/error_dialog.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/ai_services/dental_history.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/network.dart';
import 'package:apexo/shared/dental_chart/dental_chart_session.dart';
import 'package:apexo/utils/logger.dart';
import 'package:flutter/widgets.dart';

/// Dictation edits only the active chart's draft; its own Save persists it.
Widget Function(DentalChartSession session)? dentalHistoryVoiceAction({
  Future<DentalHistoryData> Function(List<int> bytes, String filename)?
      transcribe,
}) {
  if (!network.isOnline() || !globalSettings.aiServicesEnabled) return null;
  return (session) => Row(
        children: [
          AudioRecorderButton(
            hint: txt('dentalHistoryVoiceAutoFillHint'),
            label: txt('voiceAutoFill'),
            onRecordingComplete: (bytes, mimeType) async {
              try {
                final result = await (transcribe ??
                    DentalHistory.processAudioBytes)(bytes, mimeType);
                session.teeth.addAll(result.teeth);
                session.extraNotes.addAll(result.teethExtraNotes);
                session.changed();
              } catch (e, s) {
                showErrorMessage(e, 'processingDentalHistory');
                logger('Error processing dental history audio: $e', s);
              }
            },
          ),
        ],
      );
}

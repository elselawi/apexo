import 'dart:io';
import 'package:apexo/services/ai_services.dart';
import 'package:http/http.dart' as http;

// ============================================================================
//  Models
// ============================================================================

class DentalHistoryData {
  final Map<String, String> teeth;
  final Map<String, String> teethExtraNotes;

  DentalHistoryData({required this.teeth, required this.teethExtraNotes});

  factory DentalHistoryData.fromJson(Map<String, dynamic> json) =>
      DentalHistoryData(
        teeth: (json['teeth'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(k, v as String)) ??
            {},
        teethExtraNotes: (json['teethExtraNotes'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(k, v as String)) ??
            {},
      );
}

// ============================================================================
//  DentalHistory — audio-to-dental-chart via AIService
// ============================================================================

class DentalHistory extends AIService {
  /// Processes an audio recording from raw bytes.
  static Future<DentalHistoryData> processAudioBytes(
    List<int> audioBytes,
    String filename, {
    String? lang,
  }) async {
    final r = await AIService.createMultipartRequest('dental-history');
    if (lang != null) {
      r.fields['lang'] = lang;
    }
    r.files.add(
      http.MultipartFile.fromBytes('audio', audioBytes, filename: filename),
    );
    final res = await http.Response.fromStream(await r.send());
    return AIService.parseResponse(res, DentalHistoryData.fromJson);
  }

  /// Processes an audio file from disk (native only).
  static Future<DentalHistoryData> processAudioFile(
    String path, {
    String? lang,
  }) async =>
      processAudioBytes(
        await File(path).readAsBytes(),
        path.split('/').last,
        lang: lang,
      );
}

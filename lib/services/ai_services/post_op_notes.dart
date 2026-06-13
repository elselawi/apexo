import 'dart:convert';
import 'dart:io';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/ai_services.dart';
import 'package:http/http.dart' as http;

// ============================================================================
//  Models
// ============================================================================

class PostOpData {
  final String postOpNotes;
  final List<String> prescriptions;
  final double price;
  final double paid;
  final Map<String, String> teeth;
  final Map<String, String> teethExtraNotes;
  final bool hasLabwork;
  final String labName;
  final String labworkNotes;

  PostOpData({
    required this.postOpNotes,
    required this.prescriptions,
    required this.price,
    required this.paid,
    required this.teeth,
    required this.teethExtraNotes,
    required this.hasLabwork,
    required this.labName,
    required this.labworkNotes,
  });

  factory PostOpData.fromJson(Map<String, dynamic> json) => PostOpData(
        postOpNotes: json['postOpNotes'] as String? ?? '',
        prescriptions: (json['prescriptions'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        price: (json['price'] as num?)?.toDouble() ?? 0.0,
        paid: (json['paid'] as num?)?.toDouble() ?? 0.0,
        teeth: (json['teeth'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(k, v as String)) ??
            {},
        teethExtraNotes: (json['teethExtraNotes'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(k, v as String)) ??
            {},
        hasLabwork: json['hasLabwork'] as bool? ?? false,
        labName: json['labName'] as String? ?? '',
        labworkNotes: json['labworkNotes'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'postOpNotes': postOpNotes,
        'prescriptions': prescriptions,
        'price': price,
        'paid': paid,
        'teeth': teeth,
        'teethExtraNotes': teethExtraNotes,
        'hasLabwork': hasLabwork,
        'labName': labName,
        'labworkNotes': labworkNotes,
      };
}

// ============================================================================
//  PostOpNotes — audio-to-structured-notes via AIService
// ============================================================================

class PostOpNotes extends AIService {
  /// Processes an audio recording from raw bytes.
  static Future<PostOpData> processAudioBytes(
    List<int> audioBytes,
    String filename, {
    PostOpData? existingFields,
  }) async {
    final r = await AIService.createMultipartRequest('post-op-notes');
    if (existingFields != null) {
      r.fields['existingFields'] = jsonEncode(existingFields.toJson());
    }

    r.fields['lang'] = localSettings.transcriptionOutputLocale;

    r.files.add(
      http.MultipartFile.fromBytes('audio', audioBytes, filename: filename),
    );
    final res = await http.Response.fromStream(await r.send());
    return AIService.parseResponse(res, PostOpData.fromJson);
  }

  /// Processes an audio file from disk (native only).
  static Future<PostOpData> processAudioFile(
    String path, {
    PostOpData? existingFields,
  }) async =>
      processAudioBytes(
        await File(path).readAsBytes(),
        path.split('/').last,
        existingFields: existingFields,
      );
}

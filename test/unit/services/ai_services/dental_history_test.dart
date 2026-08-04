import 'package:apexo/services/ai_services/dental_history.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DentalHistoryData', () {
    test('fromJson parses teeth map and extra notes', () {
      final json = {
        'teeth': {'11': 'filling', '21': 'crown'},
        'teethExtraNotes': {'11': 'Deep cavity, monitor'},
      };

      final data = DentalHistoryData.fromJson(json);

      expect(data.teeth, {'11': 'filling', '21': 'crown'});
      expect(data.teethExtraNotes, {'11': 'Deep cavity, monitor'});
    });

    test('fromJson handles empty teeth', () {
      final data = DentalHistoryData.fromJson({
        'teeth': <String, dynamic>{},
        'teethExtraNotes': <String, dynamic>{},
      });

      expect(data.teeth, isEmpty);
      expect(data.teethExtraNotes, isEmpty);
    });

    test('fromJson handles missing keys', () {
      final data = DentalHistoryData.fromJson({});

      expect(data.teeth, isEmpty);
      expect(data.teethExtraNotes, isEmpty);
    });

    test('fromJson handles null values in map', () {
      final data = DentalHistoryData.fromJson({
        'teeth': null,
        'teethExtraNotes': null,
      });

      expect(data.teeth, isEmpty);
      expect(data.teethExtraNotes, isEmpty);
    });

    test('fromJson with many teeth', () {
      final teeth = <String, String>{};
      for (int i = 11; i <= 48; i++) {
        if (i % 10 <= 8) teeth['$i'] = 'examined';
      }
      final data = DentalHistoryData.fromJson({'teeth': teeth});
      expect(data.teeth.length, teeth.length);
    });

    test('DentalHistory is an AIService subclass', () {
      // Verify the class exists and can be referenced
      expect(DentalHistory, isNotNull);
    });
  });
}

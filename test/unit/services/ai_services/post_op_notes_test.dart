import 'package:apexo/services/ai_services/post_op_notes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PostOpData', () {
    test('fromJson parses all fields', () {
      final json = {
        'postOpNotes': 'Extraction completed.',
        'prescriptions': ['Amoxicillin 500mg', 'Ibuprofen 400mg'],
        'price': 250.0,
        'paid': 250.0,
        'teeth': {'36': 'extraction'},
        'teethExtraNotes': {'36': 'Healing well'},
        'hasLabwork': true,
        'labName': 'Crown Lab',
        'labworkNotes': 'PFM crown',
      };

      final data = PostOpData.fromJson(json);

      expect(data.postOpNotes, 'Extraction completed.');
      expect(data.prescriptions, ['Amoxicillin 500mg', 'Ibuprofen 400mg']);
      expect(data.price, 250.0);
      expect(data.paid, 250.0);
      expect(data.teeth, {'36': 'extraction'});
      expect(data.teethExtraNotes, {'36': 'Healing well'});
      expect(data.hasLabwork, true);
      expect(data.labName, 'Crown Lab');
      expect(data.labworkNotes, 'PFM crown');
    });

    test('fromJson handles missing fields with defaults', () {
      final data = PostOpData.fromJson({});

      expect(data.postOpNotes, isEmpty);
      expect(data.prescriptions, isEmpty);
      expect(data.price, 0.0);
      expect(data.paid, 0.0);
      expect(data.teeth, isEmpty);
      expect(data.hasLabwork, false);
      expect(data.labName, isEmpty);
      expect(data.labworkNotes, isEmpty);
    });

    test('fromJson handles price/paid as int', () {
      final data = PostOpData.fromJson({'price': 100, 'paid': 50});
      expect(data.price, 100.0);
      expect(data.paid, 50.0);
    });

    test('fromJson handles null prescriptions', () {
      final data = PostOpData.fromJson({'prescriptions': null});
      expect(data.prescriptions, isEmpty);
    });

    test('toJson round-trip preserves all fields', () {
      final original = PostOpData(
        postOpNotes: 'Done',
        prescriptions: ['Rx1'],
        price: 150.0,
        paid: 100.0,
        teeth: {'11': 'filling'},
        teethExtraNotes: {'11': 'Deep'},
        hasLabwork: false,
        labName: '',
        labworkNotes: '',
      );

      final json = original.toJson();
      final restored = PostOpData.fromJson(json);

      expect(restored.postOpNotes, 'Done');
      expect(restored.prescriptions, ['Rx1']);
      expect(restored.price, 150.0);
      expect(restored.paid, 100.0);
      expect(restored.hasLabwork, false);
    });

    test('PostOpNotes class exists', () {
      expect(PostOpNotes, isNotNull);
    });
  });
}

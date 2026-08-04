import 'package:apexo/features/patients/patient_model.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../helpers/model_factory.dart';

void main() {
  group('Patient.fromJson', () {
    test('parses all core fields', () {
      final p = Patient.fromJson({
        'id': 'pat1',
        'title': 'John Doe',
        'birth': 1990,
        'gender': 1,
        'phone': '+1234567890',
        'email': 'john@example.com',
        'address': '123 Main St',
        'tags': ['diabetic'],
        'notes': 'Allergic to penicillin',
        'teeth': {'11': 'filling'},
        'teethExtraNotes': {'11': 'Deep'},
      });

      expect(p.id, 'pat1');
      expect(p.title, 'John Doe');
      expect(p.birth, 1990);
      expect(p.gender, 1);
      expect(p.email, 'john@example.com');
      expect(p.address, '123 Main St');
      expect(p.tags, ['diabetic']);
      expect(p.notes, 'Allergic to penicillin');
      expect(p.teeth, {'11': 'filling'});
    });

    test('handles missing optional fields with defaults', () {
      final p = Patient.fromJson({'id': 'min'});
      expect(p.birth, DateTime.now().year - 18);
      expect(p.gender, 0);
      expect(p.email, isEmpty);
      expect(p.address, isEmpty);
      expect(p.tags, isEmpty);
    });

    test('phone field defaults to empty list', () {
      final p = testPatient(id: 'ph1');
      expect(p.phone, isEmpty);
    });

    test('phone input is normalized into exact E.164 output', () {
      final p = Patient.fromJson({
        'phone': '+1 (202) 555-0147',
      });

      expect(p.phonesString, '+12025550147');
      expect(p.toJson()['phone'], '+12025550147');
    });

    test('malformed collection values are rejected', () {
      expect(
        () => Patient.fromJson({'tags': 'not-a-list'}),
        throwsA(anything),
      );
      expect(
        () => Patient.fromJson({'teeth': 'not-a-map'}),
        throwsA(anything),
      );
    });
  });

  group('Patient.toJson', () {
    test('round-trip preserves all fields', () {
      final p = testPatient(
        id: 'rt1',
        name: 'John',
        birth: 1990,
        gender: 1,
        email: 'j@e.com',
        tags: ['tag1'],
      );
      final json = p.toJson();
      expect(json['id'], 'rt1');
      expect(json['title'], 'John');
      expect(json['birth'], 1990);
      expect(json['gender'], 1);
    });

    test('omits default collections and retains explicit dental fields', () {
      final p = Patient.fromJson({
        'id': 'dental',
        'teeth': {'11': 'filling'},
        'teethExtraNotes': {'11': 'deep'},
      });
      final json = p.toJson();

      expect(json['teeth'], {'11': 'filling'});
      expect(json['teethExtraNotes'], {'11': 'deep'});
      expect(json.containsKey('tags'), isFalse);
    });
  });

  group('Patient computed getters', () {
    test('age = current year - birth', () {
      final p = testPatient(id: 'age1', birth: 2000);
      expect(p.age, DateTime.now().year - 2000);
    });

    test('phonesString returns string for empty phone list', () {
      final p = testPatient(id: 'ps1', name: 'Test');
      // phone defaults to empty list via model_factory
      expect(p.phonesString, isEmpty);
    });

    test('searchString is lowercase', () {
      final p = testPatient(id: 'ss1', name: 'John DOE');
      expect(p.searchString, contains('john doe'));
    });

    test('searchString normalizes Arabic alif', () {
      final p = testPatient(id: 'ss2', name: 'أحمد');
      final s = p.searchString;
      expect(s.contains('أ'), false);
    });

    test('nullifyLabels clears cached search and labels', () {
      final p = testPatient(id: 'nl1', name: 'Test');
      final before = p.searchString;
      p.nullifyLabels();
      final after = p.searchString;
      expect(after, before);
      expect(after, startsWith('test'));
    });

    test('tableLabels returns non-empty list', () {
      final p = testPatient(id: 'tl1', name: 'Test', birth: 2000, gender: 1);
      final labels = p.tableLabels;
      expect(labels, isNotEmpty);
    });

    test('formatDuration returns human-readable string', () {
      final from = DateTime(2024, 1, 15);
      final to = DateTime(2026, 4, 20);
      final s = Patient.formatDuration(from, to);
      expect(s, contains('2'));
      expect(s, isNotEmpty);
    });

    test('formatDuration handles same date', () {
      final d = DateTime(2024, 1, 1);
      expect(Patient.formatDuration(d, d), '0 day');
    });

    test('copy preserves all fields', () {
      final orig = testPatient(id: 'cpy1', name: 'Original', birth: 1995);
      final clone = orig.copy(false);
      expect(clone.id, 'cpy1');
      expect(clone.title, 'Original');
      expect(clone.birth, 1995);
    });

    test('copy deep-copies collections and preserves phone normalization', () {
      final original = Patient.fromJson({
        'id': 'deep-copy',
        'phone': '+12025550147',
        'tags': ['vip'],
        'teeth': {'11': 'filling'},
      });
      final clone = original.copy(false);
      clone.tags.add('new');
      clone.teeth['12'] = 'crown';

      expect(original.tags, ['vip']);
      expect(original.teeth, {'11': 'filling'});
      expect(clone.phonesString, original.phonesString);
    });

    test('age boundary uses the current calendar year exactly', () {
      final year = DateTime.now().year;
      expect(testPatient(id: 'age-boundary', birth: year).age, 0);
      expect(testPatient(id: 'age-boundary-18', birth: year - 18).age, 18);
    });
  });
}

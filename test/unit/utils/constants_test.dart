import 'package:apexo/utils/constants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('string constants', () {
    test('shorteningServer is valid URL', () {
      expect(shorteningServer, 'https://p.apexo.app');
      expect(shorteningServer.startsWith('https://'), true);
    });

    test('alphabet has 36 chars (a-z + 0-9)', () {
      expect(alphabet.length, 36);
      expect(alphabet, 'abcdefghijklmnopqrstuvwxyz0123456789');
    });

    test('dataCollectionName is "data"', () {
      expect(dataCollectionName, 'data');
    });

    test('publicCollectionName is "public"', () {
      expect(publicCollectionName, 'public');
    });

    test('webImagesStore is "web-images"', () {
      expect(webImagesStore, 'web-images');
    });

    test('profilesCollectionName is "profiles"', () {
      expect(profilesCollectionName, 'profiles');
    });

    test('profilesViewCollectionName is "profiles_view"', () {
      expect(profilesViewCollectionName, 'profiles_view');
    });
  });

  group('dataCollectionImport', () {
    test('name is dataCollectionName', () {
      expect(dataCollectionImport.name, dataCollectionName);
    });

    test('type is "base"', () {
      expect(dataCollectionImport.type, 'base');
    });

    test('has exactly 6 fields', () {
      expect(dataCollectionImport.fields.length, 6);
    });

    test('field names: id, data, store, imgs, created, updated', () {
      final names = dataCollectionImport.fields.map((f) => f.name).toList();
      expect(names, ['id', 'data', 'store', 'imgs', 'created', 'updated']);
    });

    test('id field has the exact generated-ID constraints', () {
      final f = dataCollectionImport.fields.firstWhere((f) => f.name == 'id');

      expect(f.type, 'text');
      expect(f.required, isTrue);
      expect(f.get<bool>('primaryKey'), isTrue);
      expect(f.system, isTrue);
      expect(f.get<int>('min'), 15);
      expect(f.get<int>('max'), 15);
      expect(f.get<String>('autogeneratePattern'), '[a-z0-9]{15}');
      expect(f.get<String>('pattern'), r'^[a-zA-Z0-9_]+$');
    });

    test('data field has the exact JSON size and optionality', () {
      final f = dataCollectionImport.fields.firstWhere((f) => f.name == 'data');
      expect(f.type, 'json');
      expect(f.get<int>('maxSize'), 2000000);
      expect(f.required, isFalse);
    });

    test('imgs field has the exact file constraints', () {
      final f = dataCollectionImport.fields.firstWhere((f) => f.name == 'imgs');
      expect(f.type, 'file');
      expect(f.get<int>('maxSelect'), 99);
      expect(f.get<int>('maxSize'), 157286400);
      expect(f.required, isFalse);
      expect(f.get<bool>('protected'), isFalse);
    });

    test('autodate fields have the correct create and update semantics', () {
      final created =
          dataCollectionImport.fields.firstWhere((f) => f.name == 'created');
      final updated =
          dataCollectionImport.fields.firstWhere((f) => f.name == 'updated');

      expect(created.type, 'autodate');
      expect(created.get<bool>('onCreate'), isTrue);
      expect(created.get<bool>('onUpdate'), isFalse);
      expect(updated.type, 'autodate');
      expect(updated.get<bool>('onCreate'), isTrue);
      expect(updated.get<bool>('onUpdate'), isTrue);
    });

    test('has 2 indexes', () {
      expect(dataCollectionImport.indexes.length, 2);
    });

    test('indexes retain the exact incremental-sync SQL', () {
      expect(dataCollectionImport.indexes, [
        'CREATE INDEX `idx_get_since` ON `data` (\n  `store`,\n  `updated`\n)',
        'CREATE INDEX `idx_get_version` ON `data` (\n  `store`,\n  `updated` DESC\n)',
      ]);
    });

    test('rules preserve public settings reads and authenticated writes only',
        () {
      expect(dataCollectionImport.listRule, ruleEitherLoggedOrSettings);
      expect(dataCollectionImport.viewRule, ruleEitherLoggedOrSettings);
      expect(dataCollectionImport.createRule, ruleLoggedUsersExceptForSettings);
      expect(dataCollectionImport.updateRule, ruleLoggedUsersExceptForSettings);
      expect(dataCollectionImport.deleteRule, ruleLoggedUsersExceptForSettings);
    });
  });

  group('publicCollectionImport', () {
    test('name is "public"', () {
      expect(publicCollectionImport.name, 'public');
    });

    test('type is "view"', () {
      expect(publicCollectionImport.type, 'view');
    });

    test('viewQuery filters store = appointments', () {
      expect(
          publicCollectionImport.viewQuery, contains("store = 'appointments'"));
    });

    test('viewQuery extracts patientID, date, prescriptions, price, paid', () {
      final q = publicCollectionImport.viewQuery!;
      expect(q, contains("json_extract(data.data, '\$.patientID') AS pid"));
      expect(q, contains('patientID'));
      expect(q, contains('prescriptions'));
      expect(q, contains('price'));
      expect(q, contains('paid'));
      expect(q, contains('isDone'));
      expect(q, contains('archived'));
      expect(q, contains('FROM data'));
    });

    test('is a read-only view with intentionally empty public rules', () {
      expect(publicCollectionImport.listRule, '');
      expect(publicCollectionImport.viewRule, '');
      expect(publicCollectionImport.createRule, isNull);
      expect(publicCollectionImport.updateRule, isNull);
      expect(publicCollectionImport.deleteRule, isNull);
    });
  });

  group('profilesViewCollectionImport', () {
    test('type is "view"', () {
      expect(profilesViewCollectionImport.type, 'view');
    });

    test('viewQuery UNIONs users and _superusers', () {
      final q = profilesViewCollectionImport.viewQuery!;
      expect(q, contains('UNION ALL'));
      expect(q, contains('`users`'));
      expect(q, contains('`_superusers`'));
      expect(q, contains('LEFT JOIN `profiles`'));
      expect(q, contains("'System Admin'"));
    });
  });

  group('profilesCollectionImport', () {
    test('name is profilesCollectionName', () {
      expect(profilesCollectionImport.name, profilesCollectionName);
    });

    test(
        'has 7 fields (id, account_id, name, permissions, operate, created, updated)',
        () {
      final names = profilesCollectionImport.fields.map((f) => f.name).toSet();
      expect(names.length, 7);
      expect(names.contains('account_id'), true);
      expect(names.contains('permissions'), true);
      expect(names.contains('operate'), true);
    });

    test('account ID is required and timestamps preserve audit semantics', () {
      final accountId = profilesCollectionImport.fields
          .firstWhere((f) => f.name == 'account_id');
      final created = profilesCollectionImport.fields
          .firstWhere((f) => f.name == 'created');
      final updated = profilesCollectionImport.fields
          .firstWhere((f) => f.name == 'updated');

      expect(accountId.required, isTrue);
      expect(created.get<bool>('onCreate'), isTrue);
      expect(created.get<bool>('onUpdate'), isFalse);
      expect(updated.get<bool>('onCreate'), isTrue);
      expect(updated.get<bool>('onUpdate'), isTrue);
    });
  });

  group('rule constants', () {
    test('write rule is exact', () {
      expect(ruleLoggedUsersExceptForSettings,
          '@request.auth.id != "" && store != "settings_global"');
    });

    test('read rule is exact', () {
      expect(ruleEitherLoggedOrSettings,
          '@request.auth.id != "" || store = "settings_global"');
    });
  });

  group('Perm export', () {
    test('Perm is exported from constants.dart', () {
      // Verify the export works — Perm constants should be accessible
      expect(Perm.patients, 0);
      expect(Perm.count, 9);
    });
  });
}

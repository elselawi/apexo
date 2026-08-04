@Tags(['live_backend', 'serial'])
library;

import 'dart:convert';

import 'package:apexo/core/save_remote.dart';
import 'package:apexo/utils/uuid.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apexo/core/store.dart';
import 'package:apexo/core/model.dart';
import 'package:apexo/core/observable.dart';
import 'package:apexo/core/save_local.dart';
import 'package:pocketbase/pocketbase.dart';
import '../test_utils.dart';

class Person extends Model {
  String name = 'alex';
  int age = 100;

  Person.fromJson(Map<String, dynamic> json) : super.fromJson(json) {
    name = json["name"] ?? name;
    age = json["age"] ?? age;
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    final d = Person.fromJson({});
    if (name != d.name) json['name'] = name;
    if (age != d.age) json['age'] = age;
    return json;
  }

  get ageInDays => age * 365;
}

class FilePerson extends Model {
  List<String> imgs = [];
  List<String> dcmImgs = [];

  FilePerson.fromJson(Map<String, dynamic> json) : super.fromJson(json) {
    imgs = List<String>.from(json['imgs'] ?? imgs);
    dcmImgs = List<String>.from(json['dcmImgs'] ?? dcmImgs);
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    if (imgs.isNotEmpty) json['imgs'] = imgs;
    if (dcmImgs.isNotEmpty) json['dcmImgs'] = dcmImgs;
    return json;
  }
}

void main() {
  group('Store.mergeConflict (field-level merge)', () {
    test('scalar union: field only on one side is preserved', () {
      final local = {'id': 'x', 'name': 'Alice'};
      final remote = {'id': 'x', 'phone': '555'};
      final merged = Store.mergeConflict(
        localJson: local,
        remoteJson: remote,
        localWins: true,
      );
      expect(merged['id'], 'x');
      expect(merged['name'], 'Alice');
      expect(merged['phone'], '555');
    });

    test('scalar LWW: both sides have different non-default values', () {
      final local = {'id': 'x', 'name': 'Alice'};
      final remote = {'id': 'x', 'name': 'Bob'};
      final mergedLocalWins = Store.mergeConflict(
        localJson: local,
        remoteJson: remote,
        localWins: true,
      );
      expect(mergedLocalWins['name'], 'Alice');

      final mergedRemoteWins = Store.mergeConflict(
        localJson: local,
        remoteJson: remote,
        localWins: false,
      );
      expect(mergedRemoteWins['name'], 'Bob');
    });

    test('scalar union: default-absent field does not override set field', () {
      // Local has age=0 (default, omitted from JSON). Remote has age=12.
      // Union should take remote's 12.
      final local = {'id': 'x', 'name': 'Alice'};
      final remote = {'id': 'x', 'name': 'Alice', 'age': 12};
      final merged = Store.mergeConflict(
        localJson: local,
        remoteJson: remote,
        localWins: true,
      );
      expect(merged['age'], 12);
    });

    test('map per-key merge: different keys survive from both sides', () {
      // Two dentists edit different teeth.
      final local = {
        'id': 'x',
        'teeth': {'31': 'crown'}
      };
      final remote = {
        'id': 'x',
        'teeth': {'38': 'filling'}
      };
      final merged = Store.mergeConflict(
        localJson: local,
        remoteJson: remote,
        localWins: true,
      );
      final teeth = merged['teeth'] as Map<String, dynamic>;
      expect(teeth['31'], 'crown');
      expect(teeth['38'], 'filling');
    });

    test('map per-key LWW: same key conflict resolved by localWins', () {
      final local = {
        'id': 'x',
        'teeth': {'31': 'crown-local'}
      };
      final remote = {
        'id': 'x',
        'teeth': {'31': 'crown-remote'}
      };
      final mergedLocalWins = Store.mergeConflict(
        localJson: local,
        remoteJson: remote,
        localWins: true,
      );
      expect((mergedLocalWins['teeth'] as Map)['31'], 'crown-local');

      final mergedRemoteWins = Store.mergeConflict(
        localJson: local,
        remoteJson: remote,
        localWins: false,
      );
      expect((mergedRemoteWins['teeth'] as Map)['31'], 'crown-remote');
    });

    test('map deletion NOT preserved without a base version (known limitation)',
        () {
      // Local has teeth {31, 38}, remote deleted 38 (only has 31).
      // Remote wins the timestamp, but without a common-ancestor (base)
      // version we cannot distinguish "remote never had 38" from "remote
      // deleted 38".  Union merge therefore re-adds 38 from the loser.
      // This is the documented tombstone limitation of 2-way merge.
      final local = {
        'id': 'x',
        'teeth': {'31': 'crown', '38': 'filling'}
      };
      final remote = {
        'id': 'x',
        'teeth': {'31': 'crown'}
      };
      final merged = Store.mergeConflict(
        localJson: local,
        remoteJson: remote,
        localWins: false, // remote wins timestamp
      );
      final teeth = merged['teeth'] as Map<String, dynamic>;
      // 38 is resurrected — this is the known union-merge limitation.
      expect(teeth.containsKey('38'), isTrue);
      expect(teeth['38'], 'filling');
      expect(teeth['31'], 'crown');
    });

    test('operatorsIDs union with dedup', () {
      final local = {
        'id': 'x',
        'operatorsIDs': ['a', 'b']
      };
      final remote = {
        'id': 'x',
        'operatorsIDs': ['b', 'c']
      };
      final merged = Store.mergeConflict(
        localJson: local,
        remoteJson: remote,
        localWins: true,
      );
      final ops = (merged['operatorsIDs'] as List).cast<String>();
      expect(ops.toSet(), {'a', 'b', 'c'});
    });

    test('tags (LWW list) are NOT merged — winner takes whole field', () {
      final local = {
        'id': 'x',
        'tags': ['vip', 'allergy']
      };
      final remote = {
        'id': 'x',
        'tags': ['vip', 'diabetic']
      };
      final mergedLocalWins = Store.mergeConflict(
        localJson: local,
        remoteJson: remote,
        localWins: true,
      );
      expect(
          (mergedLocalWins['tags'] as List).cast<String>(), ['vip', 'allergy']);
    });

    test('imgs reconciled against server files', () {
      final local = {
        'id': 'x',
        'imgs': ['a.png', 'b.png', 'stale.png']
      };
      final remote = {
        'id': 'x',
        'imgs': ['a.png', 'c.png']
      };
      // Server only has a.png and b.png.
      final merged = Store.mergeConflict(
        localJson: local,
        remoteJson: remote,
        localWins: true,
        serverFiles: ['a.png', 'b.png'],
      );
      final imgs = (merged['imgs'] as List).cast<String>().toSet();
      // stale.png dropped (not on server), c.png dropped (not on server).
      expect(imgs, {'a.png', 'b.png'});
    });

    test('imgs keeps pending uploads not yet on server', () {
      final local = {
        'id': 'x',
        'imgs': ['a.png', 'pending.png']
      };
      final remote = {'id': 'x'};
      // pending.png is not on the server yet but is queued for upload.
      final merged = Store.mergeConflict(
        localJson: local,
        remoteJson: remote,
        localWins: true,
        serverFiles: ['a.png'],
        pendingUploads: {'pending.png'},
      );
      final imgs = (merged['imgs'] as List).cast<String>().toSet();
      expect(imgs, {'a.png', 'pending.png'});
    });

    test('dcmImgs separated from regular imgs via server file list', () {
      final local = {
        'id': 'x',
        'imgs': ['photo.png'],
        'dcmImgs': ['scan.dcm']
      };
      final remote = {
        'id': 'x',
        'imgs': ['photo.png', 'old.png'],
        'dcmImgs': ['scan.dcm', 'removed.dcm']
      };
      // Server has photo.png and scan.dcm only.
      final merged = Store.mergeConflict(
        localJson: local,
        remoteJson: remote,
        localWins: true,
        serverFiles: ['photo.png', 'scan.dcm'],
      );
      final imgs = (merged['imgs'] as List).cast<String>().toSet();
      final dcmImgs = (merged['dcmImgs'] as List).cast<String>().toSet();
      expect(imgs, {'photo.png'});
      expect(dcmImgs, {'scan.dcm'});
    });

    test('date always present, resolved by LWW', () {
      final local = {'id': 'x', 'date': 1000};
      final remote = {'id': 'x', 'date': 2000};
      final mergedLocalWins = Store.mergeConflict(
        localJson: local,
        remoteJson: remote,
        localWins: true,
      );
      expect(mergedLocalWins['date'], 1000);
    });

    test('id always preserved', () {
      final local = {'id': 'x', 'name': 'Alice'};
      final remote = {'id': 'x', 'name': 'Bob'};
      final merged = Store.mergeConflict(
        localJson: local,
        remoteJson: remote,
        localWins: false,
      );
      expect(merged['id'], 'x');
    });

    test('both sides identical → idempotent merge', () {
      final local = {'id': 'x', 'name': 'Alice', 'age': 30};
      final remote = {'id': 'x', 'name': 'Alice', 'age': 30};
      final merged = Store.mergeConflict(
        localJson: local,
        remoteJson: remote,
        localWins: true,
      );
      expect(merged['name'], 'Alice');
      expect(merged['age'], 30);
      expect(merged.length, 3);
    });

    test('both sides empty (only id) → merged has only id', () {
      final local = {'id': 'x'};
      final remote = {'id': 'x'};
      final merged = Store.mergeConflict(
        localJson: local,
        remoteJson: remote,
        localWins: true,
      );
      expect(merged.length, 1);
      expect(merged['id'], 'x');
    });

    test('archived field treated as scalar LWW', () {
      final local = {'id': 'x', 'archived': true};
      final remote = {'id': 'x', 'name': 'Alice'};
      final merged = Store.mergeConflict(
        localJson: local,
        remoteJson: remote,
        localWins: true,
      );
      // archived only on local → union keeps it.
      expect(merged['archived'], true);
      expect(merged['name'], 'Alice');
    });

    test('archived conflict resolved by LWW', () {
      final local = {'id': 'x', 'archived': true};
      final remote = {'id': 'x', 'archived': false};
      final mergedLocalWins = Store.mergeConflict(
        localJson: local,
        remoteJson: remote,
        localWins: true,
      );
      expect(mergedLocalWins['archived'], true);

      final mergedRemoteWins = Store.mergeConflict(
        localJson: local,
        remoteJson: remote,
        localWins: false,
      );
      expect(mergedRemoteWins['archived'], false);
    });

    test('non-string scalar types (int, bool, double) preserved', () {
      final local = {'id': 'x', 'count': 42, 'active': true, 'rate': 3.14};
      final remote = {'id': 'x', 'count': 99, 'active': false, 'rate': 2.71};
      final merged = Store.mergeConflict(
        localJson: local,
        remoteJson: remote,
        localWins: true,
      );
      expect(merged['count'], 42);
      expect(merged['active'], true);
      expect(merged['rate'], 3.14);
    });

    test('unknown list field (not in special sets) treated as scalar LWW', () {
      // A list field that's not operatorsIDs/tags/prescriptions should
      // fall through to whole-field LWW, not union.
      final local = {
        'id': 'x',
        'customList': ['a', 'b']
      };
      final remote = {
        'id': 'x',
        'customList': ['b', 'c']
      };
      final mergedLocalWins = Store.mergeConflict(
        localJson: local,
        remoteJson: remote,
        localWins: true,
      );
      expect(
          (mergedLocalWins['customList'] as List).cast<String>(), ['a', 'b']);
    });

    test('drawings map: different image annotations survive', () {
      final local = {
        'id': 'x',
        'drawings': {'img1.png': 'drawing-data-1'}
      };
      final remote = {
        'id': 'x',
        'drawings': {'img2.png': 'drawing-data-2'}
      };
      final merged = Store.mergeConflict(
        localJson: local,
        remoteJson: remote,
        localWins: true,
      );
      final drawings = merged['drawings'] as Map<String, dynamic>;
      expect(drawings['img1.png'], 'drawing-data-1');
      expect(drawings['img2.png'], 'drawing-data-2');
    });

    test('teethExtraNotes map: different teeth notes survive', () {
      final local = {
        'id': 'x',
        'teethExtraNotes': {'31': 'note about 31'}
      };
      final remote = {
        'id': 'x',
        'teethExtraNotes': {'38': 'note about 38'}
      };
      final merged = Store.mergeConflict(
        localJson: local,
        remoteJson: remote,
        localWins: false,
      );
      final notes = merged['teethExtraNotes'] as Map<String, dynamic>;
      expect(notes['31'], 'note about 31');
      expect(notes['38'], 'note about 38');
    });

    test('map: mixed same-key and different-key conflicts', () {
      // Key 31: both have it, different values → LWW.
      // Key 38: only remote has it → survives.
      // Key 45: only local has it → survives.
      final local = {
        'id': 'x',
        'teeth': {'31': 'local-crown', '45': 'local-filling'}
      };
      final remote = {
        'id': 'x',
        'teeth': {'31': 'remote-crown', '38': 'remote-filling'}
      };
      final mergedLocalWins = Store.mergeConflict(
        localJson: local,
        remoteJson: remote,
        localWins: true,
      );
      final teeth = mergedLocalWins['teeth'] as Map<String, dynamic>;
      expect(teeth['31'], 'local-crown'); // LWW: local won
      expect(teeth['38'], 'remote-filling'); // remote-only → survives
      expect(teeth['45'], 'local-filling'); // local-only → survives

      final mergedRemoteWins = Store.mergeConflict(
        localJson: local,
        remoteJson: remote,
        localWins: false,
      );
      final teeth2 = mergedRemoteWins['teeth'] as Map<String, dynamic>;
      expect(teeth2['31'], 'remote-crown'); // LWW: remote won
      expect(teeth2['38'], 'remote-filling');
      expect(teeth2['45'], 'local-filling');
    });

    test('map: same key, same value → no conflict, value preserved', () {
      final local = {
        'id': 'x',
        'teeth': {'31': 'crown'}
      };
      final remote = {
        'id': 'x',
        'teeth': {'31': 'crown'}
      };
      final merged = Store.mergeConflict(
        localJson: local,
        remoteJson: remote,
        localWins: true,
      );
      expect((merged['teeth'] as Map)['31'], 'crown');
    });

    test('map: empty on both sides → omitted from merged', () {
      final local = {'id': 'x', 'teeth': <String, String>{}};
      final remote = {'id': 'x', 'teeth': <String, String>{}};
      final merged = Store.mergeConflict(
        localJson: local,
        remoteJson: remote,
        localWins: true,
      );
      expect(merged.containsKey('teeth'), isFalse);
    });

    test('map: empty on one side, non-empty on other → non-empty survives', () {
      final local = {
        'id': 'x',
        'teeth': {'31': 'crown'}
      };
      final remote = {'id': 'x', 'teeth': <String, String>{}};
      final merged = Store.mergeConflict(
        localJson: local,
        remoteJson: remote,
        localWins: false, // remote (empty) wins timestamp
      );
      // Remote deleted all teeth and wins → but union still takes
      // local's keys (known limitation: deletions not preserved).
      final teeth = merged['teeth'] as Map<String, dynamic>;
      expect(teeth['31'], 'crown');
    });

    test('operatorsIDs: empty on both sides → omitted', () {
      final local = {'id': 'x', 'operatorsIDs': <String>[]};
      final remote = {'id': 'x', 'operatorsIDs': <String>[]};
      final merged = Store.mergeConflict(
        localJson: local,
        remoteJson: remote,
        localWins: true,
      );
      expect(merged.containsKey('operatorsIDs'), isFalse);
    });

    test('operatorsIDs: empty on one side → non-empty survives', () {
      final local = {
        'id': 'x',
        'operatorsIDs': ['a', 'b']
      };
      final remote = {'id': 'x', 'operatorsIDs': <String>[]};
      final merged = Store.mergeConflict(
        localJson: local,
        remoteJson: remote,
        localWins: false,
      );
      final ops = (merged['operatorsIDs'] as List).cast<String>().toSet();
      expect(ops, {'a', 'b'});
    });

    test('operatorsIDs: identical on both sides → no duplicates', () {
      final local = {
        'id': 'x',
        'operatorsIDs': ['a', 'b']
      };
      final remote = {
        'id': 'x',
        'operatorsIDs': ['a', 'b']
      };
      final merged = Store.mergeConflict(
        localJson: local,
        remoteJson: remote,
        localWins: true,
      );
      final ops = (merged['operatorsIDs'] as List).cast<String>();
      expect(ops.length, 2);
      expect(ops.toSet(), {'a', 'b'});
    });

    test('prescriptions (LWW list) not merged', () {
      final local = {
        'id': 'x',
        'prescriptions': ['ibuprofen 400mg', 'amoxicillin 500mg']
      };
      final remote = {
        'id': 'x',
        'prescriptions': ['paracetamol 500mg']
      };
      final mergedLocalWins = Store.mergeConflict(
        localJson: local,
        remoteJson: remote,
        localWins: true,
      );
      expect((mergedLocalWins['prescriptions'] as List).cast<String>(),
          ['ibuprofen 400mg', 'amoxicillin 500mg']);

      final mergedRemoteWins = Store.mergeConflict(
        localJson: local,
        remoteJson: remote,
        localWins: false,
      );
      expect((mergedRemoteWins['prescriptions'] as List).cast<String>(),
          ['paracetamol 500mg']);
    });

    test('tags empty on one side, LWW winner is the empty side → omitted', () {
      // If winner deleted all tags (empty list), and it's the only side
      // with the field, LWW takes winner's empty list → omitted (since
      // empty lists are omitted by toJson convention). But here loser
      // also has tags, so winner's empty list wins → tags omitted.
      final local = {
        'id': 'x',
        'tags': ['vip']
      };
      final remote = {'id': 'x', 'tags': <String>[]};
      // Remote wins (empty list) → tags should be taken from remote
      // (empty) → but LWW takes winner's value which is [] → omitted.
      final merged = Store.mergeConflict(
        localJson: local,
        remoteJson: remote,
        localWins: false, // remote wins
      );
      // Remote's tags is [] — LWW takes it. But [] is falsy-ish in our
      // merge: we take winner[key] which is []. It stays as [].
      expect(merged['tags'], []);
    });

    test('imgs: empty on both sides → empty list', () {
      final local = {'id': 'x', 'imgs': <String>[]};
      final remote = {'id': 'x', 'imgs': <String>[]};
      final merged = Store.mergeConflict(
        localJson: local,
        remoteJson: remote,
        localWins: true,
        serverFiles: [],
      );
      expect(merged['imgs'], []);
    });

    test('imgs: only on local, server has them → kept', () {
      final local = {
        'id': 'x',
        'imgs': ['a.png', 'b.png']
      };
      final remote = {'id': 'x'};
      final merged = Store.mergeConflict(
        localJson: local,
        remoteJson: remote,
        localWins: true,
        serverFiles: ['a.png', 'b.png'],
      );
      final imgs = (merged['imgs'] as List).cast<String>().toSet();
      expect(imgs, {'a.png', 'b.png'});
    });

    test('imgs: only on remote, server has them → kept', () {
      final local = {'id': 'x'};
      final remote = {
        'id': 'x',
        'imgs': ['a.png']
      };
      final merged = Store.mergeConflict(
        localJson: local,
        remoteJson: remote,
        localWins: false,
        serverFiles: ['a.png'],
      );
      final imgs = (merged['imgs'] as List).cast<String>().toSet();
      expect(imgs, {'a.png'});
    });

    test('imgs: pending upload also on server → no duplicate', () {
      final local = {
        'id': 'x',
        'imgs': ['a.png']
      };
      final remote = {'id': 'x'};
      // a.png is both on the server AND in pendingUploads.
      final merged = Store.mergeConflict(
        localJson: local,
        remoteJson: remote,
        localWins: true,
        serverFiles: ['a.png'],
        pendingUploads: {'a.png'},
      );
      final imgs = (merged['imgs'] as List).cast<String>();
      expect(imgs.length, 1);
      expect(imgs, ['a.png']);
    });

    test('imgs: all stale (none on server) → empty list', () {
      final local = {
        'id': 'x',
        'imgs': ['old1.png', 'old2.png']
      };
      final remote = {
        'id': 'x',
        'imgs': ['old3.png']
      };
      final merged = Store.mergeConflict(
        localJson: local,
        remoteJson: remote,
        localWins: true,
        serverFiles: [], // server has none of these
      );
      expect(merged['imgs'], []);
    });

    test('dcmImgs with .dicom extension recognized as DICOM', () {
      final local = {
        'id': 'x',
        'dcmImgs': ['scan.dicom']
      };
      final remote = {'id': 'x'};
      // Server has scan.dicom and a regular photo.png.
      final merged = Store.mergeConflict(
        localJson: local,
        remoteJson: remote,
        localWins: true,
        serverFiles: ['scan.dicom', 'photo.png'],
      );
      final dcmImgs = (merged['dcmImgs'] as List).cast<String>().toSet();
      expect(dcmImgs, {'scan.dicom'});
    });

    test('dcmImgs: regular image in dcmImgs list, server has it as non-dcm',
        () {
      // Edge case: a .png filename somehow ends up in dcmImgs.
      // The server has it, but _isNotDcmFileStatic filters it out for
      // the dcmImgs merge. So it should be dropped from dcmImgs.
      final local = {
        'id': 'x',
        'dcmImgs': ['scan.dcm', 'weird.png']
      };
      final remote = {'id': 'x'};
      final merged = Store.mergeConflict(
        localJson: local,
        remoteJson: remote,
        localWins: true,
        serverFiles: ['scan.dcm', 'weird.png'],
      );
      final dcmImgs = (merged['dcmImgs'] as List).cast<String>().toSet();
      // weird.png is not a .dcm file, so it's filtered out of dcmImgs
      // even though the server has it.
      expect(dcmImgs, {'scan.dcm'});
    });

    test('imgs and dcmImgs: mixed server files correctly separated', () {
      final local = {
        'id': 'x',
        'imgs': ['photo.png', 'xray.png'],
        'dcmImgs': ['scan.dcm']
      };
      final remote = {
        'id': 'x',
        'imgs': ['photo.png'],
        'dcmImgs': ['scan.dcm', 'scan2.dcm']
      };
      // Server has: photo.png, xray.png (regular), scan.dcm, scan2.dcm (DICOM)
      final merged = Store.mergeConflict(
        localJson: local,
        remoteJson: remote,
        localWins: true,
        serverFiles: ['photo.png', 'xray.png', 'scan.dcm', 'scan2.dcm'],
      );
      final imgs = (merged['imgs'] as List).cast<String>().toSet();
      final dcmImgs = (merged['dcmImgs'] as List).cast<String>().toSet();
      expect(imgs, {'photo.png', 'xray.png'});
      expect(dcmImgs, {'scan.dcm', 'scan2.dcm'});
    });

    test('imgs: case-insensitive .DCM extension', () {
      final local = {
        'id': 'x',
        'dcmImgs': ['scan.DCM']
      };
      final remote = {'id': 'x'};
      final merged = Store.mergeConflict(
        localJson: local,
        remoteJson: remote,
        localWins: true,
        serverFiles: ['scan.DCM'],
      );
      final dcmImgs = (merged['dcmImgs'] as List).cast<String>().toSet();
      expect(dcmImgs, {'scan.DCM'});
    });

    test('full record: all field strategies in one merge', () {
      // Integration test exercising every strategy at once.
      final local = {
        'id': 'apt1',
        'date': 1000,
        'name': 'local-name', // scalar conflict
        'phone': '555', // scalar only on local
        'teeth': {'31': 'local-crown'}, // map conflict on key 31
        'teethExtraNotes': {'31': 'local-note'},
        'drawings': {'img1.png': 'local-drawing'},
        'operatorsIDs': ['op1', 'op2'],
        'tags': ['vip'],
        'prescriptions': ['med1'],
        'imgs': ['photo.png'],
        'dcmImgs': ['scan.dcm'],
        'archived': true,
      };
      final remote = {
        'id': 'apt1',
        'date': 2000,
        'name': 'remote-name',
        'email': 'a@b.com', // scalar only on remote
        'teeth': {'31': 'remote-crown', '38': 'remote-filling'},
        'teethExtraNotes': {'38': 'remote-note'},
        'drawings': {'img2.png': 'remote-drawing'},
        'operatorsIDs': ['op2', 'op3'],
        'tags': ['allergy'],
        'prescriptions': ['med2'],
        'imgs': ['photo.png', 'photo2.png'],
        'dcmImgs': ['scan.dcm', 'scan2.dcm'],
        'archived': false,
      };

      final merged = Store.mergeConflict(
        localJson: local,
        remoteJson: remote,
        localWins: true,
        serverFiles: ['photo.png', 'photo2.png', 'scan.dcm', 'scan2.dcm'],
      );

      // Scalar LWW (local wins):
      expect(merged['date'], 1000);
      expect(merged['name'], 'local-name');
      expect(merged['archived'], true);
      // Scalar union (only one side has it):
      expect(merged['phone'], '555');
      expect(merged['email'], 'a@b.com');
      // Map per-key union + LWW:
      final teeth = merged['teeth'] as Map<String, dynamic>;
      expect(teeth['31'], 'local-crown'); // LWW: local won
      expect(teeth['38'], 'remote-filling'); // remote-only
      final teethNotes = merged['teethExtraNotes'] as Map<String, dynamic>;
      expect(teethNotes['31'], 'local-note');
      expect(teethNotes['38'], 'remote-note');
      final drawings = merged['drawings'] as Map<String, dynamic>;
      expect(drawings['img1.png'], 'local-drawing');
      expect(drawings['img2.png'], 'remote-drawing');
      // Union list (operatorsIDs):
      final ops = (merged['operatorsIDs'] as List).cast<String>().toSet();
      expect(ops, {'op1', 'op2', 'op3'});
      // LWW list (local wins):
      expect((merged['tags'] as List).cast<String>(), ['vip']);
      expect((merged['prescriptions'] as List).cast<String>(), ['med1']);
      // Image reconciliation:
      final imgs = (merged['imgs'] as List).cast<String>().toSet();
      expect(imgs, {'photo.png', 'photo2.png'});
      final dcmImgs = (merged['dcmImgs'] as List).cast<String>().toSet();
      expect(dcmImgs, {'scan.dcm', 'scan2.dcm'});
    });

    test('full record: all field strategies, remote wins', () {
      // Same as above but remoteWins — verifies LWW symmetry.
      final local = {
        'id': 'apt1',
        'date': 1000,
        'name': 'local-name',
        'phone': '555',
        'teeth': {'31': 'local-crown'},
        'operatorsIDs': ['op1'],
        'tags': ['vip'],
        'imgs': ['photo.png'],
      };
      final remote = {
        'id': 'apt1',
        'date': 2000,
        'name': 'remote-name',
        'email': 'a@b.com',
        'teeth': {'31': 'remote-crown', '38': 'remote-filling'},
        'operatorsIDs': ['op2', 'op3'],
        'tags': ['allergy'],
        'imgs': ['photo.png', 'photo2.png'],
      };

      final merged = Store.mergeConflict(
        localJson: local,
        remoteJson: remote,
        localWins: false,
        serverFiles: ['photo.png', 'photo2.png'],
      );

      // Scalar LWW (remote wins):
      expect(merged['date'], 2000);
      expect(merged['name'], 'remote-name');
      // Scalar union:
      expect(merged['phone'], '555');
      expect(merged['email'], 'a@b.com');
      // Map: LWW for key 31 (remote), union for 38:
      final teeth = merged['teeth'] as Map<String, dynamic>;
      expect(teeth['31'], 'remote-crown');
      expect(teeth['38'], 'remote-filling');
      // Union list:
      final ops = (merged['operatorsIDs'] as List).cast<String>().toSet();
      expect(ops, {'op1', 'op2', 'op3'});
      // LWW list (remote wins):
      expect((merged['tags'] as List).cast<String>(), ['allergy']);
      // Images:
      final imgs = (merged['imgs'] as List).cast<String>().toSet();
      expect(imgs, {'photo.png', 'photo2.png'});
    });

    test('localWins=true and localWins=false produce same union fields', () {
      // Fields that are union-based (scalar one-sided, map different keys,
      // operatorsIDs) should produce the same result regardless of LWW
      // winner. Only LWW-conflicted fields should differ.
      final local = {
        'id': 'x',
        'phone': '555', // union (only local)
        'teeth': {'31': 'local'}, // 31 conflicts, 38 is remote-only
        'operatorsIDs': ['op1'], // union
      };
      final remote = {
        'id': 'x',
        'email': 'a@b.com', // union (only remote)
        'teeth': {'31': 'remote', '38': 'remote-filling'},
        'operatorsIDs': ['op2'],
      };

      final mergedLocal = Store.mergeConflict(
          localJson: local, remoteJson: remote, localWins: true);
      final mergedRemote = Store.mergeConflict(
          localJson: local, remoteJson: remote, localWins: false);

      // Union fields are identical:
      expect(mergedLocal['phone'], mergedRemote['phone']);
      expect(mergedLocal['email'], mergedRemote['email']);
      expect((mergedLocal['operatorsIDs'] as List).toSet(),
          (mergedRemote['operatorsIDs'] as List).toSet());
      // Map: key 38 (remote-only) is identical:
      expect((mergedLocal['teeth'] as Map)['38'],
          (mergedRemote['teeth'] as Map)['38']);
      // Map: key 31 (conflict) differs:
      expect((mergedLocal['teeth'] as Map)['31'], 'local');
      expect((mergedRemote['teeth'] as Map)['31'], 'remote');
    });

    test('empty serverFiles and pendingUploads → all images dropped', () {
      final local = {
        'id': 'x',
        'imgs': ['a.png', 'b.png']
      };
      final remote = {
        'id': 'x',
        'imgs': ['c.png']
      };
      final merged = Store.mergeConflict(
        localJson: local,
        remoteJson: remote,
        localWins: true,
        serverFiles: [],
        pendingUploads: {},
      );
      expect(merged['imgs'], []);
    });

    test('map with non-Map value (malformed) → treated as empty', () {
      // Defensive: if a map field somehow holds a non-Map value,
      // _toStringMap returns {} and the merge doesn't crash.
      final local = {'id': 'x', 'teeth': 'not-a-map'};
      final remote = {
        'id': 'x',
        'teeth': {'31': 'crown'}
      };
      final merged = Store.mergeConflict(
        localJson: local,
        remoteJson: remote,
        localWins: true,
      );
      final teeth = merged['teeth'] as Map<String, dynamic>;
      expect(teeth['31'], 'crown');
    });

    test('list field with non-List value (malformed) → treated as empty', () {
      // Defensive: if a list field holds a non-List value.
      final local = {'id': 'x', 'operatorsIDs': 'not-a-list'};
      final remote = {
        'id': 'x',
        'operatorsIDs': ['op1']
      };
      final merged = Store.mergeConflict(
        localJson: local,
        remoteJson: remote,
        localWins: true,
      );
      final ops = (merged['operatorsIDs'] as List).cast<String>().toSet();
      expect(ops, {'op1'});
    });

    test('merge is pure (does not mutate inputs)', () {
      final local = {
        'id': 'x',
        'name': 'Alice',
        'teeth': {'31': 'crown'}
      };
      final remote = {
        'id': 'x',
        'name': 'Bob',
        'teeth': {'38': 'filling'}
      };
      final localCopy = jsonDecode(jsonEncode(local)) as Map<String, dynamic>;
      final remoteCopy = jsonDecode(jsonEncode(remote)) as Map<String, dynamic>;

      Store.mergeConflict(
        localJson: local,
        remoteJson: remote,
        localWins: true,
      );

      // Inputs should be unchanged.
      expect(jsonEncode(local), jsonEncode(localCopy));
      expect(jsonEncode(remote), jsonEncode(remoteCopy));
    });

    test('no serverFiles provided (default empty) → images dropped', () {
      // When serverFiles is not passed (defaults to const []), all image
      // references are dropped unless they're pending uploads.
      final local = {
        'id': 'x',
        'imgs': ['a.png']
      };
      final remote = {'id': 'x'};
      final merged = Store.mergeConflict(
        localJson: local,
        remoteJson: remote,
        localWins: true,
        pendingUploads: {'a.png'},
      );
      // a.png is a pending upload → kept even without serverFiles.
      final imgs = (merged['imgs'] as List).cast<String>().toSet();
      expect(imgs, {'a.png'});
    });
  });

  group('Store deferred-file helpers', () {
    test('parseDeferredRetries reads the retry segment', () {
      expect(
        Store.parseDeferredRetries('FILE||row||path||photo.png||4'),
        4,
      );
    });

    test('parseDeferredRetries defaults legacy and malformed keys to zero', () {
      expect(Store.parseDeferredRetries('FILE||row||path||photo.png'), 0);
      expect(Store.parseDeferredRetries('FILE||row||path||photo.png||bad'), 0);
      expect(Store.parseDeferredRetries('ordinary-document-id'), 0);
    });

    test('buildDeferredRetryKey appends retries to a legacy file key', () {
      expect(
        Store.buildDeferredRetryKey('FILE||row||path||photo.png', 1),
        'FILE||row||path||photo.png||1',
      );
    });

    test('buildDeferredRetryKey replaces retries without changing key data',
        () {
      expect(
        Store.buildDeferredRetryKey('FILE||row||path||photo.png||2', 3),
        'FILE||row||path||photo.png||3',
      );
    });

    test('filenamesFromDeferred includes upload filenames only', () {
      final filenames = Store.filenamesFromDeferred({
        'FILE||row-a||path-a||upload-a.png||0': 1,
        'FILE||row-b||path-b||upload-b.dcm||3': 1,
        'FILE||row-c||delete-me.png': 0,
        'document-id': 123,
      });

      expect(filenames, {'upload-a.png', 'upload-b.dcm'});
    });

    test('filenamesFromDeferred deduplicates matching upload filenames', () {
      final filenames = Store.filenamesFromDeferred({
        'FILE||a||one||same.png||0': 1,
        'FILE||b||two||same.png||4': 1,
      });

      expect(filenames, {'same.png'});
    });
  });

  group('Store file-model helpers', () {
    late Store<FilePerson> store;

    setUp(() {
      store = Store<FilePerson>(modeling: FilePerson.fromJson);
    });

    test('recognizes DICOM filename extensions case-insensitively', () {
      expect(store.debugIsDcmFile('scan.dcm'), isTrue);
      expect(store.debugIsDcmFile('scan.DICOM'), isTrue);
      expect(store.debugIsDcmFile('scan.dcm.png'), isFalse);
      expect(store.debugIsDcmFile('photo.png'), isFalse);
      expect(store.debugIsDcmFile('no-extension'), isFalse);
    });

    test('patchModelFilename replaces references in imgs and dcmImgs', () {
      final person = FilePerson.fromJson({
        'id': 'file-model',
        'imgs': ['old.png'],
        'dcmImgs': ['old.dcm'],
      });
      store.set(person);

      store.debugPatchModelFilename(person.id, 'old.png', 'new.png');
      store.debugPatchModelFilename(person.id, 'old.dcm', 'new.dcm');

      expect(store.get(person.id)?.id, 'file-model');
      expect(store.get(person.id)?.imgs, ['new.png']);
      expect(store.get(person.id)?.dcmImgs, ['new.dcm']);
    });

    test('cleanDanglingFileRef removes the named image reference only', () {
      final person = FilePerson.fromJson({
        'id': 'clean-file-model',
        'imgs': ['remove.png', 'keep.png'],
        'dcmImgs': ['remove.dcm'],
      });
      store.set(person);

      store.debugCleanDanglingFileRef(person.id, 'remove.png');
      store.debugCleanDanglingFileRef(person.id, 'remove.dcm');

      expect(store.get(person.id)?.imgs, ['keep.png']);
      expect(store.get(person.id)?.dcmImgs, isEmpty);
    });

    test('ensureDcmInModel adds a DICOM filename once', () {
      final person = FilePerson.fromJson({'id': 'ensure-dcm'});
      store.set(person);

      store.debugEnsureDcmInModel(person.id, 'scan.dcm');
      store.debugEnsureDcmInModel(person.id, 'scan.dcm');

      expect(store.get(person.id)?.dcmImgs, ['scan.dcm']);
    });

    test('cleanDanglingFileRef is a no-op for a missing model', () {
      expect(
        () => store.debugCleanDanglingFileRef('missing', 'photo.png'),
        returnsNormally,
      );
    });

    test('ensureDcmInModel is a no-op for a missing model', () {
      expect(
        () => store.debugEnsureDcmInModel('missing', 'scan.dcm'),
        returnsNormally,
      );
    });

    test('notify emits a view-only event without changing documents', () async {
      store.set(FilePerson.fromJson({'id': 'present'}));
      List<DictEvent>? observed;
      store.observableMap.observe((events) => observed = events);

      store.notify();
      await Future<void>.delayed(Duration.zero);

      expect(observed, isNotNull);
      expect(observed!.single.id, '__ignore_view__');
      expect(observed!.single.type, DictEventType.modify);
      expect(store.docs.keys, {'present'});
    });

    test('archive, unarchive, and delete ignore unknown IDs', () {
      store.archive('missing');
      store.unarchive('missing');
      store.delete('missing');

      expect(store.docs, isEmpty);
      expect(store.archived, isEmpty);
    });
  });

  group('Store Tests', () {
    late Store<Person> store;
    final SaveLocal local = TestUtils.local;

    setUp(() async {
      await local.clear();

      store = Store<Person>(
        modeling: Person.fromJson,
        local: local,
        remote: null,
        debounceMS: 100,
      );

      store.observableMap.clear();
      await store.loaded;
      await store.local!.clear();
      await store.deleteMemoryAndLoadFromPersistence();
      // allow for Hive to process the changes
      await Future.delayed(const Duration(milliseconds: 200));
      expect(store.docs.length, equals(0));
      store.init();
    });

    test("store is loaded and modeled", () async {
      await (await local.mainHiveBox).put("id0", '{"id":"id0"}');
      final Store<Person> mStore = Store<Person>(
        modeling: Person.fromJson,
        local: local,
        remote: null,
        debounceMS: 100,
      );
      await mStore.loaded;
      expect(mStore.docs.length, 1);
      expect(mStore.docs.values.first.id, "id0");
      expect(mStore.docs.values.first.age, 100);
      expect(mStore.docs.values.first.name, "alex");
    });

    test("store add method works and calls observers", () async {
      final List<String> observedChangesIds = [];
      store.observableMap.observe((events) {
        observedChangesIds.addAll(events.map((e) => e.id));
      });

      expect(store.docs.length, 0);
      store.set(Person.fromJson({"id": "id1"}));
      expect(store.docs.length, 1);
      expect(store.docs.values.first.id, "id1");
      await Future.delayed(const Duration(milliseconds: 10));
      expect(observedChangesIds.contains("id1"), true);
    });

    test("store setAll method works and calls observers", () async {
      int observerCalled = 0;
      store.observableMap.observe((events) {
        if (events.first.id != "__ignore_view__") observerCalled++;
      });
      expect(store.docs.length, 0);
      store.setAll([
        Person.fromJson({"id": "id1"}),
        Person.fromJson({"id": "id2"})
      ]);
      expect(store.docs.length, 2);
      expect(store.docs.values.first.id, "id1");
      expect(store.docs.values.last.id, "id2");
      await Future.delayed(const Duration(milliseconds: 10));
      expect(observerCalled, 1);
    });

    test("store delete method works and calls observers", () async {
      await store.loaded;
      int observerCalled = 0;
      store.observableMap.observe((events) {
        if (events.first.id != "__ignore_view__") observerCalled++;
      });
      expect(store.docs.length, 0);
      store.set(Person.fromJson({"id": "id1"}));
      expect(store.docs.length, 1);
      store.delete("id1");
      expect(store.docs.length, 1);
      expect(store.docs.values.first.archived, true);
      await Future.delayed(const Duration(milliseconds: 10));
      expect(observerCalled, 2);
    });

    test("store archive method works and calls observers", () async {
      int observerCalled = 0;
      store.observableMap.observe((events) {
        observerCalled++;
      });

      expect(store.docs.length, 0);
      store.set(Person.fromJson({"id": "id1"}));
      expect(store.docs.length, 1);
      store.archive("id1");
      expect(store.docs.length, 1);
      expect(store.docs.values.first.archived, true);
      await Future.delayed(const Duration(milliseconds: 10));
      expect(observerCalled, 2);
    });

    test("store unarchive method works and calls observers", () async {
      int observerCalled = 0;
      store.observableMap.observe((events) {
        observerCalled++;
      });

      expect(store.docs.length, 0);
      store.set(Person.fromJson({"id": "id1"}));
      expect(store.docs.length, 1);
      store.archive("id1");
      expect(store.docs.length, 1);
      expect(store.docs.values.first.archived, true);
      store.unarchive("id1");
      expect(store.docs.length, 1);
      expect(store.docs.values.first.archived, false);
      await Future.delayed(const Duration(milliseconds: 10));
      expect(observerCalled, 3);
    });

    test("store get method works", () async {
      store.setAll([
        Person.fromJson(
            {"id": "id1", "name": "alex", "age": 100, "archived": true}),
        Person.fromJson({"id": "id2", "name": "bob", "age": 200}),
        Person.fromJson({"id": "id3", "name": "charlie", "age": 300}),
      ]);
      expect(store.get("id1")!.name, "alex");
      expect(store.get("id2")!.name, "bob");
      expect(store.get("id3")!.name, "charlie");
      expect(store.get("id4"), null);
    });
    test("store has method works", () async {
      store.setAll([
        Person.fromJson(
            {"id": "id1", "name": "alex", "age": 100, "archived": true}),
        Person.fromJson({"id": "id2", "name": "bob", "age": 200}),
        Person.fromJson({"id": "id3", "name": "charlie", "age": 300}),
      ]);
      expect(store.has("id1"), true);
      expect(store.has("id2"), true);
      expect(store.has("id3"), true);
      expect(store.has("id4"), false);
    });
    test("store present method works", () async {
      store.setAll([
        Person.fromJson(
            {"id": "id1", "name": "alex", "age": 100, "archived": true}),
        Person.fromJson({"id": "id2", "name": "bob", "age": 200}),
        Person.fromJson({"id": "id3", "name": "charlie", "age": 300}),
      ]);
      expect(store.present.length, 2);
      expect(store.present.values.where((e) => e.id == "id1").length, 0);
      expect(store.present.values.where((e) => e.id == "id2").length, 1);
      expect(store.present.values.where((e) => e.id == "id3").length, 1);
    });
    test("store reload method doesn't remove items", () async {
      store.setAll([
        Person.fromJson(
            {"id": "id1", "name": "alex", "age": 100, "archived": true}),
        Person.fromJson({"id": "id2", "name": "bob", "age": 200}),
        Person.fromJson({"id": "id3", "name": "charlie", "age": 300}),
      ]);
      await store.reload();
      expect(store.docs.length, 3);
    });

    test("store reload method works", () async {
      store.setAll([
        Person.fromJson(
            {"id": "id1", "name": "alex", "age": 100, "archived": true}),
        Person.fromJson({"id": "id2", "name": "bob", "age": 200}),
        Person.fromJson({"id": "id3", "name": "charlie", "age": 300}),
      ]);
      await (await local.mainHiveBox).put("id4", '{"id":"id4"}');
      await store.reload();
      expect(store.docs.length, 4);
    });
    test("store reload doesn't inform observers", () async {
      await (await local.mainHiveBox).put("id4", '{"id":"id4"}');
      int observersCalled = 0;
      store.observableMap.observe((events) {
        if (events.first.id != "__ignore_view__") observersCalled++;
      });
      await store.reload();
      await Future.delayed(const Duration(milliseconds: 10));
      expect(observersCalled, 0);
    });
  });

  group('Store synchronization tests', () {
    late Store<Person> store;
    late SaveLocal local = TestUtils.local;
    late SaveRemote remote = TestUtils.remote;
    final PocketBase pb = TestUtils.pb;

    setUpAll(() async {
      await TestUtils.resetServer();
    });

    setUp(() async {
      remote.isOnline = true;
      await local.clear();
      await pb.collections.truncate("data");
      expect((await remote.getSince(version: 0)).rows, isEmpty);
      expect((await local.getDeferred()), isEmpty);

      store = Store<Person>(
        modeling: Person.fromJson,
        local: local,
        remote: remote,
        debounceMS: 100,
        manualSyncOnly: true,
      );

      store.observableMap.clear();
      await store.loaded;
      await store.local!.clear();
      await store.deleteMemoryAndLoadFromPersistence();
      // allow for Hive to process the changes
      await Future.delayed(const Duration(milliseconds: 200));
      expect(store.docs.length, equals(0));
      expect(await store.local!.getVersion(), 0);
      expect((await local.getAll()), isEmpty);
      store.init();
    });

    test("deferredPresent is true when there are deferred updates", () async {
      remote.isOnline = false;
      store.set(Person.fromJson({}));
      await store.waitUntilChangesAreProcessed();
      expect(store.deferredPresent, isTrue);
      remote.isOnline = true;
    });

    test("automatic: local additions to remote", () async {
      expect((await remote.getSince(version: 0)).rows.length, equals(0));
      expect((await remote.getSince(version: 0)).version, equals(0));
      store.set(Person.fromJson({}));
      await store.waitUntilChangesAreProcessed();
      expect((await remote.getSince(version: 0)).rows.length, equals(1));
      expect((await remote.getSince(version: 0)).version, greaterThan(0));

      // synchronization check
      // version is only updated through synchronization
      expect(await store.local!.getVersion(), equals(0));
      var sync = await store.synchronize();
      expect(sync.length, equals(2));
      expect(sync[0].exception, equals(null));
      expect(sync[0].pushed, 0);
      expect(sync[0].pulled, 1);
      expect(sync[1].exception, equals("nothing to sync"));
      expect(await local.getVersion(), equals(await remote.getVersion()));
    });
    test("automatic: local deletes to remote", () async {
      store.set(Person.fromJson({}));
      await store.waitUntilChangesAreProcessed();
      expect((await remote.getSince(version: 0)).rows.length, equals(1));
      store.delete(store.docs.values.first.id);
      await store.waitUntilChangesAreProcessed();
      var remoteRows = await remote.getSince(version: 0);
      expect(remoteRows.rows.length, equals(1));
      expect(remoteRows.rows[0].id, equals(store.docs.values.first.id));
      expect(remoteRows.rows[0].data, contains('"archived":true'));
      // synchronization check
      // version is only updated through synchronization
      expect(await local.getVersion(), equals(0));
      var sync = await store.synchronize();
      expect(sync.length, equals(2));
      expect(sync[0].exception, equals(null));
      expect(sync[0].pushed, 0);
      expect(sync[0].pulled, 1);
      expect(sync[1].exception, equals("nothing to sync"));
      expect(await local.getVersion(), equals(await remote.getVersion()));
    });
    test("automatic: local modifications to remote", () async {
      store.set(Person.fromJson({}));
      await store.waitUntilChangesAreProcessed();
      expect((await remote.getSince(version: 0)).rows.length, equals(1));
      store.set(store.docs.values.first..age = 18);
      await store.waitUntilChangesAreProcessed();
      var remoteRows = await remote.getSince(version: 0);
      expect(remoteRows.rows.length, equals(1));
      expect(remoteRows.rows[0].id, equals(store.docs.values.first.id));
      expect(remoteRows.rows[0].data, contains('"age":18'));

      // synchronization check
      // version is only updated through synchronization
      expect(await local.getVersion(), equals(0));
      var sync = await store.synchronize();
      expect(sync.length, equals(2));
      expect(sync[0].exception, equals(null));
      expect(sync[0].pushed, 0);
      expect(sync[0].pulled, 1);
      expect(sync[1].exception, equals("nothing to sync"));
      expect(await local.getVersion(), equals(await remote.getVersion()));
    });
    test("on sync: send deferred additions", () async {
      remote.isOnline = false;
      store.set(Person.fromJson({}));
      await store.waitUntilChangesAreProcessed();
      expect((await remote.getSince(version: 0)).rows.length, equals(0));
      remote.isOnline = true;

      expect(await remote.getVersion(), equals(0));

      // synchronization check
      expect(await local.getVersion(), equals(0));
      var sync = await store.synchronize();
      expect(sync.length, equals(3));
      expect(sync[0].exception, equals(null));
      expect(sync[0].pushed, 1);
      expect(sync[0].pulled, 0);
      expect(sync[1].pushed, 0);
      expect(sync[1].pulled, 1);
      expect(sync[2].exception, equals("nothing to sync"));
      expect(await local.getVersion(), equals(await remote.getVersion()));
    });

    test("on sync: send deferred deletions", () async {
      store.set(Person.fromJson({}));
      await store.waitUntilChangesAreProcessed();
      await store.synchronize();
      var remoteVersion = await remote.getVersion();
      var localVersion = await local.getVersion();

      remote.isOnline = false;
      store.delete(store.docs.values.first.id);
      await store.waitUntilChangesAreProcessed();
      expect(
          (await remote.getSince(version: 0)).version, equals(remoteVersion));
      expect((await remote.getSince(version: 0)).version, equals(localVersion));
      remote.isOnline = true;

      expect(await remote.getVersion(), equals(remoteVersion));

      // synchronization check
      expect(await local.getVersion(), equals(localVersion));
      var sync = await store.synchronize();
      expect(sync.length, equals(3));
      expect(sync[0].exception, equals(null));
      expect(sync[0].pushed, 1);
      expect(sync[0].pulled, 0);
      expect(sync[1].pushed, 0);
      expect(sync[1].pulled, 1);
      expect(sync[2].exception, equals("nothing to sync"));
      expect(await local.getVersion(), greaterThan(localVersion));
      expect(await remote.getVersion(), equals(await local.getVersion()));
    });

    test("on sync: send deferred modifications", () async {
      store.set(Person.fromJson({}));
      await store.waitUntilChangesAreProcessed();
      await store.synchronize();
      var remoteVersion = await remote.getVersion();
      var localVersion = await local.getVersion();

      remote.isOnline = false;
      store.set(store.docs.values.first..age = 11);
      await store.waitUntilChangesAreProcessed();
      expect(
          (await remote.getSince(version: 0)).version, equals(remoteVersion));
      expect((await remote.getSince(version: 0)).version, equals(localVersion));
      remote.isOnline = true;

      expect(await remote.getVersion(), equals(remoteVersion));

      // synchronization check
      expect(await local.getVersion(), equals(localVersion));
      var sync = await store.synchronize();
      expect(sync.length, equals(3));
      expect(sync[0].exception, equals(null));
      expect(sync[0].pushed, 1);
      expect(sync[0].pulled, 0);
      expect(sync[1].pushed, 0);
      expect(sync[1].pulled, 1);
      expect(sync[2].exception, equals("nothing to sync"));
      expect(await local.getVersion(), greaterThan(localVersion));
      expect(await remote.getVersion(), equals(await local.getVersion()));
    });

    test("when there's deferred, all events will be deferred until sync",
        () async {
      store.set(Person.fromJson({}));
      await store.waitUntilChangesAreProcessed();
      await store.synchronize();
      var remoteVersion = await remote.getVersion();
      var localVersion = await local.getVersion();

      remote.isOnline = false;
      store.set(store.docs.values.first..age = 11);
      await store.waitUntilChangesAreProcessed();
      expect(
          (await remote.getSince(version: 0)).version, equals(remoteVersion));
      expect((await remote.getSince(version: 0)).version, equals(localVersion));
      remote.isOnline = true;
      await store.waitUntilChangesAreProcessed();

      store.set(Person.fromJson({}));
      store.set(Person.fromJson({}));
      store.set(Person.fromJson({}));

      await store.waitUntilChangesAreProcessed();
      expect((await local.getDeferred()).length, equals(4));
    });

    test("deferred changes must keep only the latest changes", () async {
      store.set(Person.fromJson({}));
      await store.waitUntilChangesAreProcessed();
      await store.synchronize();
      var remoteVersion = await remote.getVersion();
      var localVersion = await local.getVersion();

      remote.isOnline = false;
      store.set(store.docs.values.first..age = 11);
      await store.waitUntilChangesAreProcessed();
      expect(
          (await remote.getSince(version: 0)).version, equals(remoteVersion));
      expect((await remote.getSince(version: 0)).version, equals(localVersion));
      remote.isOnline = true;
      await store.waitUntilChangesAreProcessed();

      store.set(Person.fromJson({}));
      store.delete(store.docs.values.toList()[0].id);
      store.set(store.docs.values.toList()[1]..age = 12);

      store.set(Person.fromJson({}));
      store.set(Person.fromJson({}));

      await store.waitUntilChangesAreProcessed();
      expect((await local.getDeferred()).length, equals(4));
    });

    test("remote additions to local", () async {
      final id1 = uuid();
      final id2 = uuid();
      final id3 = uuid();

      await remote.put([
        RowToWriteRemotely(
            id: id1, data: '{"id": "$id1", "name": "name1", "age": 11}'),
        RowToWriteRemotely(
            id: id2, data: '{"id": "$id2", "name": "name2", "age": 12}'),
        RowToWriteRemotely(
            id: id3, data: '{"id": "$id3", "name": "name3", "age": 13}'),
      ]);

      var sync = await store.synchronize();
      expect(sync.length, equals(2));
      expect(sync[0].exception, equals(null));
      expect(sync[0].pushed, 0);
      expect(sync[0].pulled, 3);
      expect(sync[1].exception, "nothing to sync");

      final docsList = store.docs.values.toList()
        ..sort((a, b) => a.name.compareTo(b.name));

      expect(docsList.length, equals(3));
      expect(docsList[0].id, equals(id1));
      expect(docsList[0].name, equals("name1"));
      expect(docsList[0].age, equals(11));
      expect(docsList[1].id, equals(id2));
      expect(docsList[1].name, equals("name2"));
      expect(docsList[1].age, equals(12));
      expect(docsList[2].id, equals(id3));
      expect(docsList[2].name, equals("name3"));
      expect(docsList[2].age, equals(13));
    });
    test("remote deletes to local", () async {
      final id1 = uuid();
      final id2 = uuid();
      final id3 = uuid();
      await remote.put([
        RowToWriteRemotely(
            id: id1, data: '{"id": "$id1", "name": "name1", "age": 11}'),
        RowToWriteRemotely(
            id: id2, data: '{"id": "$id2", "name": "name2", "age": 12}'),
        RowToWriteRemotely(
            id: id3, data: '{"id": "$id3", "name": "name3", "age": 13}'),
      ]);

      await store.synchronize();

      expect(store.docs.values.toList()[0].archived, equals(null));
      expect(store.docs.values.toList()[1].archived, equals(null));

      await remote.put([
        RowToWriteRemotely(
            id: id1,
            data:
                '{"id": "$id1", "name": "name1", "age": 11, "archived": true}'),
        RowToWriteRemotely(
            id: id2,
            data:
                '{"id": "$id2", "name": "name2", "age": 12, "archived": false}'),
      ]);

      var sync = await store.synchronize();
      expect(sync.length, equals(2));
      expect(sync[0].exception, equals(null));
      expect(sync[0].pushed, 0);
      expect(sync[0].pulled, 2);
      expect(sync[1].exception, "nothing to sync");

      expect(store.get(id1)?.archived, equals(true));
      expect(store.get(id2)?.archived, equals(false));
      expect(store.get(id3)?.archived, equals(null));
    });

    test("remote modifications to local", () async {
      final id1 = uuid();
      final id2 = uuid();
      final id3 = uuid();
      await remote.put([
        RowToWriteRemotely(
            id: id1, data: '{"id": "$id1", "name": "name1", "age": 11}'),
        RowToWriteRemotely(
            id: id2, data: '{"id": "$id2", "name": "name2", "age": 12}'),
        RowToWriteRemotely(
            id: id3, data: '{"id": "$id3", "name": "name3", "age": 13}'),
      ]);

      await store.synchronize();

      expect(store.get(id1)?.age, equals(11));
      expect(store.get(id2)?.age, equals(12));

      await remote.put([
        RowToWriteRemotely(
            id: id1, data: '{"id": "$id1", "name": "name1", "age": 111}'),
        RowToWriteRemotely(
            id: id2, data: '{"id": "$id2", "name": "name2", "age": 112}'),
      ]);

      var sync = await store.synchronize();
      expect(sync.length, equals(2));
      expect(sync[0].exception, equals(null));
      expect(sync[0].pushed, 0);
      expect(sync[0].pulled, 2);
      expect(sync[1].exception, "nothing to sync");

      expect(store.get(id1)?.age, equals(111));
      expect(store.get(id2)?.age, equals(112));
    });

    test("bi-directional", () async {
      final id0 = uuid();
      final id1 = uuid();
      final id2 = uuid();
      final id3 = uuid();

      remote.isOnline = false;
      store.set(Person.fromJson({"id": id0}));
      await Future.delayed(const Duration(seconds: 1));

      await store.waitUntilChangesAreProcessed();

      await remote.put([
        RowToWriteRemotely(
            id: id1, data: '{"id": "$id1", "name": "name1", "age": 11}'),
        RowToWriteRemotely(
            id: id2, data: '{"id": "$id2", "name": "name2", "age": 12}'),
        RowToWriteRemotely(
            id: id3, data: '{"id": "$id3", "name": "name3", "age": 13}'),
      ]);

      remote.isOnline = true;
      await store.waitUntilChangesAreProcessed();

      var sync = await store.synchronize();
      expect(sync.length, equals(3));
      expect(sync[0].exception, equals(null));
      expect(sync[0].pushed, 1);
      expect(sync[0].pulled, 3);
      expect(sync[1].exception, equals(null));
      expect(sync[1].pushed, 0);
      expect(sync[1].pulled, 1);
      expect(sync[2].exception, "nothing to sync");

      expect(store.get(id0), isNotNull);
      expect(store.get(id1), isNotNull);
      expect(store.get(id2), isNotNull);
      expect(store.get(id3), isNotNull);
    });
    test("bi-directional with conflicts (local winners)", () async {
      final id1 = uuid();
      final id2 = uuid();
      final id3 = uuid();
      await remote.put([
        RowToWriteRemotely(
            id: id1, data: '{"id": "$id1", "name": "name1", "age": 11}'),
        RowToWriteRemotely(
            id: id2, data: '{"id": "$id2", "name": "name2", "age": 12}'),
        RowToWriteRemotely(
            id: id3, data: '{"id": "$id3", "name": "name3", "age": 13}'),
      ]);
      await Future.delayed(const Duration(seconds: 1));
      await store.waitUntilChangesAreProcessed();
      remote.isOnline = false;
      store
          .set(Person.fromJson({"id": id2, "name": "modified-name", "age": 0}));
      await store.waitUntilChangesAreProcessed();
      remote.isOnline = true;
      var sync = await store.synchronize();

      // --- Deterministic invariants (do not depend on which side wins) ---
      expect(sync, isNotEmpty);
      expect(sync[0].exception, equals(null));
      expect(sync[0].conflicts, equals(1));
      expect(sync.last.exception, equals("nothing to sync"));

      // id1 and id3 are remote-only (no conflict) → remote value.
      expect(store.get(id1)?.name, equals("name1"));
      expect(store.get(id3)?.name, equals("name3"));

      // id2 conflicted. With field-level merge:
      // - `name`: both sides have a non-default value that differs →
      //   LWW. The local change was made ~1s after the remote put, so
      //   on a clock-synced machine local wins → "modified-name".
      //   (If the local clock is behind, remote wins → "name2".)
      // - `age`: both sides have a non-default value (local 0, remote 12)
      //   that differs → LWW (same winner as `name`).
      final id2Name = store.get(id2)?.name;
      final id2Age = store.get(id2)?.age;
      // Both fields conflict and resolve by the same LWW winner.
      if (id2Name == "modified-name") {
        // Local won → age should be local's 0.
        expect(id2Age, equals(0),
            reason: 'local won LWW → age should be local value 0');
      } else {
        // Remote won → age should be remote's 12.
        expect(id2Name, equals("name2"),
            reason: 'expected local or remote name, got $id2Name');
        expect(id2Age, equals(12),
            reason: 'remote won LWW → age should be remote value 12');
      }
      expect(store.docs.length, equals(3));
    });
    test("bi-directional with conflicts (remote winners)", () async {
      remote.isOnline = false;
      final id1 = uuid();
      final id2 = uuid();
      final id3 = uuid();

      store.set(Person.fromJson({"id": id1, "age": 11}));
      await store.waitUntilChangesAreProcessed();

      await Future.delayed(const Duration(seconds: 1));
      await remote.put([
        RowToWriteRemotely(
            id: id1, data: '{"id": "$id1", "name": "name1", "age": 111}'),
        RowToWriteRemotely(
            id: id2, data: '{"id": "$id2", "name": "name2", "age": 12}'),
        RowToWriteRemotely(
            id: id3, data: '{"id": "$id3", "name": "name3", "age": 13}'),
      ]);

      remote.isOnline = true;
      await store.waitUntilChangesAreProcessed();

      var sync = await store.synchronize();

      // --- Deterministic invariants (do not depend on which side wins) ---
      //
      // The conflict count is the number of IDs present in BOTH the
      // deferred set and the remote updates — it does not depend on
      // timestamps, so it is always 1 here (id1).
      expect(sync, isNotEmpty);
      expect(sync[0].exception, equals(null));
      expect(sync[0].conflicts, equals(1));
      // Sync always converges to "nothing to sync".
      expect(sync.last.exception, equals("nothing to sync"));

      // id2 and id3 are remote-only (no conflict) → always take the
      // remote value.
      expect(store.get(id2)?.age, equals(12));
      expect(store.get(id3)?.age, equals(13));

      // id1 conflicted. With field-level merge:
      // - `name`: only the remote side has it (local JSON omits it) →
      //   union takes "name1".  Deterministic regardless of clock skew.
      // - `age`: both sides have a non-default value (local 11, remote
      //   111) that differs → LWW.  The winner depends on the sub-second
      //   cross-clock race (see note above).
      expect(store.get(id1)?.name, equals("name1"),
          reason: 'name should be "name1" — only the remote side set it, so '
              'union merge preserves it regardless of LWW winner');
      final id1Age = store.get(id1)?.age;
      expect(id1Age == 11 || id1Age == 111, isTrue,
          reason: 'id1 age should be either the local (11) or remote (111) '
              'value after LWW conflict resolution, got $id1Age');
      expect(store.docs.length, equals(3));
    });
    test("bi-directional with conflicts (some local and some remote winners)",
        () async {
      remote.isOnline = false;
      final id1 = uuid();
      final id2 = uuid();
      final id3 = uuid();
      final id4 = uuid();
      store.set(Person.fromJson({"id": id1, "name": "local-1"}));
      await store.waitUntilChangesAreProcessed();
      await Future.delayed(const Duration(seconds: 1));
      await remote.put([
        RowToWriteRemotely(
            id: id1, data: '{"id": "$id1", "name": "remote-1", "age": 111}'),
        RowToWriteRemotely(
            id: id2, data: '{"id": "$id2", "name": "remote-2", "age": 12}'),
        RowToWriteRemotely(
            id: id3, data: '{"id": "$id3", "name": "remote-3", "age": 13}'),
      ]);

      remote.isOnline = true;
      store.set(Person.fromJson({"id": id3, "name": "local-3"}));
      store.set(Person.fromJson({"id": id4, "name": "local-4-newly-added"}));

      await store.waitUntilChangesAreProcessed();

      var sync = await store.synchronize();

      // --- Deterministic invariants (do not depend on which side wins) ---
      //
      // The conflict count is the number of IDs present in BOTH the
      // deferred set and the remote updates — it does not depend on
      // timestamps, so it is always 2 here (id1 and id3).
      expect(sync, isNotEmpty);
      expect(sync[0].exception, equals(null));
      expect(sync[0].conflicts, equals(2));
      // Sync always converges to "nothing to sync".
      expect(sync.last.exception, equals("nothing to sync"));

      // id2 is remote-only and id4 is local-only (no conflicts) →
      // always take their respective values.
      expect(store.get(id2)?.name, equals("remote-2"));
      expect(store.get(id4)?.name, equals("local-4-newly-added"));

      // id1 and id3 conflicted. With field-level merge:
      // - `name`: both sides have a non-default value that differs →
      //   LWW (sub-second cross-clock race, see note above).
      // - `age`: only the remote side set it (local JSON omits it) →
      //   union takes the remote value.  Deterministic regardless of
      //   clock skew.
      expect(store.get(id1)?.age, equals(111),
          reason: 'id1 age should be 111 — only the remote side set it, so '
              'union merge preserves it regardless of LWW winner');
      expect(store.get(id3)?.age, equals(13),
          reason: 'id3 age should be 13 — only the remote side set it, so '
              'union merge preserves it regardless of LWW winner');
      final id1Name = store.get(id1)?.name;
      expect(id1Name == "local-1" || id1Name == "remote-1", isTrue,
          reason: 'id1 name should be either the local or remote value after '
              'LWW conflict resolution, got $id1Name');
      final id3Name = store.get(id3)?.name;
      expect(id3Name == "local-3" || id3Name == "remote-3", isTrue,
          reason: 'id3 name should be either the local or remote value after '
              'LWW conflict resolution, got $id3Name');
      expect(store.docs.length, equals(4));
    });

    test("inSync methods correctly tells whether the store is in sync",
        () async {
      final id1 = uuid();
      final id2 = uuid();
      final id3 = uuid();
      await remote.put([
        RowToWriteRemotely(
            id: id1, data: '{"id": "$id1", "name": "name1", "age": 111}'),
        RowToWriteRemotely(
            id: id2, data: '{"id": "$id2", "name": "name2", "age": 12}'),
        RowToWriteRemotely(
            id: id3, data: '{"id": "$id3", "name": "name3", "age": 13}'),
      ]);
      await Future.delayed(const Duration(seconds: 1));
      expect(await store.inSync(), equals(false));
      await store.synchronize();
      expect(await store.inSync(), equals(true));
      store
          .set(Person.fromJson({"id": id1, "name": "modified-name", "age": 0}));
      await store.waitUntilChangesAreProcessed();
      expect(await store.inSync(), equals(false));
      await store.synchronize();
      expect(await store.inSync(), equals(true));
    });

    test("onSyncStart/onSyncEnd functions are called", () async {
      final id1 = uuid();
      final id2 = uuid();
      final id3 = uuid();

      int startCount = 0;
      int endCount = 0;

      store = Store(
        remote: remote,
        local: local,
        modeling: Person.fromJson,
        manualSyncOnly: true,
        onSyncStart: () {
          startCount++;
        },
        onSyncEnd: () {
          endCount++;
        },
      );
      store.init();
      await store.loaded;

      store
          .set(Person.fromJson({"id": id1, "name": "modified-name", "age": 0}));
      await store.waitUntilChangesAreProcessed();
      await remote.put([
        RowToWriteRemotely(
            id: id1, data: '{"id": "$id1", "name": "name1", "age": 111}'),
        RowToWriteRemotely(
            id: id2, data: '{"id": "$id2", "name": "name2", "age": 12}'),
        RowToWriteRemotely(
            id: id3, data: '{"id": "$id3", "name": "name3", "age": 13}'),
      ]);
      await store.synchronize();

      await store.waitUntilChangesAreProcessed();

      expect(startCount, equals(2));
      expect(endCount, equals(2));
    });

    test("Non-manual sync, on modification", () async {
      final store2 = Store(
        remote: remote,
        local: local,
        modeling: Person.fromJson,
        debounceMS: 100,
      );
      store2.init();
      await store2.loaded;

      final id = uuid();

      store2.set(Person.fromJson({"id": id}));
      expect(store2.docs.length, equals(1));
      await store2.waitUntilChangesAreProcessed();
      final remoteRes = (await remote.getSince(version: 0)).rows;
      expect(remoteRes.length, equals(1));
      expect(remoteRes.first.id, equals(id));
    });

    test("Realtime subscription", () async {
      final store2 = Store(
        remote: remote,
        local: local,
        modeling: Person.fromJson,
        debounceMS: 100,
      );
      store2.init();
      await store2.loaded;
      await store2.synchronize(); // setting up realtime requires a sync request

      final id = uuid();
      await remote.put([RowToWriteRemotely(id: id, data: '{"id": "$id"}')]);

      await Future.delayed(const Duration(milliseconds: 6000));

      expect(store2.docs.length, equals(1));
      expect(store2.docs.values.first.id, equals(id));
    });
  });
}

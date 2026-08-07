import 'dart:io';

import 'package:apexo/core/model.dart';
import 'package:apexo/core/save_local.dart';
import 'package:apexo/core/save_remote.dart';
import 'package:apexo/core/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:pocketbase/pocketbase.dart';
import '../../helpers/hive_setup.dart';

/// Minimal model for testing Store's deferred helpers.
class _TestModel extends Model {
  List<String> imgs = [];
  List<String> dcmImgs = [];

  _TestModel.fromJson(super.json) : super.fromJson();

  @override
  _TestModel copy(bool blank) => _TestModel.fromJson(blank ? {} : toJson());

  @override
  void fromJson(Map<String, dynamic> json) {
    super.fromJson(json);
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

/// A Store subclass that exposes private helpers for testing.
class _TestStore extends Store<_TestModel> {
  _TestStore() : super(modeling: _TestModel.fromJson);
}

class _SyncTestStore extends Store<_TestModel> {
  _SyncTestStore({required SaveLocal local, required SaveRemote remote})
      : super(
          modeling: _TestModel.fromJson,
          local: local,
          remote: remote,
          manualSyncOnly: true,
        );
}

class _SyncTestRemote extends SaveRemote {
  final int version;
  final VersionedResult updates;
  bool failUpload = false;

  _SyncTestRemote({required this.version, required this.updates})
      : super(
          storeName: 'test',
          pbInstance: PocketBase('http://fake-pocketbase'),
        );

  @override
  Future<int> getVersion() async => version;

  @override
  Future<VersionedResult> getSince({int version = 0}) async => updates;

  @override
  Future<String> uploadImage({
    required String rowID,
    required String filename,
    String? path,
    XFile? file,
    http.MultipartFile? predefinedMultipart,
  }) async {
    if (failUpload) throw StateError('upload unavailable');
    return filename;
  }
}

void main() {
  // ── _isDcmFile ──────────────────────────────────────────────────────

  group('Store._isDcmFile', () {
    late _TestStore store;

    setUp(() {
      store = _TestStore();
    });

    test('matches .dcm files (case-insensitive)', () {
      expect(store.debugIsDcmFile('scan.dcm'), isTrue);
      expect(store.debugIsDcmFile('scan.DCM'), isTrue);
      expect(store.debugIsDcmFile('scan.Dcm'), isTrue);
    });

    test('matches .dicom files', () {
      expect(store.debugIsDcmFile('scan.dicom'), isTrue);
      expect(store.debugIsDcmFile('scan.DICOM'), isTrue);
    });

    test('rejects non-DCM files', () {
      expect(store.debugIsDcmFile('scan.png'), isFalse);
      expect(store.debugIsDcmFile('scan.jpg'), isFalse);
      expect(store.debugIsDcmFile('scan.dcm.png'), isFalse);
      expect(store.debugIsDcmFile(''), isFalse);
    });
  });

  // ── _cleanDanglingFileRef ───────────────────────────────────────────

  group('Store._cleanDanglingFileRef', () {
    late _TestStore store;
    late String rowID;

    setUp(() {
      store = _TestStore();
      final model = _TestModel.fromJson({});
      rowID = model.id;
      model.imgs = ['a.jpg', 'bad.dcm'];
      model.dcmImgs = ['bad.dcm', 'good.dcm'];
      store.set(model);
    });

    test('removes filename from both imgs and dcmImgs', () {
      store.debugCleanDanglingFileRef(rowID, 'bad.dcm');

      final m = store.get(rowID)!;
      expect(m.imgs, ['a.jpg']);
      expect(m.dcmImgs, ['good.dcm']);
    });

    test('no-op when model not found', () {
      store.debugCleanDanglingFileRef('nonexistent', 'bad.dcm');
      // Should not throw.
    });

    test('no-op when filename not in lists', () {
      store.debugCleanDanglingFileRef(rowID, 'nonexistent.dcm');
      final m = store.get(rowID)!;
      expect(m.imgs, ['a.jpg', 'bad.dcm']);
      expect(m.dcmImgs, ['bad.dcm', 'good.dcm']);
    });

    test('removes only one duplicate reference from each field', () {
      final m = store.get(rowID)!;
      m.imgs = ['bad.dcm', 'bad.dcm'];
      m.dcmImgs = ['bad.dcm', 'bad.dcm'];
      store.set(m);

      store.debugCleanDanglingFileRef(rowID, 'bad.dcm');

      expect(store.get(rowID)!.imgs, ['bad.dcm']);
      expect(store.get(rowID)!.dcmImgs, ['bad.dcm']);
    });

    test('removes field from JSON when list becomes empty', () {
      final special = _TestModel.fromJson({});
      special.dcmImgs = ['only.dcm'];
      store.set(special);
      store.debugCleanDanglingFileRef(special.id, 'only.dcm');

      final m = store.get(special.id)!;
      expect(m.dcmImgs, isEmpty);
    });

    test('invokes onFileDeadLettered callback for DCM files', () {
      final received = <String>[];
      void cb(String f) => received.add(f);
      Store.onFileDeadLettered.add(cb);

      store.debugCleanDanglingFileRef(rowID, 'bad.dcm');

      expect(received, ['bad.dcm']);

      Store.onFileDeadLettered.remove(cb);
    });

    test('does NOT invoke onFileDeadLettered for non-DCM files', () {
      final received = <String>[];
      void cb(String f) => received.add(f);
      Store.onFileDeadLettered.add(cb);

      store.debugCleanDanglingFileRef(rowID, 'a.jpg');

      expect(received, isEmpty);

      Store.onFileDeadLettered.remove(cb);
    });
  });

  // ── _patchModelFilename ─────────────────────────────────────────────

  group('Store._patchModelFilename', () {
    late _TestStore store;
    late String rowID;

    setUp(() {
      store = _TestStore();
      final model = _TestModel.fromJson({});
      rowID = model.id;
      model.imgs = ['old_name.dcm', 'other.jpg'];
      model.dcmImgs = ['old_name.dcm'];
      store.set(model);
    });

    test('replaces old filename with new in both imgs and dcmImgs', () {
      store.debugPatchModelFilename(rowID, 'old_name.dcm', 'new_name.dcm');

      final m = store.get(rowID)!;
      expect(m.imgs, ['new_name.dcm', 'other.jpg']);
      expect(m.dcmImgs, ['new_name.dcm']);
    });

    test('no-op when old filename not found', () {
      store.debugPatchModelFilename(rowID, 'nonexistent.dcm', 'new.dcm');

      final m = store.get(rowID)!;
      expect(m.imgs, ['old_name.dcm', 'other.jpg']);
    });

    test('patches only the first duplicate in each field', () {
      final m = store.get(rowID)!;
      m.imgs = ['old_name.dcm', 'old_name.dcm'];
      m.dcmImgs = ['old_name.dcm', 'old_name.dcm'];
      store.set(m);

      store.debugPatchModelFilename(rowID, 'old_name.dcm', 'new_name.dcm');

      expect(store.get(rowID)!.imgs, ['new_name.dcm', 'old_name.dcm']);
      expect(store.get(rowID)!.dcmImgs, ['new_name.dcm', 'old_name.dcm']);
    });

    test('no-op when model not found', () {
      // Should not throw.
      store.debugPatchModelFilename('nonexistent', 'old.dcm', 'new.dcm');
    });
  });

  // ── _ensureDcmInModel ───────────────────────────────────────────────

  group('Store._ensureDcmInModel', () {
    late _TestStore store;
    late String rowID;

    setUp(() {
      store = _TestStore();
      final model = _TestModel.fromJson({});
      rowID = model.id;
      store.set(model);
    });

    test('adds pbName to empty dcmImgs', () {
      store.debugEnsureDcmInModel(rowID, 'scan.dcm');

      final m = store.get(rowID)!;
      expect(m.dcmImgs, ['scan.dcm']);
    });

    test('adds pbName when not already present', () {
      final model = store.get(rowID)!;
      model.dcmImgs = ['existing.dcm'];
      store.set(model);

      store.debugEnsureDcmInModel(rowID, 'scan.dcm');

      final m = store.get(rowID)!;
      expect(m.dcmImgs, ['existing.dcm', 'scan.dcm']);
    });

    test('does NOT duplicate when pbName already present', () {
      final model = store.get(rowID)!;
      model.dcmImgs = ['scan.dcm'];
      store.set(model);

      store.debugEnsureDcmInModel(rowID, 'scan.dcm');

      final m = store.get(rowID)!;
      expect(m.dcmImgs, ['scan.dcm']);
    });

    test('no-op when model not found', () {
      // Should not throw.
      store.debugEnsureDcmInModel('nonexistent', 'scan.dcm');
    });
  });

  // ── Duplicate prevention (Fix 2) ────────────────────────────────────

  group('PB rename duplicate prevention', () {
    late _TestStore store;
    late String rowID;

    setUp(() {
      store = _TestStore();
      final model = _TestModel.fromJson({});
      rowID = model.id;
      model.dcmImgs = ['xray.dcm']; // original local name
      store.set(model);
    });

    test('_patchModelFilename then _ensureDcmInModel does NOT create duplicate',
        () {
      // Simulate: PB renamed xray.dcm → xray_a1b2.dcm
      // Step 1: patch old→new
      store.debugPatchModelFilename(rowID, 'xray.dcm', 'xray_a1b2.dcm');

      // Step 2: ensure DCM in model (should be no-op since already there)
      store.debugEnsureDcmInModel(rowID, 'xray_a1b2.dcm');

      final m = store.get(rowID)!;
      expect(m.dcmImgs.length, 1);
      expect(m.dcmImgs, ['xray_a1b2.dcm']);
    });
  });

  // ── isValidDeferredFileKey ──────────────────────────────────────────

  group('Store.isValidDeferredFileKey', () {
    test('accepts legacy and retry upload keys', () {
      expect(
        Store.isValidDeferredFileKey('FILE||row||C:/file||scan.dcm', 1),
        isTrue,
      );
      expect(
        Store.isValidDeferredFileKey('FILE||row||C:/file||scan.dcm||3', 1),
        isTrue,
      );
    });

    test('accepts three-segment delete keys only', () {
      expect(Store.isValidDeferredFileKey('FILE||row||scan.dcm', 0), isTrue);
      expect(Store.isValidDeferredFileKey('FILE||row||path||scan.dcm', 0),
          isFalse);
    });

    test('rejects malformed, unsupported, and negative-retry keys', () {
      expect(Store.isValidDeferredFileKey('FILE||row', 1), isFalse);
      expect(
          Store.isValidDeferredFileKey('FILE||||path||scan.dcm', 1), isFalse);
      expect(Store.isValidDeferredFileKey('FILE||row||path||scan.dcm||-1', 1),
          isFalse);
      expect(Store.isValidDeferredFileKey('FILE||row||scan.dcm', 2), isFalse);
    });

    test('rejects missing upload filename and missing upload path', () {
      expect(Store.isValidDeferredFileKey('FILE||row||path||', 1), isFalse);
      expect(Store.isValidDeferredFileKey('FILE||||scan.dcm', 1), isFalse);
      expect(Store.isValidDeferredFileKey('FILE||row||', 0), isFalse);
      expect(Store.isValidDeferredFileKey('FILE||||scan.dcm', 0), isFalse);
    });

    test('rejects extra upload segments and malformed retry values', () {
      expect(
          Store.isValidDeferredFileKey(
              'FILE||row||path||scan.dcm||1||extra', 1),
          isFalse);
      expect(
          Store.isValidDeferredFileKey(
              'FILE||row||path||scan.dcm||not-a-number', 1),
          isFalse);
      expect(Store.isValidDeferredFileKey('FILE||row||path||scan.dcm||', 1),
          isFalse);
      expect(
          Store.isValidDeferredFileKey('FILE||row||file||extra', 0), isFalse);
    });

    test('accepts zero and positive retry counts only', () {
      for (final retry in [0, 1, 999999]) {
        expect(
          Store.isValidDeferredFileKey('FILE||row||path||scan.dcm||$retry', 1),
          isTrue,
        );
      }
      expect(Store.isValidDeferredFileKey('FILE||row||path||scan.dcm||-0', 1),
          isTrue);
    });
  });

  // ── parseDeferredRetries ────────────────────────────────────────────

  group('Store.parseDeferredRetries', () {
    test('returns 0 for legacy 4-segment key', () {
      expect(Store.parseDeferredRetries('FILE||row1||/p/a||scan.dcm'), 0);
    });

    test('returns parsed retries for 5-segment key', () {
      expect(Store.parseDeferredRetries('FILE||row1||/p/a||scan.dcm||3'), 3);
    });

    test('returns 0 for invalid retries value', () {
      expect(Store.parseDeferredRetries('FILE||row1||/p/a||scan.dcm||bad'), 0);
    });

    test('returns 0 for 3-segment delete key', () {
      expect(Store.parseDeferredRetries('FILE||row1||someFile'), 0);
    });

    test('accepts malformed and extra-segment keys without throwing', () {
      expect(Store.parseDeferredRetries(''), 0);
      expect(Store.parseDeferredRetries('DOC||row||path||name||9'), 9);
      expect(Store.parseDeferredRetries('FILE||row||path||name||-1'), -1);
    });

    test('parses only the retry segment and ignores later malformed segments',
        () {
      expect(Store.parseDeferredRetries('FILE||row||path||name||7||extra'), 7);
      expect(Store.parseDeferredRetries('FILE||row||path||name||'), 0);
      expect(Store.parseDeferredRetries('FILE||row||path||name||-0'), 0);
    });
  });

  // ── buildDeferredRetryKey ───────────────────────────────────────────

  group('Store.buildDeferredRetryKey', () {
    test('increments retries on 5-segment key', () {
      final result =
          Store.buildDeferredRetryKey('FILE||row1||/p/a||scan.dcm||2', 3);
      expect(result, 'FILE||row1||/p/a||scan.dcm||3');
    });

    test('migrates 4-segment key to 5-segment', () {
      final result =
          Store.buildDeferredRetryKey('FILE||row1||/p/a||scan.dcm', 1);
      expect(result, 'FILE||row1||/p/a||scan.dcm||1');
    });

    test('handles retries=0', () {
      final result =
          Store.buildDeferredRetryKey('FILE||row1||/p/a||scan.dcm||5', 0);
      expect(result, 'FILE||row1||/p/a||scan.dcm||0');
    });

    test('replaces only the retry slot on a key with extra segments', () {
      final result = Store.buildDeferredRetryKey(
          'FILE||row1||/p/a||scan.dcm||5||extra', 8);
      expect(result, 'FILE||row1||/p/a||scan.dcm||8||extra');
    });

    test('adds a retry slot to short or delete-shaped keys without throwing',
        () {
      expect(Store.buildDeferredRetryKey('FILE||row1||scan.dcm', 1),
          'FILE||row1||scan.dcm||1');
      expect(Store.buildDeferredRetryKey('', 2), '||2');
    });
  });

  // ── filenamesFromDeferred ───────────────────────────────────────────

  group('Store.filenamesFromDeferred', () {
    test('extracts filenames from upload entries (value=1)', () {
      final deferred = {
        'FILE||row1||/p/a||scan.dcm||0': 1, // upload
        'FILE||row2||/p/b||xray.dcm||2': 1, // upload
        'FILE||row3||/p/c||photo.jpg||0': 1, // upload
      };
      final result = Store.filenamesFromDeferred(deferred);
      expect(result, {'scan.dcm', 'xray.dcm', 'photo.jpg'});
    });

    test('excludes delete entries (value=0)', () {
      final deferred = {
        'FILE||row1||/p/a||scan.dcm||0': 1, // upload
        'FILE||row2||oldFile': 0, // delete (3-segment)
        'FILE||row3||/p/b||xray.dcm||1': 0, // delete (value=0)
      };
      final result = Store.filenamesFromDeferred(deferred);
      expect(result, {'scan.dcm'});
    });

    test('skips non-FILE keys', () {
      final deferred = {
        'FILE||row1||/p/a||scan.dcm||0': 1,
        'DOC||someDoc': 12345,
      };
      final result = Store.filenamesFromDeferred(deferred);
      expect(result, {'scan.dcm'});
    });

    test('3-segment delete key produces empty string', () {
      final deferred = {
        'FILE||row1||oldFile': 0, // delete: 3 segments, no filename
      };
      final result = Store.filenamesFromDeferred(deferred);
      expect(result, isEmpty);
    });

    test('malformed upload keys are ignored rather than producing filenames',
        () {
      final deferred = {
        'FILE||row1||path||valid.dcm||0': 1,
        'FILE||row1||path||': 1,
        'FILE||row1||path||too-many||1||extra': 1,
        'FILE||row1||path||negative.dcm||-1': 1,
      };

      expect(Store.filenamesFromDeferred(deferred), {'valid.dcm'});
    });

    test('empty deferred → empty set', () {
      expect(Store.filenamesFromDeferred({}), isEmpty);
    });
  });

  // ── filenamesFromDeferredForRow ─────────────────────────────────────

  group('Store.filenamesFromDeferredForRow', () {
    test('returns only upload filenames for the requested row', () {
      final deferred = {
        'FILE||row1||C:/one||same.dcm||0': 1,
        'FILE||row2||C:/two||same.dcm||0': 1,
        'FILE||row1||old.dcm': 0,
        'DOC||row1': 1,
      };

      expect(
        Store.filenamesFromDeferredForRow(deferred, 'row1'),
        {'same.dcm'},
      );
      expect(
        Store.filenamesFromDeferredForRow(deferred, 'row2'),
        {'same.dcm'},
      );
      expect(Store.filenamesFromDeferredForRow(deferred, 'missing'), isEmpty);
    });

    test('does not accept delete entries as pending uploads', () {
      final deferred = {
        'FILE||row1||old.dcm': 0,
        'FILE||row1||C:/one||new.dcm||1': 1,
      };

      expect(
        Store.filenamesFromDeferredForRow(deferred, 'row1'),
        {'new.dcm'},
      );
    });

    test('does not confuse a prefix row ID with the requested row', () {
      final deferred = {
        'FILE||row1||C:/one||one.dcm||0': 1,
        'FILE||row10||C:/ten||ten.dcm||0': 1,
      };

      expect(Store.filenamesFromDeferredForRow(deferred, 'row1'), {'one.dcm'});
    });

    test('ignores malformed and delete entries for the requested row', () {
      final deferred = {
        'FILE||row||C:/valid||valid.dcm': 1,
        'FILE||row||C:/valid||retry.dcm||3': 1,
        'FILE||row||C:/bad||': 1,
        'FILE||row||C:/bad||extra.dcm||1||extra': 1,
        'FILE||row||delete.dcm': 0,
      };

      expect(Store.filenamesFromDeferredForRow(deferred, 'row'),
          {'valid.dcm', 'retry.dcm'});
    });

    test('row IDs containing separator characters do not overmatch', () {
      final deferred = {
        'FILE||row||child||path||child.dcm||0': 1,
        'FILE||row||C:/exact||exact.dcm||0': 1,
      };

      expect(Store.filenamesFromDeferredForRow(deferred, 'row'), {'exact.dcm'});
    });
  });

  group('Store.uploadImg deferred file-only handling', () {
    late Directory hiveDirectory;
    late SaveLocal local;
    late _SyncTestRemote remote;
    late _SyncTestStore store;

    setUp(() async {
      hiveDirectory = await setupTestHive();
      local = SaveLocal(
        name: 'file-only-upload',
        uniqueId: DateTime.now().microsecondsSinceEpoch.toString(),
        storagePath: hiveDirectory.path,
      );
      remote = _SyncTestRemote(
        version: 1,
        updates: VersionedResult(1, const []),
      )..isOnline = false;
      store = _SyncTestStore(local: local, remote: remote);
      await store.loaded;
    });

    tearDown(() async {
      remote.timer?.cancel();
      await local.dispose();
      await teardownTestHive(hiveDirectory);
    });

    test('file-only deferred upload is accepted and survives retry parsing',
        () async {
      final source = File('${hiveDirectory.path}/source.bin');
      await source.writeAsBytes([1, 2, 3]);
      final result = await store.uploadImg(
        rowID: 'row-file',
        filename: 'photo.png',
        file: XFile(source.path),
      );

      expect(result, 'photo.png');
      final deferred = await local.getDeferred();
      expect(deferred, {
        'FILE||row-file||${source.path}||photo.png||0': 1,
      });
      expect(
        Store.isValidDeferredFileKey(
            'FILE||row-file||${source.path}||photo.png||0', 1),
        isTrue,
      );
    });

    test('file-only deferred upload is processed on sync without path IO',
        () async {
      final source = File('${hiveDirectory.path}/source.bin');
      await source.writeAsBytes([1, 2, 3]);
      await local.putDeferred({
        'FILE||row-file||${source.path}||photo.png||0': 1,
      });
      remote.isOnline = true;

      final result = await store.debugSyncTry();

      expect(result.exception, isNull);
      expect(await local.getDeferred(), isEmpty);
    });
  });

  group('Store synchronization deferred-entry handling', () {
    late Directory hiveDirectory;
    late SaveLocal local;
    late _SyncTestStore store;
    late _SyncTestRemote remote;

    setUp(() async {
      hiveDirectory = await setupTestHive();
      local = SaveLocal(
        name: 'deferred-sync',
        uniqueId: DateTime.now().microsecondsSinceEpoch.toString(),
        storagePath: hiveDirectory.path,
      );
      remote = _SyncTestRemote(
        version: 1,
        updates: VersionedResult(1, const []),
      );
      store = _SyncTestStore(local: local, remote: remote);
      await store.loaded;
      await local.putVersion(0);
      await local.putDeferred({
        'FILE||row||path||valid.dcm||0': 1,
        'FILE||row||||file-only.dcm||0': 1,
        'FILE||row||path||too-many.dcm||1||extra': 1,
      });
    });

    tearDown(() async {
      remote.timer?.cancel();
      await local.dispose();
      await teardownTestHive(hiveDirectory);
    });

    test('discards malformed FILE entries without aborting the sync pass',
        () async {
      final result = await store.debugSyncTry();

      expect(result.exception, isNull);
      // The valid uploads are attempted and re-queued because their test
      // sources are intentionally unavailable; malformed entries are
      // discarded rather than aborting the synchronization pass.
      expect(await local.getDeferred(), {
        'FILE||row||path||valid.dcm||1': 1,
      });
    });
  });

  // ── onFileDeadLettered callback ─────────────────────────────────────

  group('Store.onFileDeadLettered', () {
    tearDown(() {
      Store.onFileDeadLettered.clear();
    });

    test('starts empty', () {
      expect(Store.onFileDeadLettered, isEmpty);
    });

    test('supports multiple registered callbacks', () {
      final calls = <String>[];
      Store.onFileDeadLettered.add((f) => calls.add('A:$f'));
      Store.onFileDeadLettered.add((f) => calls.add('B:$f'));

      for (final cb
          in List<void Function(String)>.from(Store.onFileDeadLettered)) {
        cb('test.dcm');
      }

      expect(calls, ['A:test.dcm', 'B:test.dcm']);
    });

    test('callback can remove itself while production snapshot iteration runs',
        () {
      final calls = <String>[];
      late void Function(String) selfRemoving;
      selfRemoving = (filename) {
        calls.add('self:$filename');
        Store.onFileDeadLettered.remove(selfRemoving);
      };
      Store.onFileDeadLettered.add(selfRemoving);
      Store.onFileDeadLettered.add((filename) => calls.add('other:$filename'));

      final model = _TestModel.fromJson({});
      model.dcmImgs = ['retry.dcm'];
      final store = _TestStore()..set(model);
      store.debugCleanDanglingFileRef(model.id, 'retry.dcm');

      expect(calls, ['self:retry.dcm', 'other:retry.dcm']);
      expect(Store.onFileDeadLettered, hasLength(1));
    });

    test('missing model rows still notify DICOM dead-letter callbacks', () {
      final calls = <String>[];
      Store.onFileDeadLettered.add(calls.add);

      final store = _TestStore();
      store.debugCleanDanglingFileRef('missing-row', 'missing.dcm');

      expect(calls, ['missing.dcm']);
    });

    test('dead-letter callback is not invoked for DICOM preview filenames', () {
      final calls = <String>[];
      Store.onFileDeadLettered.add(calls.add);

      final store = _TestStore();
      store.debugCleanDanglingFileRef('missing-row', 'missing.dcm.png');

      expect(calls, isEmpty);
    });

    test('can be cleared', () {
      Store.onFileDeadLettered.add((_) {});
      expect(Store.onFileDeadLettered, isNotEmpty);
      Store.onFileDeadLettered.clear();
      expect(Store.onFileDeadLettered, isEmpty);
    });
  });
}

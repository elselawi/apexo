import 'package:apexo/core/save_remote.dart';
import 'package:apexo/utils/uuid.dart';
import 'package:http/http.dart';
import 'package:pocketbase/pocketbase.dart';
import "package:test/test.dart";
import '../../test_utils.dart';

void main() {
  int savedVersion1 = 0;
  int savedVersion2 = 0;
  int savedVersion3 = 0;
  String savedId = "";
  group("Save Remote", () {
    final SaveRemote saveRemote = TestUtils.remote;
    final PocketBase pb = TestUtils.pb;

    setUpAll(() async {
      await TestUtils.resetServer();
    });

    test("checkOnline", () async {
      await saveRemote.checkOnline();
      expect(saveRemote.isOnline, true);
    });

    test("initially the version should be 0", () async {
      expect(await saveRemote.getVersion(), 0);
    });

    test("put/get data remotely", () async {
      final data = [RowToWriteRemotely(id: uuid(), data: '{"key": "value1"}')];
      await saveRemote.put(data);
      final result = await saveRemote.getSince();
      expect(result.rows, isNotEmpty);
      expect(result.rows.first.data, '{"key":"value1"}');
      expect(result.version, greaterThan(0));
    });

    test("getting version should give an updated version number representing the date", () async {
      final version = await saveRemote.getVersion();
      expect(version, greaterThan(0));
      final versionDate = DateTime.fromMillisecondsSinceEpoch(version);
      final now = DateTime.now();
      expect(versionDate.year, now.year);
      expect(versionDate.month, now.month);
      expect(versionDate.day, now.day);
      savedVersion1 = version; // for test below
    });

    test("Putting again should give a new version", () async {
      final data = [RowToWriteRemotely(id: uuid(), data: '{"key": "value2"}')];
      await saveRemote.put(data);
      final nv = await saveRemote.getVersion();
      expect(nv, greaterThan(savedVersion1));
      savedVersion2 = nv; // for test below
    });

    test("Each version should give different result", () async {
      final data = [RowToWriteRemotely(id: uuid(), data: '{"key": "value3"}')];
      await saveRemote.put(data);
      savedVersion3 = await saveRemote.getVersion();
      expect(savedVersion3, greaterThan(savedVersion2));
      expect(savedVersion2, greaterThan(savedVersion1));

      final result0 = await saveRemote.getSince(version: 0);
      final result1 = await saveRemote.getSince(version: savedVersion1);
      final result2 = await saveRemote.getSince(version: savedVersion2);
      final result3 = await saveRemote.getSince(version: savedVersion3);

      expect(result0.rows, isNotEmpty);
      expect(result1.rows, isNotEmpty);
      expect(result2.rows, isNotEmpty);
      expect(result3.rows, isEmpty);

      expect(result0.rows.length, greaterThan(result1.rows.length));
      expect(result1.rows.length, greaterThan(result2.rows.length));
      expect(result2.rows.length, greaterThan(result3.rows.length));

      expect(result0.rows.length, equals(3));
      expect(result1.rows.length, equals(2));
      expect(result2.rows.length, equals(1));
      expect(result3.rows.length, equals(0));

      expect(result0.rows.where((item) => item.data == '{"key":"value1"}').length, equals(1));
      expect(result0.rows.where((item) => item.data == '{"key":"value2"}').length, equals(1));
      expect(result0.rows.where((item) => item.data == '{"key":"value3"}').length, equals(1));

      expect(result1.rows.where((item) => item.data == '{"key":"value1"}').length, equals(0));
      expect(result1.rows.where((item) => item.data == '{"key":"value2"}').length, equals(1));
      expect(result1.rows.where((item) => item.data == '{"key":"value3"}').length, equals(1));

      expect(result2.rows.where((item) => item.data == '{"key":"value1"}').length, equals(0));
      expect(result2.rows.where((item) => item.data == '{"key":"value2"}').length, equals(0));
      expect(result2.rows.where((item) => item.data == '{"key":"value3"}').length, equals(1));

      expect(result3.rows.where((item) => item.data == '{"key":"value1"}').length, equals(0));
      expect(result3.rows.where((item) => item.data == '{"key":"value2"}').length, equals(0));
      expect(result3.rows.where((item) => item.data == '{"key":"value3"}').length, equals(0));

      savedId = result0.rows.first.id; // for test below
    });

    test("uploading images", () async {
      // uploading
      await saveRemote.uploadImage(savedId, MultipartFile.fromString("imgs+", "content", filename: "file1.txt"));
      // version should be modified
      final version = await saveRemote.getVersion();
      expect(version, greaterThan(savedVersion3));
      // getting the image
      final record = await pb.collection("data").getOne(savedId);
      // making sure the image is there
      expect(List<String>.from(record.data["imgs"]).where((item) => item.contains("file1")).length, 1);
      // getting the image through getSince
      await saveRemote.getSince(version: savedVersion3);
      // for test below
      savedVersion3 = version;
    });
    test("appending one more image", () async {
      // uploading
      await saveRemote.uploadImage(savedId, MultipartFile.fromString("imgs+", "content", filename: "file2.txt"));
      // version should be modified
      final version = await saveRemote.getVersion();
      expect(version, greaterThan(savedVersion3));
      // getting the image
      final record = await pb.collection("data").getOne(savedId);
      // making sure the image is there
      expect(List<String>.from(record.data["imgs"]).where((item) => item.contains("file2")).length, 1);
      // as well as the old one
      expect(List<String>.from(record.data["imgs"]).where((item) => item.contains("file1")).length, 1);
      // getting the image through getSince
      await saveRemote.getSince(version: savedVersion3);
      // for test below
      savedVersion3 = version;
    });
    test("trying to append an image but its duplicated", () async {
      // uploading
      await saveRemote.uploadImage(savedId, MultipartFile.fromString("imgs+", "content", filename: "file1.txt"));
      // version should not be modified
      final version = await saveRemote.getVersion();
      expect(version, equals(savedVersion3));
      // getting the image
      final record = await pb.collection("data").getOne(savedId);
      // making sure the image is there
      expect(List<String>.from(record.data["imgs"]).where((item) => item.contains("file1")).length, 1);
      // as well as the other one
      expect(List<String>.from(record.data["imgs"]).where((item) => item.contains("file2")).length, 1);
      // getting the image through getSince
      await saveRemote.getSince(version: savedVersion3);
    });
    test("trying to append multiple images, some of which is duplicated, others are not", () async {
      await saveRemote.uploadImage(savedId, MultipartFile.fromString("imgs+", "content", filename: "file1.txt"));
      await saveRemote.uploadImage(savedId, MultipartFile.fromString("imgs+", "content", filename: "file2.txt"));
      await saveRemote.uploadImage(savedId, MultipartFile.fromString("imgs+", "content", filename: "file3.txt"));
      await saveRemote.uploadImage(savedId, MultipartFile.fromString("imgs+", "content", filename: "file4.txt"));
      final record = await pb.collection("data").getOne(savedId);
      expect(List<String>.from(record.data["imgs"]).length, equals(4));
      expect(List<String>.from(record.data["imgs"]).where((item) => item.contains("file1")).length, 1);
      expect(List<String>.from(record.data["imgs"]).where((item) => item.contains("file2")).length, 1);
      expect(List<String>.from(record.data["imgs"]).where((item) => item.contains("file3")).length, 1);
      expect(List<String>.from(record.data["imgs"]).where((item) => item.contains("file4")).length, 1);
    });
    test("trying to append multiple images, all of which are duplicated", () async {
      await saveRemote.uploadImage(savedId, MultipartFile.fromString("imgs+", "content", filename: "file1.txt"));
      await saveRemote.uploadImage(savedId, MultipartFile.fromString("imgs+", "content", filename: "file2.txt"));
      await saveRemote.uploadImage(savedId, MultipartFile.fromString("imgs+", "content", filename: "file3.txt"));
      await saveRemote.uploadImage(savedId, MultipartFile.fromString("imgs+", "content", filename: "file4.txt"));
      final record = await pb.collection("data").getOne(savedId);
      expect(List<String>.from(record.data["imgs"]).length, equals(4));
      expect(List<String>.from(record.data["imgs"]).where((item) => item.contains("file1")).length, 1);
      expect(List<String>.from(record.data["imgs"]).where((item) => item.contains("file2")).length, 1);
      expect(List<String>.from(record.data["imgs"]).where((item) => item.contains("file3")).length, 1);
      expect(List<String>.from(record.data["imgs"]).where((item) => item.contains("file4")).length, 1);
    });
    test("trying to append multiple images, none of which are duplicated", () async {
      await saveRemote.uploadImage(savedId, MultipartFile.fromString("imgs+", "content", filename: "file5.txt"));
      await saveRemote.uploadImage(savedId, MultipartFile.fromString("imgs+", "content", filename: "file6.txt"));
      await saveRemote.uploadImage(savedId, MultipartFile.fromString("imgs+", "content", filename: "file7.txt"));
      await saveRemote.uploadImage(savedId, MultipartFile.fromString("imgs+", "content", filename: "file8.txt"));
      final record = await pb.collection("data").getOne(savedId);
      expect(List<String>.from(record.data["imgs"]).length, equals(8));
      expect(List<String>.from(record.data["imgs"]).where((item) => item.contains("file1")).length, 1);
      expect(List<String>.from(record.data["imgs"]).where((item) => item.contains("file2")).length, 1);
      expect(List<String>.from(record.data["imgs"]).where((item) => item.contains("file3")).length, 1);
      expect(List<String>.from(record.data["imgs"]).where((item) => item.contains("file4")).length, 1);
      expect(List<String>.from(record.data["imgs"]).where((item) => item.contains("file5")).length, 1);
      expect(List<String>.from(record.data["imgs"]).where((item) => item.contains("file6")).length, 1);
      expect(List<String>.from(record.data["imgs"]).where((item) => item.contains("file7")).length, 1);
      expect(List<String>.from(record.data["imgs"]).where((item) => item.contains("file8")).length, 1);
    });
    test("removing one image", () async {
      await saveRemote.deleteImage(savedId, "file1.txt");
      final record = await pb.collection("data").getOne(savedId);
      expect(List<String>.from(record.data["imgs"]).length, equals(7));
      expect(List<String>.from(record.data["imgs"]).where((item) => item.contains("file1")).length, 0);
      expect(List<String>.from(record.data["imgs"]).where((item) => item.contains("file2")).length, 1);
      expect(List<String>.from(record.data["imgs"]).where((item) => item.contains("file3")).length, 1);
      expect(List<String>.from(record.data["imgs"]).where((item) => item.contains("file4")).length, 1);
      expect(List<String>.from(record.data["imgs"]).where((item) => item.contains("file5")).length, 1);
      expect(List<String>.from(record.data["imgs"]).where((item) => item.contains("file6")).length, 1);
      expect(List<String>.from(record.data["imgs"]).where((item) => item.contains("file7")).length, 1);
      expect(List<String>.from(record.data["imgs"]).where((item) => item.contains("file8")).length, 1);
    });
    test("removing one image, but it doesn't exist", () async {
      await saveRemote.deleteImage(savedId, "file1.txt");
      final record = await pb.collection("data").getOne(savedId);
      expect(List<String>.from(record.data["imgs"]).length, equals(7));
      expect(List<String>.from(record.data["imgs"]).where((item) => item.contains("file1")).length, 0);
      expect(List<String>.from(record.data["imgs"]).where((item) => item.contains("file2")).length, 1);
      expect(List<String>.from(record.data["imgs"]).where((item) => item.contains("file3")).length, 1);
      expect(List<String>.from(record.data["imgs"]).where((item) => item.contains("file4")).length, 1);
      expect(List<String>.from(record.data["imgs"]).where((item) => item.contains("file5")).length, 1);
      expect(List<String>.from(record.data["imgs"]).where((item) => item.contains("file6")).length, 1);
      expect(List<String>.from(record.data["imgs"]).where((item) => item.contains("file7")).length, 1);
      expect(List<String>.from(record.data["imgs"]).where((item) => item.contains("file8")).length, 1);
    });
    test("removing multiple images, one of which doesn't exist", () async {
      await saveRemote.deleteImage(savedId, "file1.txt");
      await saveRemote.deleteImage(savedId, "file7.txt");
      await saveRemote.deleteImage(savedId, "file8.txt");
      final record = await pb.collection("data").getOne(savedId);
      expect(List<String>.from(record.data["imgs"]).length, equals(5));
      expect(List<String>.from(record.data["imgs"]).where((item) => item.contains("file1")).length, 0);
      expect(List<String>.from(record.data["imgs"]).where((item) => item.contains("file2")).length, 1);
      expect(List<String>.from(record.data["imgs"]).where((item) => item.contains("file3")).length, 1);
      expect(List<String>.from(record.data["imgs"]).where((item) => item.contains("file4")).length, 1);
      expect(List<String>.from(record.data["imgs"]).where((item) => item.contains("file5")).length, 1);
      expect(List<String>.from(record.data["imgs"]).where((item) => item.contains("file6")).length, 1);
      expect(List<String>.from(record.data["imgs"]).where((item) => item.contains("file7")).length, 0);
      expect(List<String>.from(record.data["imgs"]).where((item) => item.contains("file8")).length, 0);
    });
    test("removing all images", () async {
      await saveRemote.deleteImage(savedId, "file2.txt");
      await saveRemote.deleteImage(savedId, "file3.txt");
      await saveRemote.deleteImage(savedId, "file4.txt");
      await saveRemote.deleteImage(savedId, "file5.txt");
      await saveRemote.deleteImage(savedId, "file6.txt");
      final record = await pb.collection("data").getOne(savedId);
      expect(List<String>.from(record.data["imgs"]).length, equals(0));
    });

    // TODO: test after implementing bulk upserts
    // test("upload/get large data", () async {
    //   int initialVersion = await saveRemote.getVersion();
    //   List<RowToWriteRemotely> largeData = [];
    //   for (int i = 0; i < 3500; i++) {
    //     largeData.add(RowToWriteRemotely(id: uuid(), data: '{"key": "value$i"}'));
    //   }
    //   await saveRemote.put(largeData);

    //   int laterVersion = await saveRemote.getVersion();
    //   expect(laterVersion, greaterThan(initialVersion));

    //   var res = await saveRemote.getSince(version: initialVersion);
    //   expect(res.version, greaterThan(initialVersion));
    //   expect(res.rows.length, equals(largeData.length));
    // }, timeout: const Timeout(Duration(minutes: 2)));
  });
}

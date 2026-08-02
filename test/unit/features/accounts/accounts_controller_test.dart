import 'package:flutter_test/flutter_test.dart';
import 'package:apexo/services/admins.dart';
import 'package:apexo/services/login.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../secret.dart';

void main() {
  group('Admins Service Tests', () {
    const testEmail = 'test_admin@example.com';
    const testPassword = 'test123456';
    String createdAdminId = '';

    setUpAll(() async {
      // Initialize PocketBase with your test server
      login.pb = PocketBase(testPBServer);

      // Login as admin first
      await login.pb!.collection("_superusers").authWithPassword(testPBEmail, testPBPassword);
      login.token = login.pb!.authStore.token;
      final allAdmins = await login.pb!.collection("_superusers").getFullList();
      for (var admin in allAdmins) {
        if (admin.data['email'] != testPBEmail) {
          await login.pb!.collection("_superusers").delete(admin.id);
        }
      }
    });

    test('Create new admin', () async {
      await admins.newAdmin(testEmail, testPassword);
      await admins.reloadFromRemote();
      expect(admins.creating(), false);
      expect(admins.errorMessage(), '');

      final adminsList = admins.list();
      final createdAdmin = adminsList.firstWhere((admin) => admin.data['email'] == testEmail);

      createdAdminId = createdAdmin.id;
      expect(createdAdmin.data['email'], equals(testEmail));
    });

    test('Update admin', () async {
      const newEmail = 'updated_admin@example.com';
      await admins.update(createdAdminId, newEmail, '');

      expect(admins.updating()[createdAdminId], null);
      expect(admins.errorMessage(), '');

      final adminsList = admins.list();
      final updatedAdmin = adminsList.firstWhere((admin) => admin.id == createdAdminId);

      expect(updatedAdmin.data['email'], equals(newEmail));
    });

    test('Reload from remote', () async {
      await admins.reloadFromRemote();

      expect(admins.loaded(), true);
      expect(admins.loading(), false);
      expect(admins.list().isNotEmpty, true);
    });

    test('Delete admin', () async {
      final adminToDelete = admins.list().firstWhere((admin) => admin.id == createdAdminId);

      await admins.delete(adminToDelete);

      expect(admins.deleting()[createdAdminId], null);
      expect(admins.list().where((admin) => admin.id == createdAdminId).isEmpty, true);
    });

    test('Error handling with invalid data', () async {
      await admins.newAdmin('invalid-email', 'short');

      expect(admins.errorMessage().isNotEmpty, true);
      expect(admins.creating(), false);
    });
  });
}

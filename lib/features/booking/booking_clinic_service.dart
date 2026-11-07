import 'dart:async';
import 'dart:convert';

import 'package:apexo/features/booking/booking_api.dart';
import 'package:apexo/features/booking/booking_canonical.dart';
import 'package:apexo/features/booking/booking_models.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/utils/constants.dart';
import 'package:apexo/utils/init_pocketbase.dart';
import 'package:pocketbase/pocketbase.dart';

/// A locally persisted enrollment/rotation/recovery attempt. PocketBase enforces
/// the JSON field's size, not its shape, so this is the typed allowlist.
class BookingPendingOperation {
  BookingPendingOperation({
    required this.action,
    required this.handle,
    required this.clinicId,
    required this.serverUrl,
    required this.challenge,
    required this.adminKey,
    required this.inboxKey,
    this.initialConfig,
  });

  final String action; // register | rotate | recover
  final String handle;
  final String clinicId;
  final String serverUrl;
  final String challenge;
  final String adminKey;
  final String inboxKey;
  final BookingClinicConfig? initialConfig;

  Map<String, Object?> toJson() => {
        "action": action,
        "handle": handle,
        "clinicId": clinicId,
        "serverUrl": serverUrl,
        "challenge": challenge,
        "adminKey": adminKey,
        "inboxKey": inboxKey,
        "initialConfig": initialConfig?.toJson(),
      };

  Map<String, Object?> toOperationBody() => {
        "action": action,
        "handle": handle,
        "clinicId": clinicId,
        "serverUrl": serverUrl,
        "challenge": challenge,
        "adminKey": adminKey,
        "inboxKey": inboxKey,
        "initialConfig": initialConfig?.toJson(),
      };

  bool get isValid =>
      _actions.contains(action) &&
      _handlePattern.hasMatch(handle) &&
      _clinicIdPattern.hasMatch(clinicId) &&
      serverUrl.startsWith("https://") &&
      _challengePattern.hasMatch(challenge) &&
      isBookingKey(adminKey) &&
      isBookingKey(inboxKey) &&
      adminKey != inboxKey &&
      (action != "register" || initialConfig != null) &&
      (action == "register" || initialConfig == null) &&
      utf8.encode(jsonEncode(toJson())).length <= 32 * 1024;

  static const List<String> _actions = ["register", "rotate", "recover"];
  static final RegExp _handlePattern = RegExp(r"^[a-z0-9]+(-[a-z0-9]+)*$");
  static final RegExp _clinicIdPattern = RegExp(r"^[0-9a-f]{32}$");
  static final RegExp _challengePattern = RegExp(r"^[0-9a-f]{64}$");

  /// Returns null for anything that is not exactly a well-formed attempt.
  static BookingPendingOperation? tryParse(Object? raw) {
    try {
      return _parse(raw);
    } catch (_) {
      return null;
    }
  }

  static BookingPendingOperation? _parse(Object? raw) {
    if (raw is! Map) return null;
    final json = raw.cast<String, Object?>();
    const allowed = {
      "action",
      "handle",
      "clinicId",
      "serverUrl",
      "challenge",
      "adminKey",
      "inboxKey",
      "initialConfig",
    };
    if (!json.keys.every(allowed.contains)) return null;
    final action = json["action"];
    final handle = json["handle"];
    final clinicId = json["clinicId"];
    final serverUrl = json["serverUrl"];
    final challenge = json["challenge"];
    final adminKey = json["adminKey"];
    final inboxKey = json["inboxKey"];
    if ([action, handle, clinicId, serverUrl, challenge, adminKey, inboxKey]
        .any((value) => value is! String)) {
      return null;
    }
    BookingClinicConfig? initialConfig;
    if (action == "register") {
      final rawConfig = json["initialConfig"];
      if (rawConfig is! Map) return null;
      initialConfig =
          BookingClinicConfig.fromJson(rawConfig.cast<String, Object?>());
      if (initialConfig.validate() != null) return null;
    } else if (json["initialConfig"] != null) {
      return null;
    }
    final attempt = BookingPendingOperation(
      action: action! as String,
      handle: handle! as String,
      clinicId: clinicId! as String,
      serverUrl: serverUrl! as String,
      challenge: challenge! as String,
      adminKey: adminKey! as String,
      inboxKey: inboxKey! as String,
      initialConfig: initialConfig,
    );
    return attempt.isValid ? attempt : null;
  }
}

/// Result of an enrollment/rotation attempt.
class BookingEnrollment {
  BookingEnrollment({
    required this.clinic,
    this.resumed = false,
  });

  final BookingClinicRecord clinic;

  /// True when a persisted attempt was completed rather than a new identity minted.
  final bool resumed;
}

/// PocketBase side of booking: discovery, enrollment, recovery, rotation and the
/// staff credential. Setup needs a superuser; failures never block ordinary PMS use.
class BookingClinicService {
  BookingClinicService({String? origin, BookingApi? api})
      : api = api ?? BookingApi(origin: (origin ?? bookingOrigin).trim()),
        _pb = login.pb,
        _serverUrl = login.url;

  final BookingApi api;
  final PocketBase? _pb;
  final String _serverUrl;

  bool get isSuperuser => identical(_pb, login.pb) && login.isAdmin;

  /// The clinic's canonical public origin, or null for a private/LAN or path-prefixed URL.
  static String? canonicalServerOrigin(String url) {
    if (url.trim().length > 255) return null;
    final parsed = Uri.tryParse(url.trim());
    if (parsed == null) return null;
    if (parsed.scheme != "https") return null;
    if (parsed.host.isEmpty || parsed.userInfo.isNotEmpty) return null;
    if (parsed.path.isNotEmpty && parsed.path != "/") return null;
    if (parsed.hasQuery || parsed.hasFragment) return null;
    if (parsed.hasPort && parsed.port != 443) return null;
    final host = parsed.host.toLowerCase();
    if (!host.contains(".") || host.length > 253 || host.endsWith(".") ||
        !RegExp(r"^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$").hasMatch(host) ||
        host.split(".").any((label) => label.isEmpty || label.length > 63)) {
      return null;
    }
    if (RegExp(r"^\d{1,3}(\.\d{1,3}){3}$").hasMatch(host)) return null;
    if ([".local", ".localhost", ".internal", ".home", ".lan", ".test",
          ".example", ".invalid", ".onion"]
        .any(host.endsWith)) {
      return null;
    }
    return "https://$host";
  }

  Future<BookingClinicRecord?> loadClinic() async {
    final pb = _pb;
    if (pb == null) return null;
    try {
      final records =
          await pb.collection(bookingClinicCollectionName).getFullList();
      if (records.isEmpty) return null;
      return BookingClinicRecord.fromRecord(records.first.data);
    } on ClientException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<BookingAdminRecord?> loadAdmin() async {
    final pb = _pb;
    if (pb == null || !isSuperuser) return null;
    try {
      final record = await pb
          .collection(bookingAdminCollectionName)
          .getOne(bookingAdminRecordId);
      return BookingAdminRecord.fromRecord(record.data);
    } on ClientException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Leaves the platform: the Worker erases the clinic and its requests, then the
  /// app drops the credential records so the claim form and inbox route return.
  Future<void> deleteClinic() async {
    if (!isSuperuser) throw StateError("booking_setup_requires_admin");
    final clinic = await loadClinic();
    final admin = await loadAdmin();
    if (clinic == null || admin == null) {
      throw StateError("booking_not_registered");
    }
    await api.deleteClinic(admin.adminKey, clinic.handle);
    final pb = _pb;
    if (pb != null) {
      for (final collection in [
        bookingClinicCollectionName,
        bookingAdminCollectionName,
      ]) {
        final List<RecordModel> records;
        try {
          records = await pb.collection(collection).getFullList();
        } on ClientException catch (e) {
          if (e.statusCode == 404) continue;
          rethrow;
        }
        for (final record in records) {
          try {
            await pb.collection(collection).delete(record.id);
          } on ClientException catch (e) {
            if (e.statusCode != 404) rethrow;
          }
        }
      }
    }
  }

  /// True when the three booking collections exist with the canonical shape.
  Future<bool> collectionsReady() async {
    final pb = _pb;
    if (pb == null) return false;
    try {
      final collections = await pb.collections.getFullList();
      final byName = {
        for (final collection in collections) collection.name: collection
      };
      for (final definition in bookingCollections) {
        final existing = byName[definition.name];
        if (existing == null) return false;
        final existingFields =
            existing.fields.map((field) => field.name).toSet();
        for (final field in definition.fields) {
          if (field.name == "id") continue;
          if (!existingFields.contains(field.name)) return false;
        }
        if (definition.name == bookingClinicCollectionName &&
            existing.listRule != definition.listRule) {
          return false;
        }
        if (definition.name == bookingVerificationCollectionName &&
            existing.viewRule != definition.viewRule) {
          return false;
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Explicit superuser repair; never deletes records or fields.
  Future<void> repairSchema() async {
    final pb = _pb;
    if (pb == null || !isSuperuser) {
      throw StateError("booking_setup_requires_admin");
    }
    await ensureBookingSchema(pb);
  }

  Future<void> _publishClinic(BookingClinicRecord clinic) async {
    final pb = _pb;
    if (pb == null || !isSuperuser) {
      throw StateError("booking_setup_requires_admin");
    }
    final body = clinic.toPocketBase();
    try {
      await pb
          .collection(bookingClinicCollectionName)
          .update(bookingClinicRecordId, body: body);
    } on ClientException catch (e) {
      if (e.statusCode != 404) rethrow;
      await pb
          .collection(bookingClinicCollectionName)
          .create(body: {"id": bookingClinicRecordId, ...body});
    }
  }

  Future<void> _saveAdmin(BookingAdminRecord admin) async {
    final pb = _pb;
    if (pb == null || !isSuperuser) {
      throw StateError("booking_setup_requires_admin");
    }
    final body = admin.toPocketBase();
    try {
      await pb
          .collection(bookingAdminCollectionName)
          .update(bookingAdminRecordId, body: body);
    } on ClientException catch (e) {
      if (e.statusCode != 404) rethrow;
      await pb
          .collection(bookingAdminCollectionName)
          .create(body: {"id": bookingAdminRecordId, ...body});
    }
  }

  /// Publishes the operation-bound proof the Worker will read. Superuser only.
  Future<String> _writeVerification(BookingPendingOperation attempt) async {
    final pb = _pb;
    if (pb == null || !isSuperuser) {
      throw StateError("booking_setup_requires_admin");
    }
    final operationHash = _operationHash(attempt);
    final proofs =
        await pb.collection(bookingVerificationCollectionName).getFullList(
                filter: pb.filter("challenge = {:challenge}", {
              "challenge": attempt.challenge,
            }));
    if (proofs.isNotEmpty) {
      final proof = proofs.single;
      if (proof.getStringValue("clinic_id") != attempt.clinicId ||
          proof.getStringValue("operation_hash") != operationHash) {
        throw StateError("booking_invalid_attempt");
      }
      await pb.collection(bookingVerificationCollectionName).delete(proof.id);
    }
    final record =
        await pb.collection(bookingVerificationCollectionName).create(
      body: {
        "challenge": attempt.challenge,
        "clinic_id": attempt.clinicId,
        "operation_hash": operationHash,
      },
    );
    return record.id;
  }

  Future<void> _deleteVerification(String recordId) async {
    final pb = _pb;
    if (pb == null) return;
    try {
      await pb.collection(bookingVerificationCollectionName).delete(recordId);
    } catch (_) {
      // Abandoned proofs are cleaned up on the next setup visit.
    }
  }

  String _operationHash(BookingPendingOperation attempt) => operationHash({
        "version": 1,
        "action": attempt.action,
        "handle": attempt.handle,
        "clinicId": attempt.clinicId,
        "serverUrl": attempt.serverUrl,
        "challenge": attempt.challenge,
        "adminKeyHash": keyHash(attempt.adminKey),
        "inboxKeyHash": keyHash(attempt.inboxKey),
        "initialConfig": attempt.initialConfig?.normalizedForProof().toJson(),
      });

  /// Resumes a persisted attempt or creates one. A registration keeps its active
  /// `admin_key` while a rotation/recovery candidate lives in `pending_operation`.
  Future<BookingPendingOperation> _pendingAttempt({
    required String action,
    required String handle,
    required String clinicId,
    required String serverUrl,
    BookingClinicConfig? initialConfig,
  }) async {
    final admin = await loadAdmin();
    final existing = BookingPendingOperation.tryParse(admin?.pendingOperation);
    if (existing != null &&
        existing.action == action &&
        existing.clinicId == clinicId &&
        existing.handle == handle &&
        existing.serverUrl == serverUrl) {
      return existing;
    }
    final attempt = BookingPendingOperation(
      action: action,
      handle: handle,
      clinicId: clinicId,
      serverUrl: serverUrl,
      challenge: randomHex(32),
      adminKey: generateBookingKey(),
      inboxKey: generateBookingKey(),
      initialConfig: initialConfig,
    );
    if (!attempt.isValid) throw StateError("booking_invalid_attempt");
    // Persist before any network call so a lost response cannot strand the keys.
    final activeAdminKey =
        admin != null && admin.adminKey.isNotEmpty && action != "register"
            ? admin.adminKey
            : attempt.adminKey;
    await _saveAdmin(BookingAdminRecord(
      clinicId: admin?.clinicId.isNotEmpty == true ? admin!.clinicId : clinicId,
      adminKey: activeAdminKey,
      pendingOperation: attempt.toJson(),
    ));
    return attempt;
  }

  Future<BookingEnrollment> register({
    required String handle,
    required BookingClinicConfig config,
  }) async {
    if (!isSuperuser || _pb == null) {
      throw StateError("booking_setup_requires_admin");
    }
    final serverUrl = canonicalServerOrigin(_serverUrl);
    if (serverUrl == null) throw StateError("booking_unsupported_server");
    final normalizedHandle = handle.trim().toLowerCase();
    if (normalizedHandle.length < 3 || normalizedHandle.length > 63 ||
        !bookingHandlePattern.hasMatch(normalizedHandle) ||
        bookingReservedHandles.contains(normalizedHandle)) {
      throw StateError("booking_invalid_handle");
    }
    final admin = await loadAdmin();
    final resumed = BookingPendingOperation.tryParse(admin?.pendingOperation);
    final clinicId = resumed?.action == "register"
        ? resumed!.clinicId
        : (admin?.clinicId.isNotEmpty == true
            ? admin!.clinicId
            : randomHex(16));
    final configForProof = config.normalizedForProof();
    final attempt = await _pendingAttempt(
      action: "register",
      handle: resumed?.action == "register" ? resumed!.handle : normalizedHandle,
      clinicId: clinicId,
      serverUrl: serverUrl,
      initialConfig: configForProof,
    );
    final verificationId = await _writeVerification(attempt);
    try {
      final result = await api.register(attempt.toOperationBody());
      final clinic = BookingClinicRecord(
        handle: attempt.handle,
        clinicId: result.clinicId,
        publicUrl: result.publicUrl,
        inboxKey: attempt.inboxKey,
        keyRevision: result.keyRevision,
      );
      await _publishClinic(clinic);
      await _saveAdmin(BookingAdminRecord(
        clinicId: result.clinicId,
        adminKey: attempt.adminKey,
      ));
      return BookingEnrollment(clinic: clinic, resumed: resumed != null);
    } on BookingApiException catch (error) {
      if ({"handle_taken", "server_taken", "invalid_fields", "bad_request"}
          .contains(error.code)) {
        await _saveAdmin(BookingAdminRecord(
          clinicId: attempt.clinicId,
          adminKey: attempt.adminKey,
        ));
      }
      rethrow;
    } finally {
      await _deleteVerification(verificationId);
    }
  }

  /// Recovers access with a fresh key pair after the admin key is lost.
  Future<BookingEnrollment> recover() async {
    if (!isSuperuser) throw StateError("booking_setup_requires_admin");
    final existing = await loadClinic();
    if (existing == null) {
      throw StateError("booking_not_registered");
    }
    final attempt = await _pendingAttempt(
      action: "recover",
      handle: existing.handle,
      clinicId: existing.clinicId,
      serverUrl: canonicalServerOrigin(_serverUrl) ?? "",
    );
    final verificationId = await _writeVerification(attempt);
    try {
      final result = await api.recover(attempt.toOperationBody());
      final clinic = BookingClinicRecord(
        handle: existing.handle,
        clinicId: result.clinicId,
        publicUrl: result.publicUrl,
        inboxKey: attempt.inboxKey,
        keyRevision: result.keyRevision,
      );
      await _publishClinic(clinic);
      await _saveAdmin(BookingAdminRecord(
        clinicId: result.clinicId,
        adminKey: attempt.adminKey,
      ));
      return BookingEnrollment(clinic: clinic);
    } finally {
      await _deleteVerification(verificationId);
    }
  }

  /// Replaces both keys. The candidate pair is persisted first; the staff
  /// credential is published only after the Worker accepts it.
  Future<BookingClinicRecord> rotate() async {
    if (!isSuperuser) throw StateError("booking_setup_requires_admin");
    final existing = await loadClinic();
    final admin = await loadAdmin();
    if (existing == null || admin == null) {
      throw StateError("booking_not_registered");
    }
    // Retry with the new admin key when rotation succeeded but publishing failed.
    final pending = BookingPendingOperation.tryParse(admin.pendingOperation);
    final attempt = pending?.action == "rotate"
        ? pending!
        : await _pendingAttempt(
            action: "rotate",
            handle: existing.handle,
            clinicId: existing.clinicId,
            serverUrl: canonicalServerOrigin(_serverUrl) ?? "",
          );
    final activeAdminKey = admin.adminKey;
    var revision = -1;
    try {
      // A retry authenticates with the candidate key; if the earlier call already
      // replaced the hashes, the Worker returns success without incrementing again.
      revision = await api.rotate(
        attempt.adminKey,
        expectedKeyRevision: existing.keyRevision,
        newAdminKey: attempt.adminKey,
        newInboxKey: attempt.inboxKey,
      );
    } on BookingApiException catch (error) {
      if (!error.unauthorized || activeAdminKey == attempt.adminKey) rethrow;
      // The candidate was never applied: the still-active key performs it.
      revision = await api.rotate(
        activeAdminKey,
        expectedKeyRevision: existing.keyRevision,
        newAdminKey: attempt.adminKey,
        newInboxKey: attempt.inboxKey,
      );
    }
    final clinic = BookingClinicRecord(
      handle: existing.handle,
      clinicId: existing.clinicId,
      publicUrl: existing.publicUrl,
      inboxKey: attempt.inboxKey,
      keyRevision: revision,
    );
    await _publishClinic(clinic);
    await _saveAdmin(BookingAdminRecord(
      clinicId: existing.clinicId,
      adminKey: attempt.adminKey,
    ));
    return clinic;
  }

  Future<int> readConfigRevision() async {
    final admin = await loadAdmin();
    if (admin == null) throw StateError("booking_not_registered");
    final snapshot = await api.readConfig(admin.adminKey);
    return snapshot.revision;
  }

  Future<BookingClinicConfig> readConfig(BookingClinicRecord clinic) async {
    final admin = await loadAdmin();
    if (admin == null) throw StateError("booking_not_registered");
    return (await api.readConfig(admin.adminKey)).config;
  }

  Future<int> writeConfig(
    BookingClinicConfig config,
    int expectedRevision,
  ) async {
    final admin = await loadAdmin();
    if (admin == null) throw StateError("booking_not_registered");
    return api.writeConfig(
        admin.adminKey, config.normalizedForProof(), expectedRevision);
  }

  void dispose() => api.dispose();
}

final RegExp bookingHandlePattern = RegExp(r"^[a-z0-9]+(-[a-z0-9]+)*$");
const Set<String> bookingReservedHandles = {
  "api",
  "v1",
  "health",
  "assets",
  "static",
  "admin",
  "privacy",
  "terms",
  "report",
  "book",
  "www",
};

/// Best-effort discovery result for the settings entry.
class BookingDiscovery {
  BookingDiscovery({
    required this.registered,
    required this.schemaReady,
    this.clinic,
    this.error,
  });

  final bool registered;
  final bool schemaReady;
  final BookingClinicRecord? clinic;
  final String? error;
}

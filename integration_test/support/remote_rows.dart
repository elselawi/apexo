// The server, seen the way *another device* sees it. §1.6.
//
// Every sync test needs a second writer. "A change made on another device" is a
// record that exists on the server and not in this app's local database, and the
// only way to make one from inside a run is to talk to PocketBase directly — the
// same client the app uses, signed in as the same admin (`_superusers`), writing
// the same `data` collection the sync engine reads and writes.
//
// Deliberately **not** a second `LocalPocket`: a test that used the engine to
// fake another device would be checking the engine against itself. Here the row
// is created, patched and deleted by hand, and every assertion stays the app's.
import 'dart:math' show min;

import 'package:pocketbase/pocketbase.dart';
import 'credentials.dart';

abstract final class RemoteRows {
  static PocketBase? _pb;

  /// The signed-in client, created once per run.
  static Future<PocketBase> client() async {
    final existing = _pb;
    if (existing != null) return existing;
    final client = PocketBase(pbServer);
    await client
        .collection('_superusers')
        .authWithPassword(pbEmail, pbPassword);
    _pb = client;
    return client;
  }

  /// The remote row with [id], or `null` when the server does not have it.
  ///
  /// A 404 is the interesting answer here, not a failure: "the app has not
  /// pushed it yet" and "another device deleted it" are both *absence*.
  static Future<RecordModel?> find(String id) async {
    try {
      return await (await client()).collection('data').getOne(id);
    } on ClientException {
      return null;
    }
  }

  /// The row's own fields — the `data` blob the store's rows are — or `null`.
  static Future<Map<String, dynamic>?> fields(String id) async {
    final record = await find(id);
    if (record == null) return null;
    return Map<String, dynamic>.from(record.data['data'] as Map);
  }

  /// Every remote row of [store], ordered by the server.
  static Future<List<RecordModel>> inStore(String store) async =>
      (await client())
          .collection('data')
          .getFullList(filter: 'store = "$store"');

  /// The remote rows of [store] whose `name` is [name] — how a test asks "did
  /// the app push this patient yet?" without having to know its id.
  static Future<List<RecordModel>> named(String store, String name) async {
    final rows = await inStore(store);
    return rows.where((row) {
      final data = row.data['data'];
      return data is Map && data['name'] == name;
    }).toList();
  }

  /// The remote rows of [store] whose `title` starts with [prefix].
  ///
  /// The suite shares one server, so "the server holds no patients" is only true
  /// in an isolated run; a group that seeds rows has to ask about **its own**.
  static Future<List<RecordModel>> titledLike(
    String store,
    String prefix,
  ) async {
    final rows = await inStore(store);
    return rows.where((row) {
      final data = row.data['data'];
      final title = data is Map ? data['title'] : null;
      return title is String && title.startsWith(prefix);
    }).toList();
  }

  /// Writes a row the app has never seen: **the other device's** write.
  ///
  /// The id comes back from the server rather than being forced through the
  /// body, so the row is created exactly the way PocketBase creates one.
  ///
  /// The value is then completed with that id, because that is what the app's
  /// own writes look like: `Model.toJson` always sets `'id'`, and a store keys
  /// its map by the *document's* id while building each model from the value.
  /// A value with no `id` therefore gets one invented by `Model.fromJson` — one
  /// row, two ids — and `Fixtures.patientIdOf(name)`, which reads the model's
  /// id, answers with the invented one. That is `sync_offline 01`/`03`:
  /// *"the pulled row is not readable by name"*, with the store already holding
  /// the row under the server's id (`_waitForLocalRow` waits for exactly that).
  static Future<String> insert({
    required String store,
    required Map<String, dynamic> data,
  }) async {
    final created = await (await client()).collection('data').create(
      body: {
        'store': store,
        'data': data,
      },
    );
    await (await client()).collection('data').update(
      created.id,
      body: {
        'data': {...data, 'id': created.id},
      },
    );
    return created.id;
  }

  /// Changes some fields of a row the server already holds.
  static Future<void> patch(String id, Map<String, dynamic> changes) async {
    final current = await fields(id);
    if (current == null) {
      throw StateError('the server has no row "$id" to patch');
    }
    await (await client()).collection('data').update(
      id,
      body: {
        'data': {...current, ...changes},
      },
    );
  }

  /// Deletes a row **on the server** — the direction the sync has no feed for.
  static Future<void> delete(String id) async {
    try {
      await (await client()).collection('data').delete(id);
    } on ClientException {
      // Already gone: handing the same row back twice is not an error.
    }
  }

  /// Deletes many rows on the server, bounded-parallel, and reports what it did.
  ///
  /// PocketBase has no bulk delete, so this is one request per row. Two facts
  /// about that shape were measured, and both are why this method looks the way
  /// it does:
  ///
  /// * **A failed request may still have landed.** Of a thousand patients, 173
  ///   deletes were confirmed and 827 came back as errors — and a probe of the
  ///   server afterwards found only 160 of the thousand left, so most of those
  ///   "failures" had deleted the row anyway (client-side socket errors under a
  ///   burst of 25 concurrent requests). A count of successful responses is
  ///   therefore not a count of deleted rows: a failure has to be **asked
  ///   about** (`find`) before it is believed, and the leftovers retried.
  /// * **Errors are worth reporting**, not swallowing: a `429` from the
  ///   server's rate limiter and a `404` from a row another device already
  ///   handed back are the same "false" otherwise.
  ///
  /// Deleting **only locally** does not stick while the server still holds the
  /// row — `Store.purge` drops the outbox entry with the row, so nothing is
  /// pushed and the next pull brings the row back (`perf_budgets 06` left 24 of
  /// a thousand that way). The server has to go first.
  ///
  /// [concurrency] is deliberately small: the app is syncing in the same process
  /// and the shared server counts requests per IP.
  static Future<DeleteReport> deleteMany(
    Iterable<String> ids, {
    int concurrency = 8,
    int rounds = 4,
  }) async {
    final client = await RemoteRows.client();
    var pending = ids.toSet().toList();
    var deleted = 0;
    final errors = <String, int>{};
    for (var round = 1; round <= rounds && pending.isNotEmpty; round++) {
      final results = await _pool(
        [
          for (final id in pending)
            () => client
                .collection('data')
                .delete(id)
                .then<Object?>((_) => null)
                .catchError((Object e) => e),
        ],
        concurrency,
      );
      final still = <String>[];
      for (var i = 0; i < pending.length; i++) {
        final error = results[i];
        if (error == null) {
          deleted++;
          continue;
        }
        // The request failed — but a failure is not the same as a no-op. Ask.
        if (await find(pending[i]) == null) {
          deleted++;
          continue;
        }
        errors[_describe(error)] = (errors[_describe(error)] ?? 0) + 1;
        still.add(pending[i]);
      }
      pending = still;
      // A round that got nowhere is a server refusing us, not a slow server:
      // stop and let the caller report the errors rather than spin.
      if (pending.length == results.length && pending.length > 1) break;
    }
    return DeleteReport(
      deleted: deleted,
      left: pending.length,
      errors: errors,
    );
  }

  /// A short, countable label for a failed delete (`429 too many requests`).
  static String _describe(Object error) {
    if (error is ClientException) {
      final message = '${error.response['message'] ?? ''}'.trim();
      final path = error.url?.pathSegments ?? const <String>[];
      return message.isEmpty
          ? '${error.statusCode} ${path.isEmpty ? '' : path.last}'
          : '${error.statusCode} $message';
    }
    return '${error.runtimeType}: ${'$error'.split('\n').first}';
  }

  /// Runs [jobs] with at most [concurrency] of them in flight, in order.
  static Future<List<T>> _pool<T>(
    List<Future<T> Function()> jobs,
    int concurrency,
  ) async {
    final results = List<T?>.filled(jobs.length, null);
    var next = 0;
    Future<void> worker() async {
      while (true) {
        final index = next++;
        if (index >= jobs.length) return;
        results[index] = await jobs[index]();
      }
    }

    await Future.wait([
      for (var w = 0; w < min(concurrency, jobs.length); w++) worker(),
    ]);
    return [for (final result in results) result as T];
  }
}

/// What a [RemoteRows.deleteMany] call achieved: how many rows are gone, how
/// many the server still has, and why the rest would not go.
class DeleteReport {
  /// Creates a report. Every field is a fact about the server, not a hope.
  const DeleteReport({
    required this.deleted,
    required this.left,
    required this.errors,
  });

  /// Rows that are no longer on the server (confirmed by the delete itself or by
  /// a follow-up read after a failed request).
  final int deleted;

  /// Ids the server still holds after the rounds were used up.
  final int left;

  /// Failure messages, and how many rows each accounted for.
  final Map<String, int> errors;

  @override
  String toString() {
    final why = errors.isEmpty
        ? ''
        : ' (${errors.entries.map((e) => '${e.key} x${e.value}').join(', ')})';
    return '$deleted deleted, $left left$why';
  }
}

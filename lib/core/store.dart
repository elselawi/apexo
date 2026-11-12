import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:apexo/core/synchronization/push_data.dart';
import 'package:apexo/utils/constants.dart';
import 'package:http/http.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

import 'model.dart';
import 'persistence/serial_operation_queue.dart';
import 'lifecycle/realtime_subscription.dart';
import 'synchronization/conflict_merge.dart';
import 'synchronization/deferred_file_keys.dart';
import 'synchronization/store_effects.dart';
import 'synchronization/document_loading.dart';
import 'reactive/observable.dart';
import 'persistence/save_local.dart';
import 'persistence/save_remote.dart';

export 'synchronization/document_loading.dart' show ModellingFunc;

class SyncResult {
  SyncResult({this.pushed, this.pulled, this.conflicts, this.exception});
  int? pushed;
  int? pulled;
  int? conflicts;
  String? exception;
  @override
  String toString() {
    return "pushed: $pushed, pulled: $pulled, conflicts: $conflicts, exception: $exception";
  }
}

class Store<G extends Model> {
  Store({
    required this.modeling,
    this.isDemo,
    this.local,
    this.remote,
    this.debounceMS = 100,
    this.onSyncStart,
    this.onSyncEnd,
    this.manualSyncOnly,
    this.effects = const StoreEffects(),
    DocumentLoader<G>? loadDocuments,
  })  : loadDocuments = loadDocuments ?? loadStoreDocuments<G>,
        observableMap = ObservableDict() {
    // loading from local
    loaded = deleteMemoryAndLoadFromPersistence();
  }

  /// Called when a file upload permanently fails (dead-letter); DICOM code
  /// clears its import registry so the file can be re-discovered.
  static final List<void Function(String filename)> onFileDeadLettered = [];

  final StoreEffects effects;
  final DocumentLoader<G> loadDocuments;
  late Future<void> loaded;
  final void Function()? onSyncStart;
  final void Function()? onSyncEnd;
  final ObservableDict<G> observableMap;
  final Set<DictEvent> changes = {};
  Map<String, G> archived = {};
  SaveLocal? local;
  SaveRemote? remote;
  late final _realtime = RealtimeSubscription(onError: (error, stack) {
    effects.authenticationFailed(error);
    effects.log('Realtime subscription failed: $error', stack);
  });
  final int debounceMS;
  late ModellingFunc<G> modeling;
  bool deferredPresent = false;
  int lastProcessChanges = 0;
  bool? manualSyncOnly;
  bool? isDemo;
  int _persistenceSession = 0;
  final SerialOperationQueue _persistence = SerialOperationQueue();
  Future<List<SyncResult>>? _syncTask;
  bool _initialized = false;
  Future<void>? _sessionSave;

  void _preserveSessionChanges() {
    final target = local;
    if (target == null || changes.isEmpty) return;
    final snapshot = <String, String>{};
    for (final event in changes) {
      final document = observableMap.get(event.id);
      if (document != null) snapshot[event.id] = _serialize(document);
    }
    if (snapshot.isEmpty) return;
    final needsRemoteSync = remote != null;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final saving = _persistence.run(() async {
      await target.put(snapshot);
      if (needsRemoteSync) {
        final deferred = await target.getDeferred();
        await target.putDeferred({
          ...deferred,
          for (final id in snapshot.keys) id: timestamp,
        });
      }
    });
    _sessionSave = saving;
    unawaited(saving.catchError((Object error, StackTrace stack) {
      effects.log(
          'Could not preserve edits while ending session: $error', stack);
    }));
  }

  @mustCallSuper
  void init() {
    if (_initialized) return;
    _initialized = true;

    // setting up observers
    observableMap.onMutation = (events) {
      if (events.isEmpty) return;
      if (events[0].type == DictEventType.modify &&
          events[0].id == "__ignore_view__") {
        // this is a view change not a storage change
        return;
      }

      for (final element in events) {
        if (element.type == DictEventType.remove) {
          if (element.id == '__removed_all__') {
            archived.clear();
          } else {
            archived.remove(element.id);
          }
          continue;
        }
        final doc = observableMap.get(element.id);
        if (doc == null) continue;
        if (doc.archived == true) {
          archived[doc.id] = doc;
        } else {
          archived.remove(doc.id);
        }
      }

      changes.addAll(events.where((c) => c.id != "__ignore_view__"));
      _processChanges();
    };
  }

  /// Reloads from local storage, bailing out if unsaved changes are pending.
  /// Use [reload] to drain pending persistence first.
  Future<void> deleteMemoryAndLoadFromPersistence() async {
    if (local == null) {
      return;
    }
    final session = _persistenceSession;
    final sessionLocal = local!;
    final Map<String, String> all = await sessionLocal.getAll();
    // Decode JSON strings in a background isolate
    final Map<String, Map<String, dynamic>> decoded =
        await compute(decodeStoreDocuments, all);

    final modellingResult = await loadDocuments(modeling, decoded);
    if (session != _persistenceSession ||
        !identical(local, sessionLocal) ||
        changes.isNotEmpty) {
      return;
    }
    final Map<String, G> modeled = modellingResult[0];
    archived = modellingResult[1];
    // silent for persistence; use the optimized setAllWithJson
    observableMap.silently(() {
      observableMap.clear();
      observableMap.setAllWithJson(modeled, decoded);
    });
    // but loud for view
    observableMap.notifyView();
    return;
  }

  String _serialize(G input) {
    return jsonEncode(input);
  }

  void _processChanges() {
    final session = _persistenceSession;
    final sessionLocal = local;
    final sessionRemote = remote;
    unawaited(_persistence
        .run(() => _processChangesForSession(
              session,
              sessionLocal,
              sessionRemote,
            ))
        .catchError((Object e, StackTrace s) {
      effects.log('Error while persisting store changes: $e', s);
    }));
  }

  Future<void> _processChangesForSession(
    int session,
    SaveLocal? sessionLocal,
    SaveRemote? sessionRemote,
  ) async {
    if (isDemo == true) notify();

    if (session != _persistenceSession || sessionLocal == null) {
      return;
    }

    if (changes.isEmpty) return;
    if (observableMap.docs.isEmpty) {
      changes.clear();
      return;
    }

    onSyncStart?.call();
    try {
      lastProcessChanges = DateTime.now().millisecondsSinceEpoch;

      final Map<String, String> toWrite = {};
      final Map<String, int> toDefer = {};
      final List<PushData> toPush = [];

      final List<DictEvent> changesToProcess = [...changes];

      for (DictEvent e in changesToProcess) {
        final G? item = observableMap.get(e.id);
        if (item == null) {
          changes.remove(e);
          continue;
        }
        final String serialized = _serialize(item);
        toWrite[e.id] = serialized;
        toDefer[e.id] = lastProcessChanges;

        // push notifications processing
        final doc = e.document;

        if (sessionRemote == null) continue;
        if (doc == null) continue;
        if (e.type == DictEventType.remove) continue;
        if (e.type == DictEventType.add && doc.pushOnCreation == false) {
          continue;
        }
        final List<String> updatedFields;
        final List<dynamic> oldVals;
        final List<dynamic> newVals;
        if (e.type == DictEventType.modify) {
          final filteredIndices = <int>[
            for (var i = 0; i < e.modifiedKeys.length; i++)
              if (doc.pushIfChanged.contains(e.modifiedKeys[i])) i,
          ];
          if (filteredIndices.isEmpty) continue;
          updatedFields = [for (final i in filteredIndices) e.modifiedKeys[i]];
          oldVals = [
            for (final i in filteredIndices)
              i < e.oldVals.length ? e.oldVals[i] : null,
          ];
          newVals = [
            for (final i in filteredIndices)
              i < e.newVals.length ? e.newVals[i] : null,
          ];
        } else {
          updatedFields = const [];
          oldVals = const [];
          newVals = const [];
        }
        final pushTargets = doc.targetsToPushTo;
        if (pushTargets.isEmpty) continue;
        toPush.add(PushData(
          store: sessionRemote.storeName,
          id: e.id,
          readableIdentifier: doc.title,
          isCreation: e.type == DictEventType.add,
          isUpdate: e.type == DictEventType.modify,
          updatedFields: updatedFields,
          oldVals: oldVals,
          newVals: newVals,
          targetIDs: pushTargets,
        ));
      }

      await sessionLocal.put(toWrite);
      if (session != _persistenceSession) return;

      if (sessionRemote == null) {
        changes.removeAll(changesToProcess);
        return;
      }

      final Map<String, int> lastDeferred = await sessionLocal.getDeferred();
      if (session != _persistenceSession) return;
      // Journal before network I/O so an interrupted write stays retryable.
      await sessionLocal.putDeferred({...lastDeferred, ...toDefer});
      if (session != _persistenceSession) return;
      if (toPush.isNotEmpty) await effects.enqueuePushes(toPush);
      deferredPresent = true;
      if (session != _persistenceSession) return;
      if (sessionRemote.isOnline && lastDeferred.isEmpty) {
        try {
          await sessionRemote.put(toWrite.entries
              .map((e) => RowToWriteRemotely(id: e.key, data: e.value))
              .toList());
          if (session != _persistenceSession) return;
          final remaining = await sessionLocal.getDeferred();
          remaining.removeWhere((key, value) => toDefer[key] == value);
          await sessionLocal.putDeferred(remaining);
          deferredPresent = remaining.isNotEmpty;
          changes.removeAll(changesToProcess);
          try {
            await effects.sendPushes(toPush);
            if (session != _persistenceSession) return;
            if (toPush.isNotEmpty) {
              await effects.clearPushesByIDs(toPush.map((p) => p.id));
            }
          } catch (pushErr, pushStack) {
            effects.log(
                "Error sending push notifications (kept in deferred queue): $pushErr",
                pushStack);
          }
          // Don't await synchronize(): its failure would be caught by the
          // catch below and re-defer the rows just written.
          if (manualSyncOnly != true) {
            unawaited(synchronize());
          }
          return;
        } catch (e, s) {
          effects.authenticationFailed(e);
          effects.reportError(e, "sendingUpdatesToServer");
          effects.log("Error during sending (Will defer updates): $e", s);
        }
      }

      changes.removeAll(changesToProcess);
    } finally {
      onSyncEnd?.call();
    }
  }

  Future<SyncResult> _syncTry(int session) async {
    final local = this.local;
    final remote = this.remote;
    if (session != _persistenceSession) {
      return SyncResult(exception: 'persistence session ended');
    }
    if (isDemo == true) {
      return SyncResult(exception: "sync is disabled in demo mode");
    }
    if (local == null || remote == null) {
      return SyncResult(
          exception: "local/remote persistence layers are not defined");
    }

    if (remote.isOnline == false) {
      return SyncResult(exception: "remote server is offline");
    }
    try {
      final int localVersion = await local.getVersion();
      final int remoteVersion = await remote.getVersion();

      final Map<String, int> deferred = await local.getDeferred();
      final processedDeferred = Map<String, int>.of(deferred);
      final hadDeferred = deferred.isNotEmpty;
      if (session != _persistenceSession) {
        return SyncResult(exception: 'persistence session ended');
      }
      int conflicts = 0;

      // Re-read the cursor millisecond because PocketBase timestamps have
      // millisecond precision and another row can share the saved timestamp.
      final pullCursor = localVersion > 0 ? localVersion - 1 : localVersion;
      final VersionedResult remoteUpdates =
          await remote.getSince(version: pullCursor);
      if (session != _persistenceSession) {
        return SyncResult(exception: 'persistence session ended');
      }
      if (localVersion == remoteVersion &&
          !hadDeferred &&
          remoteUpdates.rows.isEmpty) {
        return SyncResult(exception: "nothing to sync");
      }

      if (remoteVersion == 0 &&
          localVersion > 0 &&
          remoteUpdates.rows.isEmpty) {
        // Usually means the token expired; refresh it, and on failure the
        // authentication error asks the user to log in again.
        try {
          await effects.refreshAuthentication();
        } catch (e) {
          effects.authenticationFailed(e);
          return SyncResult(exception: "Failed to refresh token: $e");
        }
      }

      final List<int> remoteLosersIndices = [];

      // Conflicts are merged field-level via [mergeConflict], not whole-row;
      // the merged JSON goes to both local and remote.
      final Map<String, String> mergedConflictsToLocal = {};
      final Map<String, String> mergedConflictsToRemote = {};

      // First pass is sync because removeWhere's callback cannot await.
      final List<_ConflictInfo> conflictsFound = [];
      deferred.removeWhere((dfID, deferredTimeStamp) {
        final int remoteConflictIndex =
            remoteUpdates.rows.indexWhere((r) => r.id == dfID);
        if (remoteConflictIndex == -1) {
          // no conflict
          return false;
        }
        final int remoteTimeStamp = remoteUpdates.rows[remoteConflictIndex].ts;
        if (remoteTimeStamp <= localVersion) {
          // A row at or below the cursor is overlap, not a conflict: merging it
          // would resurrect default-omitted fields. Push the pending local one.
          remoteLosersIndices.add(remoteConflictIndex);
          return false;
        }
        final bool localWins = deferredTimeStamp > remoteTimeStamp;
        conflictsFound.add(_ConflictInfo(
          dfID: dfID,
          remoteConflictIndex: remoteConflictIndex,
          localWins: localWins,
          remoteData: remoteUpdates.rows[remoteConflictIndex].data,
        ));
        conflicts++;
        // Drop the conflicting remote row; the merged version is written below.
        remoteLosersIndices.add(remoteConflictIndex);
        // Drop it from deferred too; the merged version is pushed below.
        return true;
      });

      // Second pass does the async merge; pending uploads are looked up per row
      // because the same filename can be queued for different rows.
      for (final c in conflictsFound) {
        final localJson =
            jsonDecode(await local.get(c.dfID)) as Map<String, dynamic>;
        final remoteJson = jsonDecode(c.remoteData) as Map<String, dynamic>;
        final serverFiles = remote.fullNamesCache[c.dfID] ?? const <String>[];
        final pendingUploads = filenamesFromDeferredForRow(deferred, c.dfID)
            .where((f) => f.isNotEmpty)
            .toSet();

        final mergedJson = mergeConflict(
          localJson: localJson,
          remoteJson: remoteJson,
          localWins: c.localWins,
          serverFiles: serverFiles,
          pendingUploads: pendingUploads,
        );

        final mergedStr = jsonEncode(mergedJson);
        mergedConflictsToLocal[c.dfID] = mergedStr;
        mergedConflictsToRemote[c.dfID] = mergedStr;
      }

      // Remove descending so the remaining indices stay valid.
      remoteLosersIndices.sort((a, b) => b.compareTo(a));
      for (int index in remoteLosersIndices) {
        remoteUpdates.rows.removeAt(index);
      }

      final Map<String, String> toLocalWrite = Map.fromEntries(
          remoteUpdates.rows.map((r) => MapEntry(r.id, r.data)));

      // Merged conflict rows override the pulled ones; their IDs were removed
      // from remoteUpdates above.
      toLocalWrite.addAll(mergedConflictsToLocal);

      if (localVersion == remoteVersion && !hadDeferred) {
        var hasLocalChanges = false;
        for (final entry in toLocalWrite.entries) {
          if (await local.get(entry.key) != entry.value) {
            hasLocalChanges = true;
            break;
          }
        }
        if (!hasLocalChanges) {
          return SyncResult(exception: "nothing to sync");
        }
      }

      // those will be built in the for loop below
      final Map<String, String> toRemoteWrite = {};

      final List<Future<void> Function()> fileHandling = [];
      // FILE keys that succeeded, so the end-of-pass cleanup spares any
      // re-queued failure entries.
      final succeededFileKeys = <String>{};

      for (var entry in deferred.entries) {
        if (entry.key.startsWith("FILE")) {
          final deferredFile = entry.key.split("||");
          // Key format: uploads FILE||row||path||filename[||retries], deletes
          // FILE||row||filename. Malformed keys are skipped, not fatal.
          if (!isValidDeferredFileKey(entry.key, entry.value)) {
            effects.log(
                'Deferred file: discarding malformed key "${entry.key}"',
                null,
                1);
            succeededFileKeys.add(entry.key);
            continue;
          }
          final bool upload = entry.value == 1;
          final String rowID = deferredFile[1];
          final String pathOrName = deferredFile[2];
          final String filename = upload ? deferredFile[3] : "";
          final int retries = parseDeferredRetries(entry.key);
          if (retries < 0) {
            effects.log(
                'Deferred file: discarding negative retry key "${entry.key}"',
                null,
                1);
            succeededFileKeys.add(entry.key);
            continue;
          }
          const maxRetries = 5;
          final newKey = buildDeferredRetryKey(entry.key, retries + 1);

          // Files are handled after all document writes since uploads are slow.
          fileHandling.add(() async {
            if (upload) {
              // Dead-letter: too many retries.
              if (retries >= maxRetries) {
                effects.log(
                    'Deferred upload: permanently failed for '
                    '"$filename" after $retries retries — removing from model',
                    null,
                    1);
                _cleanDanglingFileRef(rowID, filename);
                succeededFileKeys.add(entry.key);
                return;
              }

              try {
                final MultipartFile multipart;
                if (pathOrName.startsWith("http") ||
                    pathOrName.startsWith("blob:")) {
                  final uri = pathOrName.startsWith("blob:")
                      ? Uri.parse(pathOrName)
                      : Uri.parse(
                          'https://imgs.apexo.app/?url=${Uri.encodeComponent(pathOrName)}');
                  final response = await http.get(uri);
                  if (response.statusCode < 200 || response.statusCode >= 300) {
                    throw http.ClientException(
                        'File source returned HTTP ${response.statusCode}');
                  }
                  multipart = MultipartFile.fromBytes(
                    "imgs+",
                    response.bodyBytes,
                    filename: filename,
                  );
                } else {
                  multipart = await MultipartFile.fromPath(
                    "imgs+",
                    pathOrName,
                    filename: filename,
                  );
                }
                final pbName = await remote.uploadImage(
                  rowID: rowID,
                  filename: filename,
                  predefinedMultipart: multipart,
                );
                if (session != _persistenceSession) return;
                // PB may rename the file, so patch the model first; otherwise
                // _ensureDcmInModel adds a duplicate dcmImgs entry.
                if (pbName != filename) {
                  _patchModelFilename(rowID, filename, pbName);
                }
                if (_isDcmFile(pbName)) {
                  _ensureDcmInModel(rowID, pbName);
                }
                succeededFileKeys.add(entry.key);
              } catch (e, s) {
                // Upload failed — keep in queue with incremented retries.
                effects.log(
                    'Deferred upload: attempt ${retries + 1}/$maxRetries '
                    'failed for "$filename" — $e',
                    s,
                    1);
                final currentDeferred = await local.getDeferred();
                currentDeferred.remove(entry.key);
                currentDeferred[newKey] = 1;
                await local.putDeferred(currentDeferred);
              }
            } else {
              await remote.deleteImage(rowID, pathOrName);
              succeededFileKeys.add(entry.key);
            }
          });
        } else {
          toRemoteWrite.addAll({entry.key: await local.get(entry.key)});
        }
      }

      // Merged conflicts were dropped from deferred, so push them here.
      toRemoteWrite.addAll(mergedConflictsToRemote);

      if (session != _persistenceSession) {
        return SyncResult(exception: 'persistence session ended');
      }
      if (toLocalWrite.isNotEmpty) {
        await local.put(toLocalWrite);
      }
      if (toRemoteWrite.isNotEmpty) {
        await remote.put(toRemoteWrite.entries
            .map((e) => RowToWriteRemotely(id: e.key, data: e.value))
            .toList());

        if (session != _persistenceSession) {
          return SyncResult(exception: 'persistence session ended');
        }
        final winningPushes = (await Future.wait(toRemoteWrite.keys.map(
          (k) async => await effects.pendingPush(k),
        )))
            .where((x) => x != null)
            .cast<PushData>()
            .toList();

        try {
          await effects.sendPushes(winningPushes);
          if (session != _persistenceSession) {
            return SyncResult(exception: 'persistence session ended');
          }
          await effects.clearPushes(remote.storeName);
        } catch (pushErr, pushStack) {
          effects.log(
              "Error sending deferred pushes during sync (kept in deferred queue): $pushErr",
              pushStack);
        }
      }

      // Files run serially after all JSON writes: each failed upload updates
      // the shared deferred map, so parallel runs would clobber each other.
      for (final handleFile in fileHandling) {
        if (session != _persistenceSession) {
          return SyncResult(exception: 'persistence session ended');
        }
        await handleFile();
      }

      // Clear only processed non-FILE keys and succeeded FILE keys; failed
      // uploads were re-queued with incremented retries and must stay.
      if (session != _persistenceSession) {
        return SyncResult(exception: 'persistence session ended');
      }
      final currentDeferred = await local.getDeferred();
      currentDeferred.removeWhere((key, value) =>
          succeededFileKeys.contains(key) ||
          (!key.startsWith('FILE') && processedDeferred[key] == value));
      await local.putDeferred(currentDeferred);
      deferredPresent = currentDeferred.isNotEmpty;

      // Adopt the version this pull reported; it may already be stale, which is
      // why _syncRequest loops until local and remote converge.
      await local.putVersion(remoteUpdates.version > localVersion
          ? remoteUpdates.version
          : localVersion);

      // Deferred writes make remoteUpdates.version stale. Re-read it in a new
      // pass, not here: another client may write between the push and the read.

      // finally show a notification if the store or model has something notification worthy

      if (docs.isNotEmpty) {
        // only do this if there were already docs
        for (var element in toLocalWrite.entries) {
          final id = element.key;
          final document =
              modeling(jsonDecode(element.value) as Map<String, dynamic>);
          if (!document.targetsToPushTo.contains(effects.currentAccountID)) {
            continue;
          }

          if (document.pushOnCreation && !docs.containsKey(id)) {
            final readableIdentifier = document.title;

            final push = PushData(
              store: remote.storeName,
              id: id,
              readableIdentifier: readableIdentifier,
              isCreation: true,
              isUpdate: false,
              updatedFields: [],
              oldVals: [],
              newVals: [],
              targetIDs: document.targetsToPushTo,
            );

            await effects.notify(push);
          } else if (document.pushIfChanged.isNotEmpty &&
              docs.containsKey(id)) {
            final existing = docs[id]!;
            final oldPushCopy = existing.jsonCopyForPush;
            final newPushCopy = document.jsonCopyForPush;
            final oldJson =
                oldPushCopy.isNotEmpty ? oldPushCopy : existing.toJson();
            final newJson =
                newPushCopy.isNotEmpty ? newPushCopy : document.toJson();
            final diff = diffJson(oldJson, newJson)
                .where((k) => document.pushIfChanged.contains(k))
                .toList();
            if (diff.isEmpty) {
              continue;
            }
            final readableIdentifier = document.title;
            final push = PushData(
              store: remote.storeName,
              id: id,
              readableIdentifier: readableIdentifier,
              isCreation: false,
              isUpdate: true,
              updatedFields: diff,
              oldVals: diff.map((key) => oldJson[key]).toList(),
              newVals: diff.map((key) => newJson[key]).toList(),
              targetIDs: document.targetsToPushTo,
            );

            await effects.notify(push);
          }
        }
      }

      if (session == _persistenceSession && toLocalWrite.isNotEmpty) {
        final pendingIds = changes.map((event) => event.id).toSet();
        final visibleUpdates = <String, G>{};
        final visibleJson = <String, Map<String, dynamic>>{};
        for (final entry in toLocalWrite.entries) {
          if (pendingIds.contains(entry.key)) continue;
          final json = jsonDecode(entry.value) as Map<String, dynamic>;
          final document = modeling(json);
          visibleUpdates[entry.key] = document;
          visibleJson[entry.key] = json;
          if (document.archived == true) {
            archived[entry.key] = document;
          } else {
            archived.remove(entry.key);
          }
        }
        observableMap.silently(() {
          observableMap.setAllWithJson(visibleUpdates, visibleJson);
        });
        if (visibleUpdates.isNotEmpty) notify();
      }

      return SyncResult(
          pulled: toLocalWrite.length,
          pushed: toRemoteWrite.length,
          conflicts: conflicts,
          exception: null);
    } catch (e, s) {
      effects.authenticationFailed(e);
      effects.log("Error during synchronization: $e", s);
      return SyncResult(exception: e.toString());
    }
  }

  List<SyncResult>? lastRes;

  // ----------------------------- Public API --------------------------------

  void cancelRealtimeSub() => _realtime.cancel();

  /// Ends persistence before its targets are replaced (e.g. switching clinic).
  /// Await it before closing Hive boxes; pending edits are saved to the old one.
  Future<void> deactivatePersistenceSession() async {
    _preserveSessionChanges();
    _persistenceSession++;
    final syncing = _syncTask;
    changes.clear();
    deferredPresent = false;
    cancelRealtimeSub();
    remote?.dispose();
    if (syncing != null) await syncing;

    await _persistence.drain();
    await _sessionSave;
    await _realtime.drain();
  }

  /// Ends listeners and queued persistence on logout but keeps local storage,
  /// so a later login to the same clinic still loads its offline data.
  void endSession() {
    _preserveSessionChanges();
    _persistenceSession++;
    changes.clear();
    deferredPresent = false;
    cancelRealtimeSub();
    remote?.dispose();
    remote = null;
  }

  /// Syncs the local database with the remote database
  ///
  /// [immediate] skips the debounce delay that coalesces rapid calls, for work
  /// that must start as soon as it is requested (e.g. the login sync).
  Future<List<SyncResult>> synchronize({bool immediate = false}) {
    return _syncTask ??= _runSynchronization(_persistenceSession, immediate);
  }

  Future<List<SyncResult>> _runSynchronization(
      int session, bool immediate) async {
    try {
      if (!immediate) {
        await Future<void>.delayed(Duration(milliseconds: debounceMS));
      }
      final operation = _persistence.run(() => _syncRequest(session));
      final result = await operation;
      if (session == _persistenceSession) lastRes = result;
      return result;
    } finally {
      _syncTask = null;
    }
  }

  Future<List<SyncResult>> _syncRequest(int session) async {
    if (session != _persistenceSession) return [];
    // A sync may take several passes: each push bumps the server-issued
    // version, so the pushed rows must be pulled back before the two match.
    final sessionRemote = remote;
    if (sessionRemote != null && manualSyncOnly != true) {
      _realtime.start(() => sessionRemote.pbInstance
              .collection(dataCollectionName)
              .subscribe('*', (msg) {
            if (session == _persistenceSession &&
                msg.record?.data['store'] == sessionRemote.storeName) {
              unawaited(synchronize());
            }
          }));
    }

    lastProcessChanges = DateTime.now().millisecondsSinceEpoch;
    onSyncStart?.call();
    try {
      final List<SyncResult> tries = [];
      while (session == _persistenceSession) {
        final SyncResult result = await _syncTry(session);
        tries.add(result);
        if (result.exception != null) break;
        // A pass that changed nothing will never converge, e.g. an empty remote
        // with a local cursor ahead; login awaits this, so don't spin here.
        final progressed = (result.pushed ?? 0) > 0 ||
            (result.pulled ?? 0) > 0 ||
            (result.conflicts ?? 0) > 0;
        if (!progressed) {
          effects.log(
            'sync stopped after a pass that changed nothing; '
            'local and remote are not converging',
            StackTrace.current,
          );
          break;
        }
      }
      return tries;
    } finally {
      onSyncEnd?.call();
    }
  }

  //// Returns true if the local database is in sync with the remote database
  Future<bool> inSync() async {
    try {
      if (local == null || remote == null) return false;
      if (deferredPresent) return false;
      return await local!.getVersion() == await remote!.getVersion();
    } catch (e, s) {
      effects.authenticationFailed(e);
      effects.log("Error during inSync check: $e", s);
      return false;
    }
  }

  /// Reloads the store from the local database
  Future<void> reload() async {
    await waitUntilChangesAreProcessed();
    await deleteMemoryAndLoadFromPersistence();
  }

  /// Returns a list of all the documents in the local database
  Map<String, G> get docs {
    return Map<String, G>.unmodifiable(observableMap.docs);
  }

  Map<String, G> get present {
    return Map<String, G>.fromEntries(docs.entries.where((entry) =>
        (entry.value.archived != true) && entry.value.locked != true));
  }

  bool has(String id) {
    return observableMap.docs.containsKey(id);
  }

  /// gets a document by id
  G? get(String id) {
    return observableMap.docs[id];
  }

  /// adds a document
  void set(G item) {
    observableMap.set(item);
  }

  /// adds a list of documents
  void setAll(List<G> items) {
    observableMap.setAll(items);
  }

  /// archives a document by id (the concept of deletion is not supported here)
  void archive(String id) {
    final G? item = get(id);
    if (item == null) return;
    observableMap.set(item..archived = true);
    archived[id] = item;
  }

  /// un-archives a document by id (the concept of deletion is not supported here)
  void unarchive(String id) {
    final G? item = get(id);
    if (item == null) return;
    observableMap.set(item..archived = false);
    archived.remove(id);
  }

  /// archives a document by id (the concept of deletion is not supported here)
  void delete(String id) {
    archive(id);
  }

  Future<T> _queuePersistence<T>(Future<T> Function() action) {
    final session = _persistenceSession;
    return _persistence.run(() {
      if (session != _persistenceSession) {
        throw StateError('Persistence session ended');
      }
      return action();
    });
  }

  /// delete an image
  Future<void> deleteImg(String rowID, String name) =>
      _queuePersistence(() => _deleteImg(rowID, name));

  Future<void> _deleteImg(String rowID, String name) async {
    final local = this.local;
    final remote = this.remote;
    onSyncStart?.call();
    try {
      if (remote == null) {
        throw Exception("remote persistence layer is not defined");
      }
      if (local == null) {
        throw Exception("local persistence layer is not defined");
      }
      final Map<String, int> lastDeferred = await local.getDeferred();
      if (remote.isOnline && lastDeferred.isEmpty) {
        try {
          await remote.deleteImage(rowID, name);
          unawaited(synchronize());
          return;
        } catch (e, s) {
          effects.reportError(e, "deletingFile");
          effects.authenticationFailed(e);
          effects.log(
              "Error during deleting the file (Will defer upload): $e", s);
        }
      }

      // DEFERRED Structure: "FILE||{rowID}||path:{0 for deleting, 1 for uploading}"

      await local.putDeferred({}
        ..addAll(lastDeferred)
        ..addAll({"FILE||$rowID||$name": 0}));
      deferredPresent = true;
    } finally {
      onSyncEnd?.call();
    }
  }

  /// Deletes a DCM file and its PNG preview, ignoring a missing preview (still
  /// queued or never generated). The caller must drop `dcmName` from `dcmImgs`.
  Future<void> deleteDcmImg(String rowID, String dcmName) async {
    // Delete the .dcm original.
    await deleteImg(rowID, dcmName);
    // Delete the .png preview — swallow errors (may not exist yet).
    try {
      await deleteImg(rowID, '$dcmName.png');
    } catch (e, s) {
      effects.log(
          "deleteDcmImg: PNG preview not deleted (may not exist): $e", s);
    }
  }

  /// Uploads an image, deferring on failure. Returns the PB filename, or the
  /// client filename if deferred (the next sync corrects the model).
  Future<String> uploadImg({
    required String rowID,
    required String filename,
    String? path,
    XFile? file,
  }) =>
      _queuePersistence(() =>
          _uploadImg(rowID: rowID, filename: filename, path: path, file: file));

  Future<String> _uploadImg({
    required String rowID,
    required String filename,
    String? path,
    XFile? file,
  }) async {
    final local = this.local;
    final remote = this.remote;
    onSyncStart?.call();
    try {
      if (remote == null) {
        throw Exception("remote persistence layer is not defined");
      }
      if (local == null) {
        throw Exception("local persistence layer is not defined");
      }
      final lastDeferred = await local.getDeferred();
      if (remote.isOnline && lastDeferred.isEmpty) {
        try {
          final pbName = await remote.uploadImage(
            rowID: rowID,
            filename: filename,
            path: path,
            file: file,
          );
          unawaited(synchronize());
          return pbName;
        } catch (e, s) {
          effects.authenticationFailed(e);
          effects.reportError(e, "uploadingFile");
          effects.log("Error during upload (Will defer): $e", s);
        }
      }

      // Key: FILE||row||path||filename||retries → 1. Keep the XFile path when no
      // native path exists, or blob/web uploads cannot be retried.
      final deferredPath = path ?? file?.path ?? '';
      await local.putDeferred({
        ...lastDeferred,
        "FILE||$rowID||$deferredPath||$filename||0": 1,
      });
      deferredPresent = true;
      return filename;
    } finally {
      onSyncEnd?.call();
    }
  }

  /// notifies the view that the store has changed
  void notify() {
    observableMap.notifyView();
  }

  Future<void> waitUntilChangesAreProcessed() async {
    await Future<void>.delayed(Duration.zero);
    await _persistence.drain();
    await _sessionSave;
    if (local != null && changes.isNotEmpty) {
      throw StateError('Store changes could not be persisted');
    }
  }

  void _cleanDanglingFileRef(String rowID, String filename) {
    final model = observableMap.docs[rowID];
    if (model != null) {
      final json = model.toJson();
      var changed = false;
      for (final field in ['imgs', 'dcmImgs']) {
        final list = (json[field] as List?)?.cast<String>();
        if (list != null && list.remove(filename)) {
          if (list.isEmpty) {
            json.remove(field);
          } else {
            json[field] = list;
          }
          changed = true;
        }
      }
      if (changed) {
        observableMap.set(modeling(json));
      }
    }
    // DICOM listeners clear the import registry; otherwise the file stays
    // locked as imported and never reappears in the pending list.
    if (_isDcmFile(filename)) {
      for (final cb in List<void Function(String)>.from(onFileDeadLettered)) {
        cb(filename);
      }
    }
  }

  void _patchModelFilename(
      String rowID, String oldFilename, String newFilename) {
    final model = observableMap.docs[rowID];
    if (model == null) return;
    final json = model.toJson();
    var changed = false;
    for (final field in ['imgs', 'dcmImgs']) {
      final list = (json[field] as List?)?.cast<String>();
      if (list != null) {
        final idx = list.indexOf(oldFilename);
        if (idx != -1) {
          list[idx] = newFilename;
          json[field] = list;
          changed = true;
        }
      }
    }
    if (changed) {
      observableMap.set(modeling(json));
    }
  }

  // Inlined instead of importing lib/utils/imgs.dart, which would be circular.
  bool _isDcmFile(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.dcm') || lower.endsWith('.dicom');
  }

  // The model may still hold the pre-upload name, so list the PB-confirmed one.
  void _ensureDcmInModel(String rowID, String pbName) {
    final model = observableMap.docs[rowID];
    if (model == null) return;
    final json = model.toJson();
    final list = (json['dcmImgs'] as List?)?.cast<String>();
    if (list != null && !list.contains(pbName)) {
      list.add(pbName);
      json['dcmImgs'] = list;
      observableMap.set(modeling(json));
    } else if (list == null) {
      json['dcmImgs'] = [pbName];
      observableMap.set(modeling(json));
    }
  }

  // @visibleForTesting wrappers: Dart privacy is library-scoped, so tests in
  // other libraries need these to reach the private helpers.

  @visibleForTesting
  void debugCleanDanglingFileRef(String rowID, String filename) =>
      _cleanDanglingFileRef(rowID, filename);

  @visibleForTesting
  void debugPatchModelFilename(
          String rowID, String oldFilename, String newFilename) =>
      _patchModelFilename(rowID, oldFilename, newFilename);

  @visibleForTesting
  void debugEnsureDcmInModel(String rowID, String pbName) =>
      _ensureDcmInModel(rowID, pbName);

  @visibleForTesting
  bool debugIsDcmFile(String name) => _isDcmFile(name);

  @visibleForTesting
  Future<SyncResult> debugSyncTry() => _syncTry(_persistenceSession);
}

class _ConflictInfo {
  _ConflictInfo(
      {required this.dfID,
      required this.remoteConflictIndex,
      required this.localWins,
      required this.remoteData});
  final String dfID;
  final int remoteConflictIndex;
  final bool localWins;
  final String remoteData;
}

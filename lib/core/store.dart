import 'dart:async';
import 'dart:convert';
import 'package:apexo/common_widgets/error_dialog.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/notifications/static_notifications.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:apexo/services/notifications/model_push_data.dart';
import 'package:apexo/services/notifications/push_relay.dart';
import 'package:apexo/services/notifications/push_deferring.dart';
import 'package:apexo/utils/constants.dart';
import 'package:apexo/utils/logger.dart';
import 'package:http/http.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

import 'model.dart';
import 'observable.dart';
import 'save_local.dart';
import 'save_remote.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/utils/phone_numbers_extractor.dart';

typedef ModellingFunc<G> = G Function(Map<String, dynamic> input);

class SyncResult {
  int? pushed;
  int? pulled;
  int? conflicts;
  String? exception;
  SyncResult({this.pushed, this.pulled, this.conflicts, this.exception});
  @override
  toString() {
    return "pushed: $pushed, pulled: $pulled, conflicts: $conflicts, exception: $exception";
  }
}

/// A class that represents a store of documents
/// This implements observableDict
/// but adds ability to persist data as well as synchronize it with a remote server

class Store<G extends Model> {
  /// Callbacks invoked when a file upload permanently fails (dead-letter).
  /// DICOM code registers here to clear the import registry so the file
  /// can be re-discovered on the next directory scan.
  static final List<void Function(String filename)> onFileDeadLettered = [];

  late Future<void> loaded;
  final Function? onSyncStart;
  final Function? onSyncEnd;
  final ObservableDict<G> observableMap;
  final Set<DictEvent> changes = {};
  Map<String, G> archived = {};
  SaveLocal? local;
  SaveRemote? remote;
  Future<void> Function()? realtimeSub;
  final int debounceMS;
  late ModellingFunc<G> modeling;
  bool deferredPresent = false;
  int lastProcessChanges = 0;
  bool? manualSyncOnly;
  bool? isDemo;

  Store({
    required this.modeling,
    this.isDemo,
    this.local,
    this.remote,
    this.debounceMS = 100,
    this.onSyncStart,
    this.onSyncEnd,
    this.manualSyncOnly,
  }) : observableMap = ObservableDict() {
    // loading from local
    loaded = deleteMemoryAndLoadFromPersistence();
  }

  @mustCallSuper
  void init() {
    // setting up sync queue
    _setupSyncJobTimer();

    // setting up observers
    observableMap.observe((events) {
      if (events[0].type == DictEventType.modify &&
          events[0].id == "__ignore_view__") {
        // this is a view change not a storage change
        return;
      }

      for (final element in events) {
        final doc = element.document;
        if (doc == null) continue;
        if (doc.archived == true) {
          archived[doc.id] = doc as G;
        } else {
          archived.remove(doc.id);
        }
      }

      changes.addAll(events.where((c) => c.id != "__ignore_view__"));
      _processChanges();
    });
  }

  /// reloads the store from the local database
  /// DO NOT USE THIS METHOD UNLESS YOU'RE SURE THAT THERE ARE NO CHANGES PENDING TO BE SAVED
  /// use "reload" method instead
  Future<void> deleteMemoryAndLoadFromPersistence() async {
    if (local == null) {
      return;
    }
    final Map<String, String> all = (await local!.getAll());
    // Decode JSON strings in a background isolate
    final Map<String, Map<String, dynamic>> decoded =
        await compute(_decodeAllDocs, all);

    // Capture the ISO country code so the compute isolate can use it
    // for phone-number parsing (isolates don't share memory with main).
    final capturedIsoCC = isoCC();

    // model json maps to document in a background isolate
    final modellingResult = await compute(
        _modelAllDocs<G>,
        _ModelAllDocsParams(
            modeling: modeling, decoded: decoded, isoCC: capturedIsoCC));
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

  _processChanges() async {
    if (isDemo == true) notify();

    if (local == null) {
      return;
    }

    if (changes.isEmpty) return;
    if (observableMap.docs.isEmpty) return;

    onSyncStart?.call();
    lastProcessChanges = DateTime.now().millisecondsSinceEpoch;

    Map<String, String> toWrite = {};
    Map<String, int> toDefer = {};
    List<PushData> toPush = [];

    List<DictEvent> changesToProcess = [...changes];

    for (DictEvent e in changesToProcess) {
      G? item = observableMap.get(e.id);
      if (item == null) {
        changes.remove(e);
        continue;
      }
      String serialized = _serialize(item);
      toWrite[e.id] = serialized;
      toDefer[e.id] = lastProcessChanges;

      // push notifications processing
      final doc = e.document;

      if (remote == null) continue;
      if (doc == null) continue;
      if (e.type == DictEventType.remove) continue;
      if (e.type == DictEventType.add && doc.pushOnCreation == false) continue;
      if (e.type == DictEventType.modify &&
          !e.modifiedKeys.any((k) => doc.pushIfChanged.contains(k))) {
        continue;
      }
      final pushTargets = doc.targetsToPushTo;
      toPush.add(PushData(
        store: remote!.storeName,
        id: e.id,
        readableIdentifier: doc.title,
        isCreation: e.type == DictEventType.add,
        isUpdate: e.type == DictEventType.modify,
        updatedFields: e.modifiedKeys,
        oldVals: e.oldVals,
        newVals: e.newVals,
        targetIDs: pushTargets,
      ));
    }

    await local!.put(toWrite);

    if (remote == null) {
      changes.clear();
      onSyncEnd?.call();
      return;
    }

    Map<String, int> lastDeferred = await local!.getDeferred();
    if (remote!.isOnline && lastDeferred.isEmpty) {
      try {
        await remote!.put(toWrite.entries
            .map((e) => RowToWriteRemotely(id: e.key, data: e.value))
            .toList());
        changes.clear();

        await PushRelay.sendPush(toPush);

        onSyncEnd?.call();
        // while we have the connection lets synchronize
        // don't put "await" before synchronize() since we don't want catch the error
        // if it gets caught it means the same file will be placed in deferred
        if (manualSyncOnly != true) {
          // this condition is especially helpful during testing
          // to have fine grained control over synchronization steps
          synchronize();
        }
        return;
      } catch (e, s) {
        login.askForLoginAgain(e);
        showErrorMessage(e, "sendingUpdatesToServer");
        logger("Error during sending (Will defer updates): $e", s);
      }
    }

    /**
	 * If we reached here, it means that its either
	 * 1. we're offline
	 * 2. there was an error during sending updates
	 * 3. there are already deferred updates
	 */
    await local!.putDeferred({}
      ..addAll(lastDeferred)
      ..addAll(toDefer));

    if (toPush.isNotEmpty) {
      await deferredPush.putBulk(toPush);
    }
    deferredPresent = true;
    changes.clear();
    await reload();
    onSyncEnd?.call();
  }

  Future<SyncResult> _syncTry() async {
    if (isDemo == true) {
      return SyncResult(exception: "sync is disabled in demo mode");
    }
    if (local == null || remote == null) {
      return SyncResult(
          exception: "local/remote persistence layers are not defined");
    }

    if (remote!.isOnline == false) {
      return SyncResult(exception: "remote server is offline");
    }
    try {
      int localVersion = await local!.getVersion();
      int remoteVersion = await remote!.getVersion();

      Map<String, int> deferred = await local!.getDeferred();
      int conflicts = 0;

      if (localVersion == remoteVersion && deferred.isEmpty) {
        return SyncResult(exception: "nothing to sync");
      }

      // fetch updates since our local version
      VersionedResult remoteUpdates =
          await remote!.getSince(version: localVersion);

      if (remoteVersion == 0 &&
          localVersion > 0 &&
          remoteUpdates.rows.isEmpty) {
        // since the above condition usually happens when the token is expired,
        // we try to refresh the token
        // if this fails the authentication will throw an exception and the user will be asked to login again
        try {
          await login.authenticateWithToken(login.token);
        } catch (e) {
          login.askForLoginAgain(e);
          return SyncResult(exception: "Failed to refresh token: $e");
        }
      }

      List<int> remoteLosersIndices = [];

      // check conflicts: last write wins
      // Collect merged results for conflicting records.  Each conflict is
      // field-level-merged (see [mergeConflict]) rather than discarding one
      // entire version.  The merged JSON goes to BOTH local and remote.
      final Map<String, String> mergedConflictsToLocal = {};
      final Map<String, String> mergedConflictsToRemote = {};

      // First pass: identify conflicts synchronously (removeWhere's
      // callback cannot be async).  Collect the data needed for merging.
      final List<_ConflictInfo> conflictsFound = [];
      deferred.removeWhere((dfID, deferredTimeStamp) {
        int remoteConflictIndex =
            remoteUpdates.rows.indexWhere((r) => r.id == dfID);
        if (remoteConflictIndex == -1) {
          // no conflict
          return false;
        }
        int remoteTimeStamp = remoteUpdates.rows[remoteConflictIndex].ts;
        final bool localWins = deferredTimeStamp > remoteTimeStamp;
        conflictsFound.add(_ConflictInfo(
          dfID: dfID,
          remoteConflictIndex: remoteConflictIndex,
          localWins: localWins,
          remoteData: remoteUpdates.rows[remoteConflictIndex].data,
        ));
        conflicts++;
        // Remove the conflicting remote row from the pull set — the
        // merged version is written to local directly below.
        remoteLosersIndices.add(remoteConflictIndex);
        // Remove from deferred — the merged version is pushed to remote
        // directly below.
        return true;
      });

      // Second pass: async field-level merge for each conflict.
      final pendingUploadsAll =
          filenamesFromDeferred(deferred).where((f) => f.isNotEmpty).toSet();
      for (final c in conflictsFound) {
        final localJson =
            jsonDecode(await local!.get(c.dfID)) as Map<String, dynamic>;
        final remoteJson = jsonDecode(c.remoteData) as Map<String, dynamic>;
        final serverFiles = remote!.fullNamesCache[c.dfID] ?? const <String>[];

        final mergedJson = mergeConflict(
          localJson: localJson,
          remoteJson: remoteJson,
          localWins: c.localWins,
          serverFiles: serverFiles,
          pendingUploads: pendingUploadsAll,
        );

        final mergedStr = jsonEncode(mergedJson);
        mergedConflictsToLocal[c.dfID] = mergedStr;
        mergedConflictsToRemote[c.dfID] = mergedStr;
      }

      // remove losers from remote updates
      // Sort indices in descending order
      remoteLosersIndices.sort((a, b) => b.compareTo(a));
      for (int index in remoteLosersIndices) {
        remoteUpdates.rows.removeAt(index);
      }

      Map<String, String> toLocalWrite = Map.fromEntries(
          remoteUpdates.rows.map((r) => MapEntry(r.id, r.data)));

      // Merge in field-level-merged conflict results (these override any
      // remote-only row of the same ID, but conflicting IDs were already
      // removed from remoteUpdates above via remoteLosersIndices).
      toLocalWrite.addAll(mergedConflictsToLocal);

      // those will be built in the for loop below
      Map<String, String> toRemoteWrite = {};

      final List<Future Function()> fileHandling = [];
      // Track FILE keys whose upload succeeds so we can safely clear
      // them at the end without wiping re-queued failure entries.
      final succeededFileKeys = <String>{};

      for (var entry in deferred.entries) {
        if (entry.key.startsWith("FILE")) {
          List<String> deferredFile = entry.key.split("||");
          final bool upload = entry.value == 1;
          final String rowID = deferredFile[1];
          final String pathOrName = deferredFile[2];
          final String filename =
              deferredFile.length >= 4 ? deferredFile[3] : "";
          final int retries = parseDeferredRetries(entry.key);
          const maxRetries = 5;
          final newKey = buildDeferredRetryKey(entry.key, retries + 1);

          // we will delay file handling since it takes too much time
          // so we would run the document handling first then the file handling
          fileHandling.add(() async {
            if (upload) {
              // Dead-letter: too many retries.
              if (retries >= maxRetries) {
                logger(
                    'Deferred upload: permanently failed for '
                    '"$filename" after $retries retries — removing from model',
                    null,
                    1);
                _cleanDanglingFileRef(rowID, filename);
                succeededFileKeys.add(entry.key);
                return;
              }

              MultipartFile multipart;
              if (!pathOrName.startsWith("http")) {
                multipart = await MultipartFile.fromPath(
                  "imgs+",
                  pathOrName,
                  filename: filename,
                );
              } else {
                multipart = MultipartFile.fromBytes(
                  "imgs+",
                  (await http.get(Uri.parse(
                          'https://imgs.apexo.app/?url=${Uri.encodeComponent(pathOrName)}')))
                      .bodyBytes,
                  filename: filename,
                );
              }
              try {
                final pbName = await remote!.uploadImage(
                  rowID: rowID,
                  filename: filename,
                  predefinedMultipart: multipart,
                );
                // PB may assign a different name — patch the model first
                // so _ensureDcmInModel sees the correct name and avoids
                // creating a duplicate entry.
                if (pbName != filename) {
                  _patchModelFilename(rowID, filename, pbName);
                }
                // DICOM files: ensure the model's dcmImgs lists the
                // PB-confirmed filename.
                if (_isDcmFile(pbName)) {
                  _ensureDcmInModel(rowID, pbName);
                }
                // Mark this entry as successfully uploaded so it gets
                // cleaned up at the end of the sync cycle.
                succeededFileKeys.add(entry.key);
              } catch (e, s) {
                // Upload failed — keep in queue with incremented retries.
                logger(
                    'Deferred upload: attempt ${retries + 1}/$maxRetries '
                    'failed for "$filename" — $e',
                    s,
                    1);
                final currentDeferred = await local!.getDeferred();
                currentDeferred.remove(entry.key);
                currentDeferred[newKey] = 1;
                await local!.putDeferred(currentDeferred);
              }
            } else {
              await remote!.deleteImage(rowID, pathOrName);
            }
          });
        } else {
          toRemoteWrite.addAll({entry.key: await local!.get(entry.key)});
        }
      }

      // Add field-level-merged conflict results to the remote write set.
      // These were removed from `deferred` above and need to be pushed.
      toRemoteWrite.addAll(mergedConflictsToRemote);

      if (toLocalWrite.isNotEmpty) {
        await local!.put(toLocalWrite);
      }
      if (toRemoteWrite.isNotEmpty) {
        await remote!.put(toRemoteWrite.entries
            .map((e) => RowToWriteRemotely(id: e.key, data: e.value))
            .toList());

        final winningPushes = (await Future.wait(toRemoteWrite.keys.map(
          (k) async => await deferredPush.getByID(k),
        )))
            .where((x) => x != null)
            .cast<PushData>()
            .toList();

        await PushRelay.sendPush(winningPushes);
        await deferredPush.clearByStore(remote!.storeName);
      }

      // when all json related updates are done, we can handle files
      await Future.wait(fileHandling.map((f) => f()));

      // Clean up deferred entries that were successfully processed.
      // - Non-FILE entries were handled via toRemoteWrite above.
      // - Succeeded FILE entries are tracked in succeededFileKeys.
      // - Failed FILE entries were re-queued with incremented retries
      //   by the catch block — those must NOT be cleared here.
      final currentDeferred = await local!.getDeferred();
      currentDeferred.removeWhere(
          (k, _) => !k.startsWith("FILE") || succeededFileKeys.contains(k));
      await local!.putDeferred(currentDeferred);
      deferredPresent = currentDeferred.isNotEmpty;

      // set local version to the version given by the current request
      // this might be outdated as soon as this functions ends
      // that's why this function will run on a while loop (below)
      await local!.putVersion(remoteUpdates.version);

      // but if we had deferred updates then the remoteUpdates.version is outdated
      // so we need to fetch the latest version again
      // however, we should not do this in the same run since there might be updates
      // from another client between the time we fetched the remoteUpdates and the
      // time we sent deferred updates
      // so every sync should be followed by another sync
      // until the versions match
      // this is why there's another sync method below

      // finally show a notification if the store or model has something notification worthy

      if (docs.isNotEmpty) {
        // only do this if there were already docs
        for (var element in toLocalWrite.entries) {
          final id = element.key;
          final document = modeling(jsonDecode(element.value));
          if (!document.targetsToPushTo.contains(login.currentAccountID)) {
            continue;
          }

          if (modeling({}).pushOnCreation && !docs.containsKey(id)) {
            final readableIdentifier = document.title;

            List<String> displayTuple = PushData(
              store: remote!.storeName,
              id: id,
              readableIdentifier: readableIdentifier,
              isCreation: true,
              isUpdate: false,
              updatedFields: [],
              oldVals: [],
              newVals: [],
              targetIDs: [],
            ).displayTuple();

            await staticNotifications.dingANotification(
              title: displayTuple[0],
              body: displayTuple[1],
              icon: WindowsIcons.add,
            );
          } else if (document.pushIfChanged.isNotEmpty) {
            final oldJson = docs[id]!.toJson();
            final newJson = document.toJson();
            final diff = diffJson(oldJson, newJson).toList();
            if (diff.isEmpty) {
              continue;
            }
            final readableIdentifier = document.title;
            List<String> displayTuple = PushData(
              store: remote!.storeName,
              id: id,
              readableIdentifier: readableIdentifier,
              isCreation: false,
              isUpdate: true,
              updatedFields: diff,
              oldVals: diff.map((key) => oldJson[key]).toList(),
              newVals: diff.map((key) => newJson[key]).toList(),
              targetIDs: [],
            ).displayTuple();

            await staticNotifications.dingANotification(
              title: displayTuple[0],
              body: displayTuple[1],
              icon: FluentIcons.edit,
            );
          }
        }
      }

      await reload();

      return SyncResult(
          pulled: toLocalWrite.length,
          pushed: toRemoteWrite.length,
          conflicts: conflicts,
          exception: null);
    } catch (e, s) {
      login.askForLoginAgain(e);
      logger("Error during synchronization: $e", s);
      return SyncResult(exception: e.toString());
    }
  }

  // the following logic is for the task management of synchronization
  // it's not really a task runner,
  // since it allows only for one task to be in the que with no concurrency
  // any task that would be added will override the previous one

  bool _jobRunning = false;
  void _setupSyncJobTimer() {
    // the following timer would run indefinitely,
    // checking whether there's a sync job exists or not
    Timer.periodic(Duration(milliseconds: debounceMS), (timer) async {
      if (_jobRunning) {
        return;
      }
      _jobRunning = true;
      try {
        if (_syncJob != null) {
          await _syncJob!();
          _syncJob = null;
        }
      } catch (e, s) {
        login.askForLoginAgain(e);
        logger("Error during synchronization: $e", s);
      }
      _jobRunning = false;
    });
  }

  // holds the next job
  Future<void> Function()? _syncJob;
  // holds the result of the last job that ran
  List<SyncResult>? lastRes;

  // ----------------------------- Public API --------------------------------

  void cancelRealtimeSub() {
    if (realtimeSub != null) {
      // cancel the subscription once we go offline
      realtimeSub!();
      // and set this to null so that we get to subscribe again when we go online
      realtimeSub = null;
    }
  }

  /// Syncs the local database with the remote database
  Future<List<SyncResult>> synchronize() async {
    // this would only register a job
    // and wait patiently for its result
    // if runs out of patience
    // then it would steal the last result
    // and shows as its own
    // pretty weird... but it works
    List<SyncResult>? res;
    final sw = Stopwatch();
    sw.start();
    _syncJob = () async {
      res = await _syncRequest();
      lastRes = res;
    };
    while (res == null && sw.elapsed.inSeconds < 10) {
      await Future.delayed(Duration(milliseconds: debounceMS));
    }
    return res ?? lastRes ?? [];
  }

  Future<List<SyncResult>> _syncRequest() async {
    // this would run multiple tries to be in sync with the server
    // why multiple tries?
    // well... if it gives the server data then it would outdate itself
    // since the server is the one issues the version numbers
    // so when it gives the server somethings
    // it would need pull the same thing that it gave (to have its version)
    // finally when it sees that the local and the remote version match
    // it would end
    // check the while loop below for more.

    // regardless of that... on first sync
    // we need to set up the realtime subscription
    if (remote != null && realtimeSub == null && manualSyncOnly != true) {
      remote?.pbInstance.collection(dataCollectionName).subscribe("*", (msg) {
        if (msg.record?.data["store"] == remote?.storeName) {
          synchronize();
        }
      }).then((cancellation) {
        realtimeSub = cancellation;
      }).catchError((e, s) {
        login.askForLoginAgain(e);
        logger("Error during realtime subscription: $e", s);
      });
    }

    lastProcessChanges = DateTime.now().millisecondsSinceEpoch;
    onSyncStart?.call();
    List<SyncResult> tries = [];
    while (true) {
      SyncResult result = await _syncTry();
      tries.add(result);
      if (result.exception != null) break;
    }
    onSyncEnd?.call();
    return tries;
  }

  //// Returns true if the local database is in sync with the remote database
  Future<bool> inSync() async {
    try {
      if (local == null || remote == null) return false;
      if (deferredPresent) return false;
      return await local!.getVersion() == await remote!.getVersion();
    } catch (e, s) {
      login.askForLoginAgain(e);
      logger("Error during inSync check: $e", s);
      return false;
    }
  }

  /// Reloads the store from the local database
  Future<void> reload() async {
    // wait for any changes to be processed, since we're going to delete the dictionary
    await Future.delayed(Duration(milliseconds: debounceMS + 2));
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
    G? item = get(id);
    if (item == null) return;
    observableMap.set(item..archived = true);
    archived[id] = item;
  }

  /// un-archives a document by id (the concept of deletion is not supported here)
  void unarchive(String id) {
    G? item = get(id);
    if (item == null) return;
    observableMap.set(item..archived = false);
    archived.remove(id);
  }

  /// archives a document by id (the concept of deletion is not supported here)
  void delete(String id) {
    archive(id);
  }

  /// delete an image
  Future<void> deleteImg(String rowID, String name) async {
    onSyncStart?.call();
    if (remote == null) {
      throw Exception("remote persistence layer is not defined");
    }
    if (local == null) {
      throw Exception("local persistence layer is not defined");
    }
    Map<String, int> lastDeferred = await local!.getDeferred();
    if (remote!.isOnline && lastDeferred.isEmpty) {
      try {
        await remote!.deleteImage(rowID, name);
        onSyncEnd?.call();
        synchronize();
        return;
      } catch (e, s) {
        showErrorMessage(e, "deletingFile");
        login.askForLoginAgain(e);
        logger("Error during deleting the file (Will defer upload): $e", s);
      }
    }

    /**
     * If we reached here it means that its either
     * 1. we're offline
     * 2. there was an error during sending updates
     * 3. there are already deferred updates
     */
    // DEFERRED Structure: "FILE||{rowID}||path:{0 for deleting, 1 for uploading}"

    await local!.putDeferred({}
      ..addAll(lastDeferred)
      ..addAll({"FILE||$rowID||$name": 0}));
    deferredPresent = true;
    onSyncEnd?.call();
  }

  /// Deletes a DCM X-ray and its PNG preview from PocketBase.
  ///
  /// Calls [deleteImg] for both the `.dcm` original and the `${dcmName}.png`
  /// preview. If the PNG doesn't exist yet (still queued or generation
  /// failed), the error for that call is swallowed — the `.dcm` deletion
  /// still proceeds.
  ///
  /// The caller is responsible for removing `dcmName` from the model's
  /// `dcmImgs` list and calling `set(model)`.
  Future<void> deleteDcmImg(String rowID, String dcmName) async {
    // Delete the .dcm original.
    await deleteImg(rowID, dcmName);
    // Delete the .png preview — swallow errors (may not exist yet).
    try {
      await deleteImg(rowID, '$dcmName.png');
    } catch (e, s) {
      logger("deleteDcmImg: PNG preview not deleted (may not exist): $e", s);
    }
  }

  /// Upload an image with deferred retry support.
  /// Returns the PB-assigned filename on success, or the client filename
  /// if the upload was deferred (model will be corrected by next sync).
  Future<String> uploadImg({
    required String rowID,
    required String filename,
    String? path,
    XFile? file,
  }) async {
    onSyncStart?.call();
    if (remote == null) {
      throw Exception("remote persistence layer is not defined");
    }
    if (local == null) {
      throw Exception("local persistence layer is not defined");
    }
    final lastDeferred = await local!.getDeferred();
    if (remote!.isOnline && lastDeferred.isEmpty) {
      try {
        final pbName = await remote!.uploadImage(
          rowID: rowID,
          filename: filename,
          path: path,
          file: file,
        );
        onSyncEnd?.call();
        synchronize();
        return pbName;
      } catch (e, s) {
        login.askForLoginAgain(e);
        showErrorMessage(e, "uploadingFile");
        logger("Error during upload (Will defer): $e", s);
      }
    }

    // Defer: "FILE||{rowID}||{path}||{filename}||{retries}" → 1 (upload)
    await local!.putDeferred({
      ...lastDeferred,
      "FILE||$rowID||${path ?? ''}||$filename||0": 1,
    });
    deferredPresent = true;
    onSyncEnd?.call();
    return filename;
  }

  /// notifies the view that the store has changed
  void notify() {
    observableMap.notifyView();
  }

  Future<void> waitUntilChangesAreProcessed() async {
    await Future.delayed(Duration(milliseconds: debounceMS + 2));
    while (changes.isNotEmpty) {
      await Future.delayed(const Duration(milliseconds: 30));
    }
  }

  /// Remove a dangling file reference from the local model after permanent
  /// upload failure (retries exhausted or local file deleted).
  void _cleanDanglingFileRef(String rowID, String filename) {
    final model = observableMap.docs[rowID];
    if (model == null) return;
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
    // If this was a DICOM file, notify listeners so the import registry
    // can be cleared — otherwise the file stays locked as "imported" and
    // never re-appears in the pending list.
    if (_isDcmFile(filename)) {
      for (final cb in onFileDeadLettered) {
        cb(filename);
      }
    }
  }

  /// After a deferred upload succeeds, PB may assign a different filename
  /// (e.g. collision suffix). Update the local model so other devices see
  /// the correct filename.
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

  /// True when [name] ends with `.dcm` or `.dicom` (case-insensitive).
  /// Inlined here to avoid a circular dependency on `lib/utils/imgs.dart`.
  bool _isDcmFile(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.dcm') || lower.endsWith('.dicom');
  }

  /// Ensures [pbName] is listed in the model's `dcmImgs` field.
  ///
  /// Called after a deferred DICOM upload succeeds — at this point the file
  /// is confirmed on PB but the model may not yet advertise it in `dcmImgs`
  /// (because [DicomImporter.approveImport] intentionally deferred the
  /// `dcmImgs` update until the upload is confirmed).
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

  // ── @visibleForTesting wrappers ───────────────────────────────────
  // Dart privacy is library-scoped, not class-scoped. These thin public
  // wrappers let unit tests in other libraries exercise the logic without
  // making the helpers part of the public API.

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

  // ── Static helpers (extracted from _syncTry / _healDanglingDcmImgs) ─

  /// Returns the retry count embedded in a deferred FILE key, or 0 for
  /// legacy 4-segment keys.  Format: `FILE||rowID||path||filename||retries`.
  @visibleForTesting
  static int parseDeferredRetries(String key) {
    final parts = key.split('||');
    if (parts.length >= 5) return int.tryParse(parts[4]) ?? 0;
    return 0;
  }

  /// Builds a new deferred FILE key with [newRetries] substituted into the
  /// retries slot.  Legacy 4-segment keys grow a 5th segment; 5+-segment
  /// keys overwrite the last segment.
  @visibleForTesting
  static String buildDeferredRetryKey(String key, int newRetries) {
    final parts = key.split('||');
    final next = newRetries.toString();
    if (parts.length > 4) {
      parts[4] = next;
    } else {
      parts.add(next);
    }
    return parts.join('||');
  }

  /// Extracts the filename (segment index 3) from every `FILE||…` key in
  /// [deferred] whose value indicates an upload (value == 1).  Delete
  /// entries (value == 0 / 3-segment keys) produce empty strings and are
  /// harmless in the returned set.
  ///
  /// Used by [DicomController._healDanglingDcmImgs] to skip filenames that
  /// are currently queued for upload.
  @visibleForTesting
  static Set<String> filenamesFromDeferred(Map<String, int> deferred) {
    return deferred.keys
        .where((k) => k.startsWith('FILE') && (deferred[k] ?? 0) == 1)
        .map((k) {
      final parts = k.split('||');
      return parts.length >= 4 ? parts[3] : '';
    }).toSet();
  }

  /// Field names that store image filenames in the model JSON.  These are
  /// reconciled against the server's actual file list during merge instead
  /// of being union/LWW-merged, because PocketBase's `imgs` column is the
  /// authoritative source of which files exist.
  static const _imageFields = ['imgs', 'dcmImgs'];

  /// Map fields (tooth notes, drawings) that are merged per-key with
  /// last-writer-wins for same-key conflicts.  This lets two devices edit
  /// *different* keys (e.g. different teeth) without losing either edit.
  static const _mapFields = ['teeth', 'teethExtraNotes', 'drawings'];

  /// List fields that are merged by union with dedup.  Only fields whose
  /// semantics are additive (multi-assignment) belong here.
  static const _unionListFields = ['operatorsIDs'];

  /// List fields that are NOT merged — they keep whole-field LWW.
  /// Free-text lists edited via whole-list replacement (tags,
  /// prescriptions) are unsafe to union because deletions are expressed
  /// only by absence and would be silently un-deleted.
  static const _lwwListFields = ['tags', 'prescriptions'];

  /// Merges two JSON representations of the same record after a sync
  /// conflict, instead of discarding one entire version.
  ///
  /// Strategies per field type (see the field sets above):
  /// - **Scalar fields**: union — a field present on one side (and
  ///   default-absent on the other) is kept.  When both sides have a
  ///   non-default value that differs, last-write-wins by [localWins].
  /// - **`imgs`/`dcmImgs`**: reconciled against [serverFiles] (the PB
  ///   `imgs` column), which is the authoritative source of which files
  ///   exist.  Filenames in [pendingUploads] are kept even if not yet on
  ///   the server (deferred uploads).
  /// - **Map fields** (`teeth`, `teethExtraNotes`, `drawings`): per-key
  ///   LWW — different keys survive from both sides; same-key conflict
  ///   resolved by [localWins].
  /// - **`operatorsIDs`**: union with dedup (additive semantics).
  /// - **`tags`/`prescriptions`**: whole-field LWW (no merge).
  ///
  /// [localJson]/[remoteJson] are the full `toJson()` output for each
  /// side.  [localWins] selects the winner for same-field/same-key
  /// conflicts.  [serverFiles] is the list of filenames PB actually has
  /// for this record (may be empty).  [pendingUploads] is the set of
  /// filenames queued for deferred upload to this record.
  ///
  /// Returns the merged JSON map.
  @visibleForTesting
  static Map<String, dynamic> mergeConflict({
    required Map<String, dynamic> localJson,
    required Map<String, dynamic> remoteJson,
    required bool localWins,
    List<String> serverFiles = const [],
    Set<String> pendingUploads = const {},
  }) {
    final winner = localWins ? localJson : remoteJson;
    final loser = localWins ? remoteJson : localJson;
    final merged = <String, dynamic>{};

    // Union of all keys across both sides.
    final allKeys = <String>{...localJson.keys, ...remoteJson.keys};

    for (final key in allKeys) {
      // `id` is always present and identical — take it from either side.
      if (key == 'id') {
        merged['id'] = localJson['id'] ?? remoteJson['id'];
        continue;
      }

      final localVal = localJson[key];
      final remoteVal = remoteJson[key];
      final localHas = localJson.containsKey(key);
      final remoteHas = remoteJson.containsKey(key);

      // ── Image fields: reconcile against the server's actual files ──
      if (_imageFields.contains(key)) {
        merged[key] = _mergeImageField(
          localVal: localVal,
          remoteVal: remoteVal,
          serverFiles: serverFiles,
          pendingUploads: pendingUploads,
          isDcm: key == 'dcmImgs',
        );
        continue;
      }

      // ── Map fields: per-key LWW ──
      if (_mapFields.contains(key)) {
        final localMap = _toStringMap(localVal);
        final remoteMap = _toStringMap(remoteVal);
        // Winner's keys win for same-key conflicts; loser's distinct
        // keys survive.  This preserves deletions on the winning side
        // (a deleted key is simply absent from the winner's map).
        final mapKeys = <String>{...localMap.keys, ...remoteMap.keys};
        final mergedMap = <String, String>{};
        for (final mk in mapKeys) {
          if (winner.containsKey(key) && winner[key] is Map) {
            // Winner takes precedence for keys it has.
            final wMap = _toStringMap(winner[key]);
            if (wMap.containsKey(mk)) {
              mergedMap[mk] = wMap[mk]!;
              continue;
            }
          }
          // Otherwise take from whichever side has it.
          if (localMap.containsKey(mk)) {
            mergedMap[mk] = localMap[mk]!;
          } else if (remoteMap.containsKey(mk)) {
            mergedMap[mk] = remoteMap[mk]!;
          }
        }
        if (mergedMap.isNotEmpty) merged[key] = mergedMap;
        continue;
      }

      // ── Union list fields (operatorsIDs): union with dedup ──
      if (_unionListFields.contains(key)) {
        final localList = _toStringList(localVal);
        final remoteList = _toStringList(remoteVal);
        final union = <String>{
          ...localList,
          ...remoteList,
        }.toList();
        if (union.isNotEmpty) merged[key] = union;
        continue;
      }

      // ── LWW list fields (tags, prescriptions) & all other scalars ──
      // Whole-field LWW: take the winner's value if present, else the
      // loser's.  This also covers `date` (always present → winner wins)
      // and scalar fields like `name`/`phone`/`age`.
      if (winner.containsKey(key)) {
        merged[key] = winner[key];
      } else if (loser.containsKey(key)) {
        merged[key] = loser[key];
      }
    }

    return merged;
  }

  /// Merges an image-filename list field (`imgs`/`dcmImgs`) by taking the
  /// union of local and remote model lists, then keeping only filenames
  /// that either (a) exist on the server ([serverFiles]) or (b) are
  /// pending upload ([pendingUploads]).  [isDcm] filters the server list
  /// to DICOM vs regular images.
  static List<String> _mergeImageField({
    required dynamic localVal,
    required dynamic remoteVal,
    required List<String> serverFiles,
    required Set<String> pendingUploads,
    required bool isDcm,
  }) {
    final localList = _toStringList(localVal);
    final remoteList = _toStringList(remoteVal);
    final candidates = <String>{...localList, ...remoteList};

    // The server's `imgs` column holds BOTH regular images and DICOM
    // files in one list.  Filter to the relevant subtype.
    final serverRelevant = serverFiles
        .where(isDcm ? _isDcmFileStatic : _isNotDcmFileStatic)
        .toSet();

    final kept = <String>[];
    for (final name in candidates) {
      // Keep if the server actually has the file, or if it's pending
      // upload (deferred FILE entry not yet processed).
      if (serverRelevant.contains(name) || pendingUploads.contains(name)) {
        kept.add(name);
      }
    }
    return kept;
  }

  static bool _isDcmFileStatic(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.dcm') || lower.endsWith('.dicom');
  }

  static bool _isNotDcmFileStatic(String name) => !_isDcmFileStatic(name);

  static Map<String, String> _toStringMap(dynamic val) {
    if (val is Map) {
      return val.map((k, v) => MapEntry(k.toString(), v.toString()));
    }
    return {};
  }

  static List<String> _toStringList(dynamic val) {
    if (val is List) {
      return val.map((e) => e.toString()).toList();
    }
    return [];
  }
}

// The following two functions
// are meant to be running on an isolate
// that's why they are top-level
// they are meant to to run jsonDecode
// and modelling on large batches of data

/// Internal record used during conflict resolution in [_syncTry].
/// Collects the data needed for the async field-level merge pass.
class _ConflictInfo {
  final String dfID;
  final int remoteConflictIndex;
  final bool localWins;
  final String remoteData;
  _ConflictInfo({
    required this.dfID,
    required this.remoteConflictIndex,
    required this.localWins,
    required this.remoteData,
  });
}

Map<String, Map<String, dynamic>> _decodeAllDocs(Map<String, String> encoded) {
  return Map<String, Map<String, dynamic>>.fromEntries(encoded.entries.map(
      (entry) => MapEntry(
          entry.key, jsonDecode(entry.value) as Map<String, dynamic>)));
}

class _ModelAllDocsParams<G extends Model> {
  final ModellingFunc<G> modeling;
  final Map<String, Map<String, dynamic>> decoded;
  final String isoCC;
  _ModelAllDocsParams({
    required this.modeling,
    required this.decoded,
    required this.isoCC,
  });
}

List<Map<String, G>> _modelAllDocs<G extends Model>(
    _ModelAllDocsParams<G> params) {
  // Make the ISO country code available to PhoneNumberExtractor inside
  // this compute isolate (the reactive globalSettings store is not
  // accessible here).
  setIsoCountryCodeForIsolate(params.isoCC);
  final Map<String, G> archived = {};
  final mapped = Map<String, G>.fromEntries(params.decoded.entries.map((entry) {
    final modeled = params.modeling(entry.value);
    if (modeled.archived == true) {
      archived[modeled.id] = modeled;
    }
    return MapEntry(entry.key, modeled);
  }));
  return [mapped, archived];
}

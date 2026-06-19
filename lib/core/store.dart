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
      deferred.removeWhere((dfID, deferredTimeStamp) {
        int remoteConflictIndex =
            remoteUpdates.rows.indexWhere((r) => r.id == dfID);
        if (remoteConflictIndex == -1) {
          // no conflict
          return false;
        }
        int remoteTimeStamp = remoteUpdates.rows[remoteConflictIndex].ts;
        if (deferredTimeStamp > remoteTimeStamp) {
          // local update wins
          conflicts++;
          remoteLosersIndices.add(remoteConflictIndex);
          return false;
        } else {
          // remote update wins
          // return true to remove this item from deferred
          conflicts++;
          return true;
        }
      });

      // remove losers from remote updates
      // Sort indices in descending order
      remoteLosersIndices.sort((a, b) => b.compareTo(a));
      for (int index in remoteLosersIndices) {
        remoteUpdates.rows.removeAt(index);
      }

      Map<String, String> toLocalWrite = Map.fromEntries(
          remoteUpdates.rows.map((r) => MapEntry(r.id, r.data)));

      // those will be built in the for loop below
      Map<String, String> toRemoteWrite = {};

      final List<Future Function()> fileHandling = [];

      for (var entry in deferred.entries) {
        if (entry.key.startsWith("FILE")) {
          List<String> deferredFile = entry.key.split("||");
          final bool upload = entry.value == 1;
          final String rowID = deferredFile[1];
          final String pathOrName = deferredFile[2];
          final String fileName =
              deferredFile.length == 4 ? deferredFile[3] : "";
          // we will delay file handling since it takes too much time
          // so we would run the document handling first then the file handling
          fileHandling.add(() async {
            if (upload) {
              MultipartFile multipart;
              if (!pathOrName.startsWith("http")) {
                multipart = await MultipartFile.fromPath(
                  "imgs+",
                  pathOrName,
                  filename: fileName,
                );
              } else {
                multipart = MultipartFile.fromBytes(
                  "imgs+",
                  (await http.get(Uri.parse(
                          'https://imgs.apexo.app/?url=${Uri.encodeComponent(pathOrName)}')))
                      .bodyBytes,
                  filename: fileName,
                );
              }
              await remote!.uploadImage(rowID, multipart);
            } else {
              await remote!.deleteImage(rowID, pathOrName);
            }
          });
        } else {
          toRemoteWrite.addAll({entry.key: await local!.get(entry.key)});
        }
      }

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

      // reset deferred
      await local!.putDeferred({});
      deferredPresent = false;

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

  /// upload set of files to a certain row
  Future<void> uploadImg(
      {required String rowID,
      required String filename,
      String? path,
      XFile? file}) async {
    if (path == null && file == null) {
      throw Exception("either path or file must be defined when uploading");
    }
    if (remote == null) {
      throw Exception("remote persistence layer is not defined");
    }
    if (local == null) {
      throw Exception("local persistence layer is not defined");
    }
    onSyncStart?.call();

    Map<String, int> lastDeferred = await local!.getDeferred();

    if (remote!.isOnline && lastDeferred.isEmpty) {
      try {
        MultipartFile multipart;
        if (path != null) {
          multipart = await MultipartFile.fromPath(
            "imgs+",
            path,
            filename: filename,
          );
        } else {
          multipart = MultipartFile.fromBytes(
            "imgs+",
            (await http.get(file!.path.startsWith("blob")
                    ? Uri.parse(file.path)
                    : Uri.parse(
                        'https://imgs.apexo.app/?url=${Uri.encodeComponent(file.path)}')))
                .bodyBytes,
            filename: filename,
          );
        }
        await remote!.uploadImage(rowID, multipart);
        onSyncEnd?.call();
        synchronize();
        return;
      } catch (e, s) {
        login.askForLoginAgain(e);
        showErrorMessage(e, "uploadingFile");
        logger("Error during sending the file (Will defer upload): $e", s);
      }
    }

    /**
     * If we reached here it means that its either
     * 1. we're offline
     * 2. there was an error during sending updates
     * 3. there are already deferred updates
     */
    // DEFERRED Structure: "FILE||{rowID}||path:{0 for deleting, 1 for uploading}"
    final valueToDefer = path ?? file!.path;
    await local!.putDeferred({}
      ..addAll(lastDeferred)
      ..addAll({"FILE||$rowID||$valueToDefer||$filename": 1}));
    deferredPresent = true;
    onSyncEnd?.call();
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
}

// The following two functions
// are meant to be running on an isolate
// that's why they are top-level
// they are meant to to run jsonDecode
// and modelling on large batches of data
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

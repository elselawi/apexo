import 'package:apexo/app/data/application_store_effects.dart';
import 'package:apexo/app/data/store_session_binding.dart';
import 'package:apexo/core/reactive/observable.dart';
import 'package:apexo/services/launch.dart';
import 'package:apexo/utils/constants.dart';
import 'package:apexo/utils/demo_generator.dart' show demoNotes;
import '../network_actions/network_actions_controller.dart';
import '../../services/login.dart';
import 'notes_model.dart';
import '../../core/store.dart';

const _storeName = "notes";

class Notes extends Store<Note> {
  Notes()
      : super(
          effects: applicationStoreEffects,
          loadDocuments: loadApplicationDocuments,
          modeling: Note.fromJson,
          isDemo: launch.isDemo,
          onSyncStart: () {
            networkActions.isSyncing(networkActions.isSyncing() + 1);
          },
          onSyncEnd: () {
            networkActions.isSyncing(networkActions.isSyncing() - 1);
          },
        );
  // Parent-to-children index for faster childInstances lookup
  final Map<String, List<String>> _parentToChildren = {};
  bool _indexBuilt = false;

  late final _session = StoreSessionBinding<Note>(
    store: this, name: _storeName,
    loadingMessage: 'Synchronizing notes',
    seedDemo: () => demoNotes(100),
  );

  @override
  void init() {
    super.init();
    _session.install();

    // Observe store changes to update indexes
    observableMap.observe((_) {
      _rebuildIndex();
    });


  }

  List<Note> get columns {
    return List<Note>.from(present.values.where((e) => e.isColumn))
      ..sort((a, b) => a.order.compareTo(b.order));
  }

  List<Note> ghostCreatorsInColumn(String columnID) {
    return docs.values.where((n) {
      if (n.columnID != columnID) return false;
      if (!n.deservesRecurrence) return false;
      if (login.perm(Perm.notes).none &&
          !login.isAdmin &&
          n.createdBy != login.currentAccountID &&
          n.assignedTo != login.currentAccountID) {
        return false;
      }
      return true;
    }).toList();
  }

  final showIncoming = ObservableState(false);
  final filterByAccountId = ObservableState("");
  final sortDirection = ObservableState(1);

  Map<String, Note> get filtered {
    if (login.perm(Perm.notes).none && !login.isAdmin) {
      filterByAccountId(login.currentAccountID);
    }
    if (filterByAccountId().isEmpty && showIncoming() == false) return present;
    return Map<String, Note>.fromEntries(present.entries.where((entry) =>
        (showIncoming() == false || entry.value.incoming) &&
        (filterByAccountId().isEmpty ||
            entry.value.createdBy == filterByAccountId() ||
            entry.value.assignedTo == filterByAccountId())));
  }

  // Rebuilds the parent-to-children index for fast lookups
  void _rebuildIndex() {
    _parentToChildren.clear();

    for (final note in docs.values) {
      if (note.parentID != null && note.parentID!.isNotEmpty) {
        _parentToChildren[note.parentID!] ??= [];
        _parentToChildren[note.parentID]!.add(note.id);
      }
    }

    _indexBuilt = true;
  }

  // Get child instances using the index for O(1) lookup
  List<Note> getChildInstances(String parentId) {
    if (!_indexBuilt) {
      _rebuildIndex();
    }

    final childIds = _parentToChildren[parentId] ?? [];
    return childIds
        .map((id) => get(id))
        .where((note) => note != null)
        .cast<Note>()
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  // Get sibling instances using the index for O(1) lookup
  List<Note> getSiblingInstances(String parentId, String currentId) {
    if (!_indexBuilt) {
      _rebuildIndex();
    }

    final childIds = _parentToChildren[parentId] ?? [];
    return childIds
        .where((id) => id != currentId) // Exclude current note
        .map((id) => get(id))
        .where((note) => note != null)
        .cast<Note>()
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }
}

final notes = Notes();

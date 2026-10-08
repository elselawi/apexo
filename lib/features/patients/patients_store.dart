import 'package:apexo/app/data/application_store_effects.dart';
import 'package:apexo/app/data/store_session_binding.dart';
import 'package:apexo/services/launch.dart';
import 'package:apexo/utils/demo_generator.dart';

import 'patient_model.dart';
import '../network_actions/network_actions_controller.dart';
import '../../core/store.dart';

const _storeName = "patients";

class Patients extends Store<Patient> {
  Patients()
      : super(
          effects: applicationStoreEffects,
          loadDocuments: loadApplicationDocuments,
          modeling: Patient.fromJson,
          isDemo: launch.isDemo,
          onSyncStart: () {
            networkActions.isSyncing(networkActions.isSyncing() + 1);
          },
          onSyncEnd: () {
            networkActions.isSyncing(networkActions.isSyncing() - 1);
          },
        );

  late final _session = StoreSessionBinding<Patient>(
    store: this, name: _storeName,
    loadingMessage: 'Synchronizing patients',
    seedDemo: () => demoPatients(100),
  );

  @override
  void init() {
    super.init();
    _session.install();

  }

  List<String> get allTags {
    return Set<String>.from(present.values.expand((doc) => doc.tags)).toList();
  }
}

final patients = Patients();
// don't forget to initialize it in main.dart

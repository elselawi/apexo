import 'package:apexo/core/observable.dart';
import 'package:apexo/features/login/login_controller.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/services/archived.dart';
import 'package:apexo/services/launch.dart';
import 'package:apexo/services/network.dart';
import 'package:apexo/utils/hash.dart';
import 'package:apexo/utils/demo_generator.dart';

import '../../core/save_local.dart';
import '../../core/save_remote.dart';
import '../network_actions/network_actions_controller.dart';
import '../../services/login.dart';
import 'appointment_model.dart';
import '../../core/store.dart';

const _storeName = "appointments";

class Appointments extends Store<Appointment> {
  Appointments()
      : super(
          modeling: Appointment.fromJson,
          isDemo: launch.isDemo,
          showArchived: showArchived,
          onSyncStart: () {
            networkActions.isSyncing(networkActions.isSyncing() + 1);
          },
          onSyncEnd: () {
            networkActions.isSyncing(networkActions.isSyncing() - 1);
          },
        );

  Map<String, Map<String, List<Appointment>>>? _byPatientCache;
  Map<String, Map<String, List<Appointment>>> get byPatient {
    if (_byPatientCache != null) {
      return _byPatientCache!;
    }
    final newCache = <String, Map<String, List<Appointment>>>{};
    final now = DateTime.now();
    for (var appointment in observableMap.values) {
      final patientID = appointment.patientID ?? "";
      final isDone = appointment.isDone;
      final isUpcoming = appointment.date.isAfter(now);
      final isPast = appointment.date.isBefore(now);

      if (appointment.hasLabwork && appointment.labName.isNotEmpty) {
        labs.add(appointment.labName);
      }
      // build patient caches
      if (newCache[patientID] == null) {
        newCache[patientID] = {
          "upcoming": [],
          "done": [],
          "past": [],
          "all": [],
        };
      }
      newCache[patientID]!["all"]!.add(appointment);
      if (isUpcoming) {
        newCache[patientID]!["upcoming"]!.add(appointment);
      } else if (isDone) {
        newCache[patientID]!["done"]!.add(appointment);
      }
      if (isPast) {
        newCache[patientID]!["past"]!.add(appointment);
      }
    }
    _byPatientCache = newCache;
    return newCache;
  }

  Set<String> labs = {};

  @override
  init() {
    super.init();

    observableMap.observe((_) {
      _byPatientCache = null;
      _allPrescriptions = null;
    });
    login.activators[_storeName] = () async {
      await loaded;

      local = SaveLocal(name: _storeName, uniqueId: simpleHash(login.url));
      await deleteMemoryAndLoadFromPersistence();

      if (launch.isDemo) {
        if (docs.isEmpty) setAll(demoAppointments(1000));
      } else {
        remote = SaveRemote(
          pbInstance: login.pb!,
          storeName: _storeName,
          onOnlineStatusChange: (current) {
            if (network.isOnline() != current) {
              network.isOnline(current);
            }
          },
        );
      }

      return () async {
        loginCtrl.loadingIndicator("Synchronizing appointments");
        await synchronize();
        networkActions.syncCallbacks[_storeName] = synchronize;
        networkActions.reconnectCallbacks[_storeName] = remote!.checkOnline;

        network.onOnline[_storeName] = synchronize;
        network.onOffline[_storeName] = cancelRealtimeSub;
      };
    };
  }

  final filterByOperatorID = ObservableState("");

  Map<String, Appointment> get filtered {
    if (filterByOperatorID().isEmpty) return present;
    return Map<String, Appointment>.fromEntries(present.entries.where(
        (entry) => entry.value.operatorsIDs.contains(filterByOperatorID())));
  }

  List<String>? _allPrescriptions;
  List<String> get allPrescriptions {
    return _allPrescriptions ??=
        Set<String>.from(present.values.expand((doc) => doc.prescriptions))
            .toList();
  }
}

class LabworkItem {
  final String appointmentId;
  final Patient? patient;
  final DateTime date;
  final String laboratory;
  final String notes;
  final bool status;
  final String operators;

  LabworkItem({
    required this.appointmentId,
    required this.patient,
    required this.date,
    required this.laboratory,
    required this.notes,
    required this.status,
    required this.operators,
  });
}

final appointments = Appointments();

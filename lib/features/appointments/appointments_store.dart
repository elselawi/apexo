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

  Map<String, Map<String, List<Appointment>>> byPatient = {};
  Map<String, Map<String, List<Appointment>>> byDoctor = {};
  Set<String> labs = {};

  @override
  init() {
    super.init();

    observableMap.observe((_) => _allPrescriptions = null);
    observableMap.observe((_) {
      byPatient = {};
      byDoctor = {};
      for (var appointment in observableMap.values) {
        final patientID = appointment.patientID ?? "";
        final isDone = appointment.isDone;
        final isUpcoming = appointment.date.isAfter(DateTime.now());
        final isPast = appointment.date.isBefore(DateTime.now());

        if(appointment.labName.isNotEmpty && !labs.contains(appointment.labName)) {
          labs.add(appointment.labName);
        }
        // build patient caches
        if (byPatient[patientID] == null) {
          byPatient[patientID] = {
            "upcoming": [],
            "done": [],
            "past": [],
            "all": [],
          };
        }
        byPatient[patientID]!["all"]!.add(appointment);
        if (isUpcoming) {
          byPatient[patientID]!["upcoming"]!.add(appointment);
        } else if (isDone) {
          byPatient[patientID]!["done"]!.add(appointment);
        } else if (isPast) {
          byPatient[patientID]!["past"]!.add(appointment);
        }

        // build doctor caches
        for (var doctorId in appointment.operatorsIDs) {
          if (byDoctor[doctorId] == null) {
            byDoctor[doctorId] = {
              "upcoming": [],
              "done": [],
              "past": [],
              "all": [],
            };
          }
          byDoctor[doctorId]!["all"]!.add(appointment);
          if (isUpcoming) {
            byDoctor[doctorId]!["upcoming"]!.add(appointment);
          } else if (isDone) {
            byDoctor[doctorId]!["done"]!.add(appointment);
          } else if (isPast) {
            byDoctor[doctorId]!["past"]!.add(appointment);
          }
        }
      }
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

  final doctorId = ObservableState("");

  Map<String, Appointment> get filtered {
    if (doctorId().isEmpty) return present;
    return Map<String, Appointment>.fromEntries(
        present.entries.where((entry) => entry.value.operatorsIDs.contains(doctorId())));
  }

  List<String>? _allPrescriptions;
  List<String> get allPrescriptions {
    return _allPrescriptions ??= Set<String>.from(present.values.expand((doc) => doc.prescriptions)).toList();
  }
}

class LabworkItem {
  final String appointmentId;
  final Patient? patient;
  final DateTime date;
  final String laboratory;
  final String notes;
  final bool status;

  LabworkItem({
    required this.appointmentId,
    required this.patient,
    required this.date,
    required this.laboratory,
    required this.notes,
    required this.status,
  });
}

final appointments = Appointments();

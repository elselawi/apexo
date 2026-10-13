import 'package:apexo/app/data/application_store_effects.dart';
import 'package:apexo/app/data/store_session_binding.dart';
import 'package:apexo/core/reactive/observable.dart';
import 'package:apexo/services/launch.dart';
import 'package:apexo/utils/demo_generator.dart';

import '../network_actions/network_actions_controller.dart';
import 'appointment_model.dart';
import '../../core/store.dart';

const _storeName = "appointments";

class Appointments extends Store<Appointment> {
  Appointments()
      : super(
          effects: applicationStoreEffects,
          loadDocuments: loadApplicationDocuments,
          modeling: Appointment.fromJson,
          isDemo: launch.isDemo,
          onSyncStart: () {
            networkActions.isSyncing(networkActions.isSyncing() + 1);
          },
          onSyncEnd: () {
            networkActions.isSyncing(networkActions.isSyncing() - 1);
          },
        );

  int _cacheRevision = -1;

  void _ensureCacheRevision() {
    if (_cacheRevision == observableMap.revision) return;
    nullifyAppointmentsCache(null);
    _cacheRevision = observableMap.revision;
  }

  void _rebuildCache() {
    _ensureCacheRevision();
    _labs.clear();
    final newByPatientCache = <String, Map<String, List<Appointment>>>{};

    _todayAppointments = [];
    _thisMonthAppointments = [];

    final now = DateTime.now();

    final today = DateTime(now.year, now.month, now.day);

    for (var appointment in present.values) {
      final patientID = appointment.patientID ?? "";
      final isDone = appointment.isDone;
      final isUpcoming = appointment.date.isAfter(now);
      final isPast = appointment.date.isBefore(now);

      if (appointment.hasLabwork && appointment.labName.isNotEmpty) {
        _labs.add(appointment.labName);
      }

      if (appointment.date.year == today.year &&
          appointment.date.month == today.month &&
          appointment.date.day == today.day) {
        _todayAppointments!.add(appointment);
      }

      if (appointment.date.year == today.year &&
          appointment.date.month == today.month) {
        _thisMonthAppointments!.add(appointment);
      }

      // build patient caches
      if (newByPatientCache[patientID] == null) {
        newByPatientCache[patientID] = {
          "upcoming": [],
          "done": [],
          "past": [],
          "all": [],
        };
      }
      newByPatientCache[patientID]!["all"]!.add(appointment);
      if (isUpcoming) {
        newByPatientCache[patientID]!["upcoming"]!.add(appointment);
      } else if (isDone) {
        newByPatientCache[patientID]!["done"]!.add(appointment);
      }
      if (isPast) {
        newByPatientCache[patientID]!["past"]!.add(appointment);
      }
    }
    _thisMonthAppointments!.sort((a, b) => a.date.compareTo(b.date));
    _todayAppointments!.sort((a, b) => a.date.compareTo(b.date));
    _byPatientCache = newByPatientCache;
  }

  List<Appointment>? _thisMonthAppointments;
  List<Appointment> get thisMonthAppointments {
    _ensureCacheRevision();
    if (_thisMonthAppointments != null) {
      return _thisMonthAppointments!;
    }
    _rebuildCache();
    return _thisMonthAppointments!;
  }

  List<Appointment>? _todayAppointments;
  List<Appointment> get todayAppointments {
    _ensureCacheRevision();
    if (_todayAppointments != null) {
      return _todayAppointments!;
    }
    _rebuildCache();
    return _todayAppointments!;
  }

  Map<String, Map<String, List<Appointment>>>? _byPatientCache;
  Map<String, Map<String, List<Appointment>>> get byPatient {
    _ensureCacheRevision();
    if (_byPatientCache != null) {
      return _byPatientCache!;
    }
    _rebuildCache();
    return _byPatientCache!;
  }

  final Set<String> _labs = {};
  Set<String> get labs {
    _ensureCacheRevision();
    if (_byPatientCache == null) _rebuildCache();
    return _labs;
  }

  void nullifyAppointmentsCache(_) {
    _byPatientCache = null;
    _todayAppointments = null;
    _thisMonthAppointments = null;
    _allPrescriptions = null;
    _labs.clear();
  }

  late final _session = StoreSessionBinding<Appointment>(
    store: this, name: _storeName,
    loadingMessage: 'Synchronizing appointments',
    seedDemo: () => demoAppointments(1000),
  );

  @override
  void init() {
    super.init();
    _session.install();

  }

  final filterByOperatorID = ObservableState("");

  Map<String, Appointment> get filtered {
    if (filterByOperatorID().isEmpty) return present;
    return Map<String, Appointment>.fromEntries(present.entries.where(
        (entry) => entry.value.operatorsIDs.contains(filterByOperatorID())));
  }

  List<String>? _allPrescriptions;
  List<String> get allPrescriptions {
    _ensureCacheRevision();
    return _allPrescriptions ??=
        Set<String>.from(present.values.expand((doc) => doc.prescriptions))
            .toList();
  }
}

final appointments = Appointments();

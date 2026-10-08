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

  void _rebuildCache() {
    labs.clear();
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
        labs.add(appointment.labName);
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
    if (_thisMonthAppointments != null) {
      return _thisMonthAppointments!;
    }
    _rebuildCache();
    return _thisMonthAppointments!;
  }

  List<Appointment>? _todayAppointments;
  List<Appointment> get todayAppointments {
    if (_todayAppointments != null) {
      return _todayAppointments!;
    }
    _rebuildCache();
    return _todayAppointments!;
  }

  Map<String, Map<String, List<Appointment>>>? _byPatientCache;
  Map<String, Map<String, List<Appointment>>> get byPatient {
    if (_byPatientCache != null) {
      return _byPatientCache!;
    }
    _rebuildCache();
    return _byPatientCache!;
  }

  Set<String> labs = {};

  void nullifyAppointmentsCache(_) {
    _byPatientCache = null;
    _todayAppointments = null;
    _thisMonthAppointments = null;
    _allPrescriptions = null;
    labs.clear();
  }

  @override
  void set(Appointment item) {
    super.set(item);
    nullifyAppointmentsCache(null);
  }

  @override
  void setAll(List<Appointment> items) {
    super.setAll(items);
    nullifyAppointmentsCache(null);
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
    observableMap.observe(nullifyAppointmentsCache);

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

final appointments = Appointments();

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
  Appointments({DateTime Function()? now})
      : _now = now ?? DateTime.now,
        super(
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

  final DateTime Function() _now;
  int _cacheRevision = -1;
  DateTime? _cacheBuiltAt;
  DateTime? _cacheExpiresAt;

  void _ensureCacheRevision() {
    final now = _now();
    if (_cacheRevision == observableMap.revision &&
        (_cacheBuiltAt == null || !now.isBefore(_cacheBuiltAt!)) &&
        (_cacheExpiresAt == null || now.isBefore(_cacheExpiresAt!))) {
      return;
    }
    nullifyAppointmentsCache(null);
    _cacheRevision = observableMap.revision;
  }

  void _rebuildCache() {
    _ensureCacheRevision();
    _labs.clear();
    final newByPatientCache = <String, Map<String, List<Appointment>>>{};

    _todayAppointments = [];
    _thisMonthAppointments = [];

    final now = _now();
    _cacheBuiltAt = now;
    _cacheExpiresAt = DateTime(now.year, now.month, now.day + 1);

    final today = DateTime(now.year, now.month, now.day);

    for (var appointment in present.values) {
      final patientID = appointment.patientID ?? "";
      final isDone = appointment.isDone;
      final isUpcoming = appointment.date.isAfter(now);
      final isPast = appointment.date.isBefore(now);
      if (!isPast && appointment.date.isBefore(_cacheExpiresAt!)) {
        _cacheExpiresAt = appointment.date;
      }

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

  /// Every stored appointment of [patientID], archived ones included.
  ///
  /// [byPatient] is built from [present], which hides appointments the signed-in
  /// account may not edit ([Appointment.locked]). Use this method — not
  /// [byPatient] — when the question is whether a visit already exists for a
  /// patient, as DICOM matching and import ask: a scan must attach to the
  /// existing visit even when this account's permission level hides it.
  List<Appointment> allForPatient(String patientID) {
    return observableMap.docs.values
        .where((a) => a.patientID == patientID)
        .toList();
  }

  Map<String, Set<DateTime>>? _daysByPatientCache;

  /// The calendar days that already have a (non-archived) appointment, per
  /// patient id.
  ///
  /// Like [allForPatient] this ignores [Appointment.locked], so it answers
  /// "does this patient already have a visit that day?" for accounts with
  /// limited appointment permissions too.
  Map<String, Set<DateTime>> get appointmentDaysByPatient {
    _ensureCacheRevision();
    if (_daysByPatientCache != null) return _daysByPatientCache!;
    final days = <String, Set<DateTime>>{};
    for (final appointment in observableMap.docs.values) {
      if (appointment.archived == true) continue;
      final patientID = appointment.patientID ?? "";
      if (patientID.isEmpty) continue;
      (days[patientID] ??= <DateTime>{}).add(DateTime(
          appointment.date.year, appointment.date.month, appointment.date.day));
    }
    return _daysByPatientCache = days;
  }

  final Set<String> _labs = {};
  Set<String> get labs {
    _ensureCacheRevision();
    if (_byPatientCache == null) _rebuildCache();
    return _labs;
  }

  void nullifyAppointmentsCache(_) {
    _cacheBuiltAt = null;
    _cacheExpiresAt = null;
    _byPatientCache = null;
    _daysByPatientCache = null;
    _todayAppointments = null;
    _thisMonthAppointments = null;
    _allPrescriptions = null;
    _labs.clear();
  }

  late final _session = StoreSessionBinding<Appointment>(
    store: this,
    name: _storeName,
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

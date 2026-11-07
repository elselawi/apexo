import 'dart:async';

import 'package:apexo/core/reactive/observable.dart';
import 'package:apexo/features/booking/booking_clinic_service.dart';
import 'package:apexo/features/booking/booking_models.dart';
import 'package:apexo/features/booking/booking_requests_controller.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/utils/constants.dart';
import 'package:flutter/widgets.dart';

/// The app-level booking session. Nothing here may block a normal PMS login; a
/// missing registration or a down Worker leaves ordinary use untouched.
class BookingSession with WidgetsBindingObserver {
  BookingSession({BookingClinicService Function()? createService})
      : _createService = createService ?? BookingClinicService.new;

  final BookingClinicService Function() _createService;
  int _generation = 0;

  final ObservableState<BookingClinicRecord?> clinic =
      ObservableState<BookingClinicRecord?>(null);
  final ObservableState<bool> ready = ObservableState<bool>(false);
  final ObservableState<bool> schemaReady = ObservableState<bool>(false);
  final ObservableState<String> lastError = ObservableState<String>("");

  final BookingRequestsController requests = BookingRequestsController();

  BookingClinicService? service;
  bool _observing = false;

  bool get available => bookingAvailable;

  bool get isRegistered => clinic() != null;

  String get clinicKey {
    final record = clinic();
    if (record == null) return "";
    return "$bookingOrigin|${record.clinicId}|${login.currentAccountID}";
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && ready()) {
      unawaited(requests.refresh());
    }
  }

  Future<void> initialize() async {
    if (!bookingAvailable) {
      ready(false);
      return;
    }
    if (!_observing) {
      _observing = true;
      WidgetsBinding.instance.addObserver(this);
    }
    final currentService = service ??= _createService();
    final generation = ++_generation;
    final accountId = login.currentAccountID;
    try {
      final hasSchema = await currentService.collectionsReady();
      if (generation != _generation) return;
      schemaReady(hasSchema);
      final record = await currentService.loadClinic();
      if (generation != _generation) return;
      _attach(currentService, record, accountId);
      lastError("");
    } catch (_) {
      if (generation != _generation) return;
      requests.detach();
      clinic(null);
      ready(false);
      lastError("bookingUnavailable");
    }
  }

  void _attach(BookingClinicService currentService,
      BookingClinicRecord? record, String accountId) {
    clinic(record);
    if (record == null) {
      requests.detach();
      ready(false);
      return;
    }
    final key = "${currentService.api.origin}|${record.clinicId}|$accountId";
    if (requests.sessionKey != key ||
        _attachedInboxKey != record.inboxKey ||
        !requests.isAttached) {
      requests.attach(api: currentService.api, clinic: record, accountId: accountId);
    }
    _attachedInboxKey = record.inboxKey;
    ready(true);
    unawaited(requests.refresh());
  }

  String? _attachedInboxKey;

  /// Re-reads credentials without discarding same-session undelivered links.
  Future<void> reload() async {
    final currentService = service;
    if (currentService == null) return initialize();
    final generation = ++_generation;
    final accountId = login.currentAccountID;
    final record = await currentService.loadClinic();
    if (generation != _generation) return;
    _attach(currentService, record, accountId);
  }

  void reset() {
    _generation++;
    _attachedInboxKey = null;
    schemaReady(false);
    requests.detach();
    clinic(null);
    ready(false);
    lastError("");
    service?.dispose();
    service = null;
    if (_observing) {
      _observing = false;
      WidgetsBinding.instance.removeObserver(this);
    }
  }
}

final booking = BookingSession();


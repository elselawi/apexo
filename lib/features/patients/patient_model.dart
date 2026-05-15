import 'dart:convert';

import 'package:apexo/common_widgets/teeth_selector/tx_options.dart';
import 'package:apexo/core/model.dart';
import 'package:apexo/services/archived.dart';
import 'package:apexo/services/launch.dart';
import 'package:apexo/services/notifications/push_relay.dart';
import 'package:apexo/utils/constants.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/utils/encode.dart';
import 'package:http/http.dart' as http;

class Patient extends Model {
  List<String> get allPredefinedTreatments {
    final List<String> list = List.from(teeth.values);
    list.addAll((appointments.byPatient[id]?["all"] ?? []).fold<Set<String>>(
        {},
        (set, x) => set
          ..addAll((x.archived == true && showArchived() == false)
              ? []
              : x.teeth.values)));
    return list
        .where((label) =>
            txOptions.any((x) => x.type != StateType.state && x.label == label))
        .toSet()
        .toList();
  }

  Map<String, String> get allAppointmentsDentalNotes {
    return Map.from(teeth)
      ..addAll((appointments.byPatient[id]?["all"] ?? [])
          .fold<Map<String, String>>({}, (x, y) {
        if ((y.archived == true && showArchived() == false)) return x;
        for (var iso in y.teeth.keys) {
          x[iso] = y.teeth[iso]!;
        }
        return x;
      }));
  }

  List<Appointment> get allAppointments {
    return (appointments.byPatient[id]?["all"] ?? [])
        .where((appointment) =>
            (appointment.archived != true || showArchived()) &&
            appointment.locked == false)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  List<Appointment> get doneAppointments {
    return (appointments.byPatient[id]?["done"] ?? [])
        .where((appointment) =>
            (appointment.archived != true || showArchived()) &&
            appointment.locked == false)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  List<Appointment> get upcomingAppointments {
    return (appointments.byPatient[id]?["upcoming"] ?? [])
        .where((appointment) =>
            (appointment.archived != true || showArchived()) &&
            appointment.locked == false)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  List<Appointment> get pastAppointments {
    return (appointments.byPatient[id]?["past"] ?? [])
        .where((appointment) =>
            (appointment.archived != true || showArchived()) &&
            appointment.locked == false)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  int get age {
    return DateTime.now().year - birth;
  }

  double get paymentsMade {
    return doneAppointments.fold(0.0, (value, element) => value + element.paid);
  }

  double get pricesGiven {
    return doneAppointments.fold(
        0.0, (value, element) => value + element.price);
  }

  bool get overPaid {
    return paymentsMade > pricesGiven;
  }

  bool get fullPaid {
    return paymentsMade == pricesGiven;
  }

  bool get underPaid {
    return paymentsMade < pricesGiven;
  }

  double get outstandingPayments {
    return pricesGiven - paymentsMade;
  }

  int? get daysSinceLastAppointment {
    if (doneAppointments.isEmpty) return null;
    return DateTime.now().difference(doneAppointments.last.date).inDays;
  }

  @override
  bool get locked {
    // lock if only personal patients are permissible
    // and the patient DO have appointments
    // but those appointments doesn't have the current user as operator
    return login.permissions[PInt.patients] != 2 &&
        (allAppointments.isNotEmpty &&
            allAppointments
                .where((appointment) =>
                    appointment.operatorsIDs.contains(login.currentAccountID))
                .isEmpty);
  }

  @override
  String? get avatar {
    if (launch.isDemo) return "https://person.alisaleem.workers.dev/";
    final appointmentsWithImages =
        allAppointments.where((a) => a.imgs.isNotEmpty);
    if (appointmentsWithImages.isEmpty) return null;
    return appointmentsWithImages.first.imgs.first;
  }

  @override
  String? get imageRowId {
    final appointmentsWithImages =
        allAppointments.where((a) => a.imgs.isNotEmpty);
    if (appointmentsWithImages.isEmpty) return null;
    return appointmentsWithImages.first.id;
  }

  List<Appointment> get appointmentsWithImages {
    return allAppointments.where((a) => a.imgs.isNotEmpty).toList();
  }

  @override
  Map<String, String> get labels {
    final Map<String, String> _ = {};
    _["age"] = (DateTime.now().year - birth).toString();

    if (daysSinceLastAppointment == null) {
      _["lastVisit"] = txt("noVisits");
    } else {
      _["lastVisit"] = "$daysSinceLastAppointment ${txt("daysAgo")}";
    }

    if (gender == 0) {
      _["gender"] = "♀";
    } else {
      _["gender"] = "♂️";
    }

    if (outstandingPayments > 0) {
      _["pay"] = "${txt("underpaid")}🔻";
    }

    if (outstandingPayments < 0) {
      _["pay"] = "${txt("overpaid")}🔺";
    }

    if (paymentsMade != 0) {
      _["totalPayments"] = "$paymentsMade";
    }

    for (var i = 0; i < tags.length; i++) {
      _[List.generate(i + 1, (_) => "\u200B").join("")] = tags[i];
    }
    return _;
  }

  Future<String> generatePatientLink() async {
    final longLink =
        "https://web.apexo.app/${encode("$id|$title|${login.url}|${await PushRelay.ensureKey()}")}";

    final shortLink = await http.put(Uri.parse(shorteningServer),
        body: jsonEncode({"long": longLink}));
    return shortLink.body;
  }

  get shortLink {
    if (link == null) return "";
    return "$shorteningServer/$link";
  }

  // id: id of the patient (inherited from Model)
  // title: name of the patient (inherited from Model)
  /* 1 */ int birth = DateTime.now().year - 18;
  /* 2 */ int gender = 0; // 0 for female, 1 for male
  /* 3 */ String phone = "";
  /* 4 */ String email = "";
  /* 5 */ String address = "";
  /* 6 */ List<String> tags = [];
  /* 7 */ String notes = "";
  /* 8 */ Map<String, String> teeth = {};
  /* 9 */ String? link;

  @override
  Patient.fromJson(super.json) : super.fromJson();

  @override
  Patient copy(bool blank) {
    return Patient.fromJson(blank ? {} : toJson());
  }

  @override
  void fromJson(Map<String, dynamic> json) {
    super.fromJson(json);

    /* 1 */ birth = json['birth'] ?? birth;
    /* 2 */ gender = json['gender'] ?? gender;
    /* 3 */ phone = json['phone'] ?? phone;
    /* 4 */ email = json['email'] ?? email;
    /* 5 */ address = json['address'] ?? address;
    /* 6 */ tags = List<String>.from(json['tags'] ?? tags);
    /* 7 */ notes = json['notes'] ?? notes;
    /* 8 */ teeth = Map<String, String>.from(json['teeth'] ?? teeth);
    /* 9 */ link = json["link"] ?? link;
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    final d = Patient.fromJson({});

    /* 1 */ if (birth != d.birth) json['birth'] = birth;
    /* 2 */ if (gender != d.gender) json['gender'] = gender;
    /* 3 */ if (phone != d.phone) json['phone'] = phone;
    /* 4 */ if (email != d.email) json['email'] = email;
    /* 5 */ if (address != d.address) json['address'] = address;
    /* 6 */ if (tags.toString() != d.tags.toString()) json['tags'] = tags;
    /* 7 */ if (notes != d.notes) json['notes'] = notes;
    /* 8 */ if (teeth.isNotEmpty) json['teeth'] = teeth;
    /* 9 */ if (link != d.link) json['link'] = link;
    return json;
  }
}

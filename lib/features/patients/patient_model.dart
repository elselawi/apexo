import 'dart:convert';

import 'package:apexo/common_widgets/item_title.dart';
import 'package:apexo/common_widgets/teeth_selector/tx_options.dart';
import 'package:apexo/core/model.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/launch.dart';
import 'package:apexo/services/notifications/push_relay.dart';
import 'package:apexo/utils/constants.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/utils/encode.dart';
import 'package:apexo/utils/parsed_phone_number.dart';
import 'package:apexo/utils/phone_numbers_extractor.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:http/http.dart' as http;

class PatientTableLabel {
  final IconData icon;
  final Color? color;
  final String title;
  final String content;
  final double value;
  final String searchableString;
  final bool sortable;
  final int tab;
  final bool view;

  PatientTableLabel({
    this.icon = FluentIcons.document,
    this.color,
    this.view = true,
    required this.title,
    required this.content,
    required this.value,
    required this.searchableString,
    required this.sortable,
    required this.tab,
  });
}

class Patient extends Model {
  List<String> get allPredefinedTreatments {
    final List<String> list = List.from(teeth.values);
    list.addAll((appointments.byPatient[id]?["all"] ?? []).fold<Set<String>>(
        {}, (set, x) => set..addAll(x.archived == true ? [] : x.teeth.values)));
    return list
        .where((label) =>
            txOptions.any((x) => x.type != StateType.state && x.label == label))
        .toSet()
        .toList();
  }

  List<TreatmentLabel> get treatmentLabels {
    return allPredefinedTreatments
        .map((x) => x == "pontic" || x == "abutment" ? "bridge" : x)
        .where((x) =>
            txOptions.any((y) => y.type != StateType.state && y.label == x))
        .toSet()
        .map((x) => TreatmentLabel(
            string: x, color: labelToColor(x), icon: labelToIcon(x)))
        .toList();
  }

  Map<String, String> get allAppointmentsDentalNotes {
    return Map.from(teeth)
      ..addAll((appointments.byPatient[id]?["all"] ?? [])
          .fold<Map<String, String>>({}, (x, y) {
        if (y.archived == true) return x;
        for (var iso in y.teeth.keys) {
          x[iso] = y.teeth[iso]!;
        }
        return x;
      }));
  }

  List<Appointment> get allAppointments {
    return (appointments.byPatient[id]?["all"] ?? [])
        .where((appointment) =>
            (appointment.archived != true) && appointment.locked == false)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  List<Appointment> get doneAppointments {
    return (appointments.byPatient[id]?["done"] ?? [])
        .where((appointment) =>
            (appointment.archived != true) && appointment.locked == false)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  List<Appointment> get upcomingAppointments {
    return (appointments.byPatient[id]?["upcoming"] ?? [])
        .where((appointment) =>
            (appointment.archived != true) && appointment.locked == false)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  List<Appointment> get pastAppointments {
    return (appointments.byPatient[id]?["past"] ?? [])
        .where((appointment) =>
            (appointment.archived != true) && appointment.locked == false)
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

  Color? get colorBasedOnPayments {
    if (fullPaid) return null;
    if (underPaid) return Colors.orange;
    return Colors.blue;
  }

  double get outstandingPayments {
    return pricesGiven - paymentsMade;
  }

  int? get daysSinceLastAppointment {
    if (doneAppointments.isEmpty) return null;
    return DateTime.now().difference(doneAppointments.last.date).inDays;
  }

  /// Returns a human-readable string like "2 years, 3 months, 10 days"
  String? get lastVisitDuration {
    if (doneAppointments.isEmpty) return null;
    return Patient.formatDuration(doneAppointments.last.date, DateTime.now());
  }

  /// Formats the duration between two dates as a human-readable string.
  /// e.g. "2 years, 3 months, 10 days"
  static String formatDuration(DateTime from, DateTime to) {
    int years = to.year - from.year;
    int months = to.month - from.month;
    int days = to.day - from.day;

    if (days < 0) {
      months--;
      final prevMonth = DateTime(to.year, to.month - 1, 0);
      days += prevMonth.day;
    }
    if (months < 0) {
      years--;
      months += 12;
    }

    final parts = <String>[];
    if (years > 0) {
      parts.add("$years ${txt("year${years > 1 ? "s" : ""}")}");
    }
    if (months > 0) {
      parts.add("$months ${txt("month${months > 1 ? "s" : ""}")}");
    }
    if (days > 0 || parts.isEmpty) {
      parts.add("$days ${txt("day${days > 1 ? "s" : ""}")}");
    }

    return parts.join(", ").toLowerCase();
  }

  @override
  bool get locked {
    // lock if only personal patients are permissible
    // and the patient DO have appointments
    // but those appointments doesn't have the current user as operator
    return login.perm(Perm.patients).not(2) &&
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
        allAppointments.where((a) => a.viewableImgs.isNotEmpty);
    if (appointmentsWithImages.isEmpty) return null;
    return appointmentsWithImages.first.viewableImgs.first;
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

  /// Appointments that have at least one DCM X-ray attached.
  /// Parallel to [appointmentsWithImages].
  List<Appointment> get appointmentsWithDcmImgs {
    return allAppointments.where((a) => a.dcmImgs.isNotEmpty).toList();
  }

  String? _searchString;
  List<PatientTableLabel>? _labels;
  void nullifyLabels() {
    _labels = null;
    _searchString = null;
  }

  String get searchString {
    return _searchString ??=
        (title + tableLabels.map((x) => x.searchableString).join(" "))
            .toLowerCase()
            .replaceAll(RegExp("أ|إ"), "ا");
  }

  List<PatientTableLabel> get tableLabels {
    if (_labels != null) return _labels!;
    final List<PatientTableLabel> _ = [];

    // age
    final age = DateTime.now().year - birth;
    _.add(PatientTableLabel(
      content: age.toString(),
      icon: FluentIcons.birthday_cake,
      title: txt("age"),
      value: age.toDouble(),
      searchableString: age.toString(),
      sortable: true,
      tab: 0,
    ));

    // gender
    final genderSymbol =
        gender == 1 ? "👨 ${txt('male')}" : "👩 ${txt('female')}";
    _.add(PatientTableLabel(
      content: genderSymbol,
      icon: FluentIcons.info,
      title: txt("gender"),
      value: gender.toDouble(),
      searchableString: gender == 1 ? "male" : "female",
      sortable: true,
      tab: 0,
    ));

    // phones
    _.add(PatientTableLabel(
      title: txt("phone"),
      content: phonesString.isEmpty ? txt("notSet") : phonesString,
      value: 0,
      searchableString: phonesString,
      sortable: false,
      tab: 0,
      icon: WindowsIcons.phone,
      color: phone.isEmpty ? Colors.orange : null,
    ));

    _.add(PatientTableLabel(
      title: txt("share"),
      content: txt("qrCode"),
      value: 0,
      searchableString: "",
      sortable: false,
      tab: 3,
      icon: FluentIcons.q_r_code,
    ));

    // number of visits
    _.add(PatientTableLabel(
      icon: WindowsIcons.calendar_reply,
      title: txt("appointments"),
      searchableString: "${allAppointments.length}",
      value: allAppointments.length.toDouble(),
      content: allAppointments.length.toString(),
      sortable: true,
      tab: 2,
    ));

    // last visit
    final lastVisitContent = daysSinceLastAppointment == null
        ? txt("noVisits")
        : "$lastVisitDuration ${txt("daysAgo").split(" ").last}";
    _.add(PatientTableLabel(
      icon: WindowsIcons.calendar,
      title: txt("lastVisit"),
      searchableString: lastVisitContent,
      value: (daysSinceLastAppointment ?? double.infinity).toDouble(),
      content: lastVisitContent,
      sortable: true,
      tab: 2,
    ));

    final paymentStatus = txt(underPaid
        ? "underpaid"
        : overPaid
            ? "overpaid"
            : "fullyPaid");
    _.add(PatientTableLabel(
      icon: WindowsIcons.payment_card,
      color: overPaid
          ? Colors.blue
          : underPaid
              ? Colors.orange
              : null,
      content: "${paymentsMade.toStringAsFixed(2)} ${currency()}",
      value: paymentsMade,
      searchableString: paymentStatus,
      title: txt("paid"),
      sortable: true,
      tab: 2,
    ));

    _.add(PatientTableLabel(
      icon: FluentIcons.warning,
      color: Colors.orange,
      content: "${outstandingPayments.toStringAsFixed(2)} ${currency()}",
      value: outstandingPayments,
      searchableString: paymentStatus,
      title: txt("underpaid"),
      sortable: true,
      tab: 2,
      view: underPaid,
    ));

    _.add(PatientTableLabel(
      icon: FluentIcons.warning,
      color: Colors.blue,
      content: "${outstandingPayments.abs().toStringAsFixed(2)} ${currency()}",
      value: overPaid ? outstandingPayments.abs() : outstandingPayments,
      searchableString: paymentStatus,
      title: txt("overpaid"),
      sortable: true,
      tab: 2,
      view: overPaid,
    ));

    for (var tag in tags) {
      _.add(PatientTableLabel(
        content: tag,
        icon: FluentIcons.tag,
        title: txt("patientTags"),
        searchableString: tag,
        value: 0,
        sortable: false,
        tab: 0,
      ));
    }

    return _labels = _;
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
  /* 3 */ List<ParsedPhoneNumber> phone = [];
  /* 4 */ String email = "";
  /* 5 */ String address = "";
  /* 6 */ List<String> tags = [];
  /* 7 */ String notes = "";
  /* 8 */ Map<String, String> teeth = {};
  /* 8b */ Map<String, String> teethExtraNotes = {};
  /* 9 */ String? link;

  String get phonesString => phone.map((p) => p.e164).join(" ");

  @override
  Patient.fromJson(super.json) : super.fromJson();

  @override
  Patient copy(bool blank) {
    return Patient.fromJson(blank ? {} : toJson());
  }

  @override
  void fromJson(Map<String, dynamic> json) {
    nullifyLabels();
    super.fromJson(json);

    /* 1 */ birth = json['birth'] ?? birth;
    /* 2 */ gender = json['gender'] ?? gender;
    /* 3 */ phone = json['phone'] == null
        ? []
        : PhoneNumberExtractor.extract(json['phone'])
            .map((s) => ParsedPhoneNumber(s))
            .toList();
    /* 4 */ email = json['email'] ?? email;
    /* 5 */ address = json['address'] ?? address;
    /* 6 */ tags = List<String>.from(json['tags'] ?? tags);
    /* 7 */ notes = json['notes'] ?? notes;
    /* 8 */ teeth = Map<String, String>.from(json['teeth'] ?? teeth);
    /* 8b */ teethExtraNotes =
        Map<String, String>.from(json['teethExtraNotes'] ?? teethExtraNotes);
    /* 9 */ link = json["link"] ?? link;
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    final d = Patient.fromJson({});

    /* 1 */ if (birth != d.birth) json['birth'] = birth;
    /* 2 */ if (gender != d.gender) json['gender'] = gender;
    /* 3 */ if (phone != d.phone) json['phone'] = phonesString;
    /* 4 */ if (email != d.email) json['email'] = email;
    /* 5 */ if (address != d.address) json['address'] = address;
    /* 6 */ if (tags.toString() != d.tags.toString()) json['tags'] = tags;
    /* 7 */ if (notes != d.notes) json['notes'] = notes;
    /* 8 */ if (teeth.isNotEmpty) json['teeth'] = teeth;
    /* 8b */ if (teethExtraNotes.isNotEmpty)
      json['teethExtraNotes'] = teethExtraNotes;
    /* 9 */ if (link != d.link) json['link'] = link;
    return json;
  }
}

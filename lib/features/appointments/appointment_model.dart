import 'package:apexo/core/model.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/launch.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/features/doctors/doctor_model.dart';
import 'package:apexo/features/doctors/doctors_store.dart';
import 'package:intl/intl.dart' as intl;


class Appointment extends Model {
  @override
  String? get avatar {
    if (launch.isDemo) return "https://person.alisaleem.workers.dev/";
    if (imgs.isEmpty) return null;
    return imgs.first;
  }

  @override
  String get title {
    if (patient == null) {
      return "  ";
    } else if (patient!.title.isEmpty) {
      return "  ";
    } else {
      return "${patient!.title} - ${intl.DateFormat(localSettings.dateFormat.startsWith("d") == true ? "d/MM/yyyy" : "MM/d/yyyy").format(date)}";
    }
  }

  Patient? get patient {
    if (patientID != null && patientID!.isNotEmpty && patients.get(patientID!) == null && patientID!.length == 15) {
      return Patient.fromJson({
        id: patientID,
        title: "${patientID}temp"
      });
    }
    return patients.get(patientID ?? "return null when null");
  }

  @override
  bool get locked {
    if (operators.isEmpty) return false;
    if (login.isAdmin) return false;
    return operators.every((element) => element.locked);
  }

  List<Doctor> get operators {
    List<Doctor> foundOperators = [];
    for (var id in operatorsIDs) {
      var found = doctors.get(id);
      if (found != null) {
        foundOperators.add(found);
      }
    }
    return foundOperators;
  }

  Set<int> get availableWeekDays {
    return operators.expand((element) => element.dutyDays).toSet().map((day) => allDays.indexOf(day) + 1).toSet();
  }

  String get subtitleLine1 {
    return "${isDone ? "✔️ " : ""}${isDone && postOpNotes.isNotEmpty ? postOpNotes : preOpNotes}";
  }

  String get subtitleLine2 {
    if (operatorsIDs.isEmpty) return "";
    return "👨‍⚕️ ${operatorsIDs.map((id) => doctors.get(id)?.title).join(", ")}";
  }

  bool get fullPaid {
    return paid == price;
  }

  bool get overPaid {
    return paid > price;
  }

  bool get underPaid {
    return paid < price;
  }

  double get paymentDifference {
    return (paid - price).abs();
  }

  bool get isMissed {
    return date.isBefore(DateTime.now()) && date.difference(DateTime.now()).inDays.abs() > 0 && !isDone;
  }

  bool get firstAppointmentForThisPatient {
    if (patient == null) return false;
    return patient!.allAppointments.first == this;
  }

  // id: id of the appointment (inherited from Model)

  /* 1 */ List<String> operatorsIDs = [];
  /* 2 */ String? patientID;
  /* 3 */ String preOpNotes = "";
  /* 4 */ String postOpNotes = "";
  /* 5 */ List<String> prescriptions = [];
  /* 6 */ double price = 0;
  /* 7 */ double paid = 0;
  /* 8 */ List<String> imgs = [];
  /* 9 */ DateTime date = DateTime.now();
  /* 10 */ bool isDone = false;
  /* 11 */ Map<String, String> teeth = {};
  /* 12 */ bool hasLabwork = false;
  /* 13 */ String labName = "";
  /* 14 */ String labworkNotes = "";
  /* 15 */ bool labworkReceived = false;

  Appointment.fromJson(Map<String, dynamic> json) : super.fromJson(json) {
    /* 1 */ operatorsIDs = List<String>.from(json["operatorsIDs"] ?? operatorsIDs);
    /* 2 */ prescriptions = List<String>.from(json["prescriptions"] ?? prescriptions);
    /* 3 */ patientID = json["patientID"] ?? patientID;
    /* 4 */ preOpNotes = json["preOpNotes"] ?? preOpNotes;
    /* 5 */ postOpNotes = json["postOpNotes"] ?? postOpNotes;
    /* 6 */ price = double.parse((json["price"] ?? price).toString());
    /* 7 */ paid = double.parse((json["paid"] ?? paid).toString());
    /* 8 */ imgs = List<String>.from(json["imgs"] ?? imgs);
    /* 9 */ date = (json["date"] != null ? DateTime.fromMillisecondsSinceEpoch((json["date"] * 60000).toInt()) : date);
    /* 10 */ isDone = (json["isDone"] ?? isDone);
    /* 11 */ teeth = Map<String, String>.from(json['teeth'] ?? teeth);
    /* 12 */ hasLabwork = json["hasLabwork"] ?? hasLabwork;
    /* 13 */ labName = json["labName"] ?? labName;
    /* 14 */ labworkNotes = json["labworkNotes"] ?? labworkNotes;
    /* 15 */ labworkReceived = json["labworkReceived"] ?? labworkReceived;
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    final d = Appointment.fromJson({});
    /* 1 */ if (operatorsIDs.isNotEmpty) json['operatorsIDs'] = operatorsIDs;
    /* 2 */ if (prescriptions.isNotEmpty) json['prescriptions'] = prescriptions;
    /* 3 */ if (patientID != d.patientID) json['patientID'] = patientID;
    /* 4 */ if (preOpNotes != d.preOpNotes) json['preOpNotes'] = preOpNotes;
    /* 5 */ if (postOpNotes != d.postOpNotes) json['postOpNotes'] = postOpNotes;
    /* 6 */ if (price != d.price) json['price'] = price;
    /* 7 */ if (paid != d.paid) json['paid'] = paid;
    /* 8 */ if (imgs.isNotEmpty) json['imgs'] = imgs;
    /* 9 */ if (isDone != d.isDone) json['isDone'] = isDone;
    /* 10 */ json['date'] = (date.millisecondsSinceEpoch / 60000).round();
    /* 11 */ if (teeth.isNotEmpty) json['teeth'] = teeth;
    /* 12 */ if (hasLabwork != d.hasLabwork) json['hasLabwork'] = hasLabwork;
    /* 13 */ if (labName != d.labName) json['labName'] = labName;
    /* 14 */ if (labworkNotes != d.labworkNotes) json['labworkNotes'] = labworkNotes;
    /* 15 */ if (labworkReceived != d.labworkReceived) json['labworkReceived'] = labworkReceived;


    json.remove("title"); // remove since it is a computed value in this case

    return json;
  }
}

import 'package:apexo/core/model.dart';
import 'package:apexo/features/accounts/accounts_controller.dart';
import 'package:apexo/services/launch.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/utils/constants.dart';

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
      return patient!.title;
    }
  }

  @override
  bool get locked {
    // lock if only personal appointments are permissible
    // and the appointment doesn't have the current account id as an operator
    return login.permissions[PInt.appointments] != 2 &&
        !operatorsIDs.contains(login.currentAccountID);
  }

  Patient? get patient {
    return patients.get(patientID ?? "return null when null");
  }

  String get subtitleLine1 {
    return "${isDone ? "✔️ " : ""}${isDone && postOpNotes.isNotEmpty ? postOpNotes : preOpNotes}";
  }

  String get subtitleLine2 {
    if (operatorsIDs.isEmpty) return "";
    return "👨‍⚕️ ${operatorsIDs.map((id) => accounts.nameOrEmailFromID(id)).join(", ")}";
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
    return date.isBefore(DateTime.now()) &&
        date.difference(DateTime.now()).inDays.abs() > 0 &&
        !isDone;
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
  /* 16 */ Map<String, String> drawings = {};

  Appointment.fromJson(Map<String, dynamic> json) : super.fromJson(json) {
    /* 1 */ operatorsIDs =
        List<String>.from(json["operatorsIDs"] ?? operatorsIDs);
    /* 2 */ prescriptions =
        List<String>.from(json["prescriptions"] ?? prescriptions);
    /* 3 */ patientID = json["patientID"] ?? patientID;
    /* 4 */ preOpNotes = json["preOpNotes"] ?? preOpNotes;
    /* 5 */ postOpNotes = json["postOpNotes"] ?? postOpNotes;
    /* 6 */ price = double.parse((json["price"] ?? price).toString());
    /* 7 */ paid = double.parse((json["paid"] ?? paid).toString());
    /* 8 */ imgs = List<String>.from(json["imgs"] ?? imgs);
    /* 9 */ date = (json["date"] != null
        ? DateTime.fromMillisecondsSinceEpoch((json["date"] * 60000).toInt())
        : date);
    /* 10 */ isDone = (json["isDone"] ?? isDone);
    /* 11 */ teeth = Map<String, String>.from(json['teeth'] ?? teeth);
    /* 12 */ hasLabwork = json["hasLabwork"] ?? hasLabwork;
    /* 13 */ labName = json["labName"] ?? labName;
    /* 14 */ labworkNotes = json["labworkNotes"] ?? labworkNotes;
    /* 15 */ labworkReceived = json["labworkReceived"] ?? labworkReceived;
    /* 16 */ drawings = Map<String, String>.from(json['drawings'] ?? drawings);
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
    /* 14 */ if (labworkNotes != d.labworkNotes)
      json['labworkNotes'] = labworkNotes;
    /* 15 */ if (labworkReceived != d.labworkReceived)
      json['labworkReceived'] = labworkReceived;
    /* 16 */ if (drawings.isNotEmpty) json['drawings'] = drawings;

    json.remove("title"); // remove since it is a computed value in this case

    return json;
  }

  @override
  Map<String, dynamic> get jsonCopyForPush {
    return {
      "date": (date.millisecondsSinceEpoch / 60000).round(),
      "isDone": isDone,
      "archived": archived,
      "operatorsIDs": operatorsIDs,
    };
  }

  @override
  List<String> get pushIfChanged =>
      ["date", "isDone", "archived", "operatorsIDs"];

  @override
  bool get pushOnCreation => true;

  @override
  List<String> get targetsToPushTo => [
        // once we've implemented the patient side, we should uncomment the following line
        // if (patientID != null && patientID!.isNotEmpty) patientID!,
        ...operatorsIDs
      ];
}

import 'package:apexo/core/model.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/features/doctors/doctor_model.dart';
import 'package:apexo/features/doctors/doctors_store.dart';
import 'package:apexo/services/login.dart';
import 'package:intl/intl.dart';

class Labwork extends Model {
  @override
  bool get locked {
    if (operators.isEmpty) return false;
    if (login.isAdmin) return false;
    return operators.every((element) => element.locked);
  }

  @override
  get labels {
    return {
      "Laboratory": lab,
      "Month": DateFormat("MMM yyyy", locale.s.$code).format(date),
      "Patient": patient?.title ?? "Unknown",
      "Paid": paid ? txt("paid") : txt("due"),
      "doctors": operators.map((e) => e.title).join(", "),
    };
  }

  Patient? get patient {
    if (patientID != null && patientID!.isNotEmpty && patients.get(patientID!) == null && patientID!.length == 15) {
      return Patient.fromJson({
        id: patientID,
        title: "${patientID}temp"
      });
    }
    return patients.get(patientID ?? "");
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

  @override
  String get title {
    return DateFormat("yyyy-MM-dd").format(date);
  }

  // id: id of the labwork (inherited from Model)
  // title: title of the labwork (inherited from Model)
  /* 1 */ List<String> operatorsIDs = [];
  /* 2 */ String? patientID;
  /* 3 */ String note = "";
  /* 4 */ bool paid = false;
  /* 5 */ double price = 0;
  /* 6 */ DateTime date = DateTime.now();
  /* 7 */ String lab = "";
  /* 8 */ String phoneNumber = "";

  Labwork.fromJson(Map<String, dynamic> json) : super.fromJson(json) {
    /* 1 */ operatorsIDs = List<String>.from(json["operatorsIDs"] ?? operatorsIDs);
    /* 2 */ patientID = json["patientID"] ?? patientID;
    /* 3 */ note = json["note"] ?? note;
    /* 4 */ price = double.parse((json["price"] ?? price).toString());
    /* 5 */ paid = json["paid"] ?? paid;
    /* 6 */ date = json["date"] != null ? DateTime.fromMillisecondsSinceEpoch(json["date"] * (60 * 60 * 1000)) : date;
    /* 7 */ lab = json["lab"] ?? lab;
    /* 8 */ phoneNumber = json["phoneNumber"] ?? phoneNumber;
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    final d = Labwork.fromJson({});
    /* 1 */ if (operatorsIDs.isNotEmpty) json['operatorsIDs'] = operatorsIDs;
    /* 2 */ if (patientID != d.patientID) json['patientID'] = patientID;
    /* 3 */ if (note != d.note) json['note'] = note;
    /* 4 */ if (price != d.price) json['price'] = price;
    /* 5 */ if (paid != d.paid) json['paid'] = paid;
    /* 6 */ json['date'] = (date.millisecondsSinceEpoch / (60 * 60 * 1000)).round();
    /* 7 */ if (lab != d.lab) json['lab'] = lab;
    /* 8 */ if (phoneNumber != d.phoneNumber) json['phoneNumber'] = phoneNumber;
    return json;
  }
}

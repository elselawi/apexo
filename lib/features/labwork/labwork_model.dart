import 'package:apexo/core/model.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/features/doctors/doctor_model.dart';
import 'package:apexo/services/login.dart';

class Labwork extends Model {
  @override
  bool get locked {
    if (operators.isEmpty) return false;
    if (login.isAdmin) return false;
    return operators.every((element) => element.locked);
  }

  @override
  String get title {
    if(appointment == null) {
      return note;
    } else {
      return appointment!.title;
    }
  }

  List<Doctor> get operators {
    if (appointment != null) {
      return appointment!.operators;
    } else {
      return [];
    }
  }

  Patient? get patient {
    if (appointment != null) {
      return appointment!.patient;
    } else {
      return null;
    }
  }

  Appointment? get appointment {
    if (appointmentID != null) {
      return appointments.get(appointmentID!);
    } else {
      return null;
    }
  }

  DateTime? get date {
    if (appointment != null) {
      return appointment!.date;
    } else {
      return null;
    }
  }

  // id: id of the labwork (inherited from Model)
  // title: title of the labwork (inherited from Model)
  /* 1 */ String? appointmentID;
  /* 2 */ String note = "";
  /* 3 */ bool received = false;
  /* 4 */ String lab = "";

  Labwork.fromJson(Map<String, dynamic> json) : super.fromJson(json) {
    /* 1 */ appointmentID = json["appointmentID"] ?? appointmentID;
    /* 2 */ note = json["note"] ?? note;
    /* 3 */ received = json["received"] ?? received;
    /* 4 */ lab = json["lab"] ?? lab;
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    final d = Labwork.fromJson({});
    /* 1 */ if (appointmentID != d.appointmentID) json['appointmentID'] = appointmentID;
    /* 2 */ if (note != d.note) json['note'] = note;
    /* 3 */ if (received != d.received) json['received'] = received;
    /* 4 */ if (lab != d.lab) json['lab'] = lab;
    return json;
  }
}

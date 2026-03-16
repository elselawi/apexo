import 'package:apexo/common_widgets/teeth_selector/tx_options.dart';
import 'package:apexo/core/model.dart';
import 'package:apexo/features/accounts/accounts_controller.dart';
import 'package:apexo/features/notes/notes_store.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/utils/constants.dart';
import 'package:apexo/utils/get_deterministic_item.dart';
import 'package:apexo/utils/hash.dart';
import 'package:fluent_ui/fluent_ui.dart';

class Note extends Model {
  @override
  bool get locked => (login.permissions[PInt.notes] == 0 &&
      !login.isAdmin &&
      isColumn == false &&
      login.currentAccountID != createdBy &&
      login.currentAccountID != assignedTo);
  bool get isNote => !isColumn;
  Patient? get patient => patients.get(forPatient);
  bool get incoming => login.currentAccountID == assignedTo;
  bool get outgoing => login.currentAccountID == createdBy;
  bool get unCategorized => isNote && columnID.isEmpty;
  bool get unAssigned => isNote && assignedTo.isEmpty;
  bool get overdue => isNote && !done && dueDate.isBefore(DateTime.now());
  bool get pending => isNote && !done && !overdue;
  bool get completed => isNote && done;
  int get commentsCount => comments.length;
  int get attachmentsCount => attachments.length;
  bool get hasComments => commentsCount > 0;
  bool get hasAttachments => attachmentsCount > 0;
  String get assignedUsername => accounts.nameOrEmailFromID(assignedTo);
  String get createdByUsername => accounts.nameOrEmailFromID(createdBy);

  // recurrence related getters and methods
  bool get isRecurring => recurringInterval != null;
  bool get isRecurringInstance => parentID != null;
  bool get isGhost => notes.get(id) == null;
  Note? get parent => notes.get(parentID ?? "");
  List<Note> get childInstances => notes.getChildInstances(id);
  List<Note> get siblingInstances =>
      notes.getSiblingInstances(parentID ?? "", id);
  Note createChild() {
    final child = Note.fromJson({});
    final expectedDate = nextExpectedDate;
    // recurrence related
    child.parentID = id;
    child.date = expectedDate;
    child.id =
        simpleHash('${id}_${expectedDate.millisecondsSinceEpoch}', length: 15);
    // note related
    child.columnID = columnID;
    child.title = title;
    child.note = note;
    child.createdBy = createdBy;
    child.assignedTo = assignedTo;
    child.dueDate = expectedDate.add(dueDate.difference(date));
    child.forPatient = forPatient;

    return child;
  }

  DateTime get nextExpectedDate {
    final lastRecurrence = childInstances.lastOrNull?.date ?? date;
    return lastRecurrence.add(Duration(days: recurringInterval!));
  }

  bool get deservesRecurrence {
    return isRecurring && nextExpectedDate.isBefore(DateTime.now());
  }

  Color get computedTint {
    return tint ??
        getDeterministicItem(
          txOptions.map((x) => x.color).toList(),
          id,
        );
  }

  // id: id of the expense item (inherited from Model)
  // title: title of the expense item (inherited from Model, used as note title)

  /* 1 */ bool isColumn = false;
  /* 2 */ String columnName = "";
  /* 3 */ Color? tint;
  /* 4 */ double order = 0;

  // when its a note
  /* 5 */ String columnID = "";
  /* 6 */ DateTime date = DateTime.now();
  /* 7 */ String note = "";
  /* 8 */ List<List<String>> comments = [];
  /* 9 */ bool done = false;
  /* 10 */ List<String> attachments = [];
  /* 11 */ String createdBy = "";
  /* 12 */ String assignedTo = "";
  /* 13 */ DateTime dueDate = DateTime.now();
  /* 14 */ String forPatient = "";
  /* 15 */ int? recurringInterval;
  /* 16 */ String? parentID;

  Note.fromJson(Map<String, dynamic> json) : super.fromJson(json) {
    /* 1 */ isColumn = json['isColumn'] ?? isColumn;
    /* 2 */ columnName = json['columnName'] ?? columnName;
    /* 3 */ tint = json['tint'] != null ? Color(json['tint']) : tint;
    /* 4 */ order = double.parse((json['order'] ?? order).toString());

    /* 5 */ columnID = json['columnID'] ?? columnID;
    /* 6 */ date = json["date"] != null
        ? DateTime.fromMillisecondsSinceEpoch(json["date"] * 60 * 60 * 1000)
        : date;
    /* 7 */ note = json['note'] ?? note;
    /* 8 */
    if (json["comments"] != null) {
      comments = [];
      for (var comment in json["comments"]) {
        comments.add([comment[0], comment[1]]);
      }
    }
    /* 9 */ done = json['done'] ?? done;
    /* 10 */ attachments =
        List<String>.from(json["attachments"] ?? attachments);
    /* 11 */ createdBy = json['createdBy'] ?? createdBy;
    /* 12 */ assignedTo = json['assignedTo'] ?? assignedTo;
    /* 13 */ dueDate = json["dueDate"] != null
        ? DateTime.fromMillisecondsSinceEpoch(json["dueDate"] * 60 * 60 * 1000)
        : dueDate;
    /* 14 */ forPatient = json['forPatient'] ?? forPatient;
    /* 15 */ recurringInterval = json['recurringInterval'] ?? recurringInterval;
    /* 16 */ parentID = json['parentID'] ?? parentID;
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    final d = Note.fromJson({});
    /* 1 */ if (isColumn != d.isColumn) json['isColumn'] = isColumn;
    /* 2 */ if (columnName != d.columnName) {
      json['columnName'] = columnName;
    }
    /* 3 */ if (tint != d.tint) json['tint'] = tint?.toARGB32();
    /* 4 */ if (order != d.order) json['order'] = order;

    /* 5 */ if (columnID != d.columnID) json['columnID'] = columnID;
    /* 6 */ json['date'] =
        (date.millisecondsSinceEpoch / (60 * 60 * 1000)).round();
    /* 7 */ if (note != d.note) json['note'] = note;
    /* 6 */ if (comments.isNotEmpty) json['comments'] = comments;
    /* 7 */ if (done != d.done) json['done'] = done;
    /* 10 */ if (attachments.isNotEmpty) json['attachments'] = attachments;
    /* 11 */ if (createdBy != d.createdBy) json['createdBy'] = createdBy;
    /* 12 */ if (assignedTo != d.assignedTo) json['assignedTo'] = assignedTo;
    /* 13 */ json['dueDate'] =
        (dueDate.millisecondsSinceEpoch / (60 * 60 * 1000)).round();
    /* 14 */ if (forPatient != d.forPatient) json['forPatient'] = forPatient;
    /* 15 */ if (recurringInterval != d.recurringInterval) {
      json['recurringInterval'] = recurringInterval;
    }
    /* 16 */ if (parentID != d.parentID) json['parentID'] = parentID;

    return json;
  }

  @override
  Map<String, dynamic> get jsonCopyForPush {
    return {
      "comments": comments,
      "done": done,
      "attachments": attachments,
      "assignedTo": assignedTo,
      "dueDate": (dueDate.millisecondsSinceEpoch / (60 * 60 * 1000)).round(),
      "archived": archived,
    };
  }

  @override
  List<String> get pushIfChanged =>
      ["comments", "done", "attachments", "assignedTo", "dueDate", "archived"];

  @override
  bool get pushOnCreation => true;

  @override
  List<String> get targetsToPushTo => [
        if (assignedTo.isNotEmpty) assignedTo,
        if (createdBy.isNotEmpty) createdBy,
      ];
}

import 'package:apexo/features/accounts/open_account_panel.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/expenses/expense_model.dart';
import 'package:apexo/features/notes/notes_model.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/features/settings/settings_model.dart';

// ──────────────────────────────────────────────────────────────────────────────
// Model Factories
//
// Each factory returns a fully-constructed model instance with sensible
// defaults. Pass only the fields you care about — everything else gets a
// reasonable default so tests stay focused on what they're actually testing.
//
// Every model gets a unique random id via uuid() by default.
// ──────────────────────────────────────────────────────────────────────────────

/// Creates a test [Patient] with sensible defaults.
Patient testPatient({
  String? id,
  String name = 'John Doe',
  int birth = 1990,
  int gender = 1,
  String phone = '+1234567890',
  String email = 'john@example.com',
  String address = '123 Main St',
  List<String>? tags,
  String notes = '',
  Map<String, String>? teeth,
  Map<String, String>? teethExtraNotes,
  bool? archived,
}) {
  return Patient.fromJson({
    if (id != null) 'id': id,
    'title': name,
    'birth': birth,
    'gender': gender,
    'phone': phone,
    'email': email,
    'address': address,
    'tags': tags ?? [],
    'notes': notes,
    'teeth': teeth ?? {},
    'teethExtraNotes': teethExtraNotes ?? {},
    if (archived != null) 'archived': archived,
  });
}

/// Creates a test [Appointment] with sensible defaults.
Appointment testAppointment({
  String? id,
  String? patientID,
  List<String>? operatorsIDs,
  DateTime? date,
  int duration = 30,
  double price = 100.0,
  double paid = 0.0,
  bool isDone = false,
  String preOpNotes = '',
  String postOpNotes = '',
  List<String>? prescriptions,
  Map<String, String>? teeth,
  Map<String, String>? teethExtraNotes,
  bool hasLabwork = false,
  String labName = '',
  String labworkNotes = '',
  bool labworkReceived = false,
  List<String>? imgs,
  List<String>? dcmImgs,
  Map<String, String>? drawings,
  bool? archived,
}) {
  final d = date ?? DateTime.now();
  return Appointment.fromJson({
    if (id != null) 'id': id,
    if (patientID != null) 'patientID': patientID,
    'operatorsIDs': operatorsIDs ?? [],
    'date': d.millisecondsSinceEpoch ~/ 60000,
    'duration': duration,
    'price': price,
    'paid': paid,
    'isDone': isDone,
    'preOpNotes': preOpNotes,
    'postOpNotes': postOpNotes,
    'prescriptions': prescriptions ?? [],
    'teeth': teeth ?? {},
    'teethExtraNotes': teethExtraNotes ?? {},
    'hasLabwork': hasLabwork,
    'labName': labName,
    'labworkNotes': labworkNotes,
    'labworkReceived': labworkReceived,
    'imgs': imgs ?? [],
    'dcmImgs': dcmImgs ?? [],
    'drawings': drawings ?? {},
    if (archived != null) 'archived': archived,
  });
}

/// Creates a test [Expense] with sensible defaults.
Expense testExpense({
  String? id,
  bool isSupplier = false,
  String supplierName = '',
  String supplierId = '',
  DateTime? date,
  List<String>? items,
  double cost = 0.0,
  double paidAmount = 0.0,
  bool processed = false,
  List<String>? photos,
  String notes = '',
  bool? archived,
}) {
  return Expense.fromJson({
    if (id != null) 'id': id,
    'isSupplier': isSupplier,
    'supplierName': supplierName,
    'supplierId': supplierId,
    'date': (date ?? DateTime.now()).millisecondsSinceEpoch,
    'items': items ?? [],
    'cost': cost,
    'paidAmount': paidAmount,
    'processed': processed,
    'photos': photos ?? [],
    'notes': notes,
    if (archived != null) 'archived': archived,
  });
}

/// Creates a test [Note] with sensible defaults.
Note testNote({
  String? id,
  bool isColumn = false,
  String columnName = '',
  int? tint,
  double order = 0,
  String columnID = '',
  DateTime? date,
  String note = '',
  List<List<String>>? comments,
  bool done = false,
  List<String>? attachments,
  String createdBy = '',
  String assignedTo = '',
  DateTime? dueDate,
  String forPatient = '',
  int? recurringInterval,
  String? parentID,
  bool? archived,
}) {
  return Note.fromJson({
    if (id != null) 'id': id,
    'isColumn': isColumn,
    'columnName': columnName,
    if (tint != null) 'tint': tint,
    'order': order,
    'columnID': columnID,
    'date': ((date ?? dueDate ?? DateTime.now()).millisecondsSinceEpoch) ~/
        (60 * 60 * 1000),
    'note': note,
    'comments': comments ?? [],
    'done': done,
    'attachments': attachments ?? [],
    'createdBy': createdBy,
    'assignedTo': assignedTo,
    'dueDate': ((dueDate ?? DateTime.now()).millisecondsSinceEpoch) ~/
        (60 * 60 * 1000),
    'forPatient': forPatient,
    if (recurringInterval != null) 'recurringInterval': recurringInterval,
    if (parentID != null) 'parentID': parentID,
    if (archived != null) 'archived': archived,
  });
}

/// Creates a test [AccountModel] with sensible defaults.
AccountModel testAccount({
  String? id,
  String email = 'test@example.com',
  String password = 'test123456',
  String name = 'Test User',
  List<int>? permissions,
  bool operates = true,
  bool isAdmin = false,
}) {
  return AccountModel.fromJson({
    if (id != null) 'id': id,
    'email': email,
    'password': password,
    'name': name,
    'permissions':
        permissions ?? [2, 2, 2, 2, 2, 2, 2, 2, 2], // full permissions
    'operate': operates,
    'isAdmin': isAdmin,
    'type': isAdmin ? 'admin' : 'user',
  });
}

/// Creates a test [Setting] with sensible defaults.
Setting testSetting({
  String? id,
  String value = '',
}) {
  return Setting.fromJson({
    'id': id ?? 'setting_key',
    'value': value,
  });
}

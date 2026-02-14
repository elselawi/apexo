import 'dart:math';

import 'package:apexo/features/accounts/accounts_screen.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/expenses/expense_model.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/utils/uuid.dart';
import 'package:pocketbase/pocketbase.dart';

const _firstNames = [
  "John",
  "Jane",
  "Bob",
  "Alice",
  "Mike",
  "Emily",
  "David",
  "Sarah",
  "Tom",
  "Lisa",
  "Chris",
  "Karen",
  "Mark",
  "Laura",
  "Kevin",
  "Olivia",
  "Steve",
  "Rachel",
  "Paul",
  "Amanda",
  "Eric",
  "Jessica",
  "Brian",
  "Megan",
  "Ryan",
  "Stephanie",
  "Jeff",
  "Nicole",
  "Scott",
  "Melissa",
  "Greg",
  "Lauren",
  "Matt",
  "Hannah",
  "Peter",
  "Ashley",
  "Tim",
  "Katherine",
  "Josh",
  "Christine",
  "Andrew",
  "Natalie",
  "Ray",
  "Amber",
  "Kevin",
  "Rachel",
  "Chris",
  "Megan",
  "Brian",
  "Stephanie",
  "Jeff",
  "Nicole",
  "Scott",
  "Melissa",
  "Greg",
  "Lauren",
  "Matt",
  "Hannah",
  "Peter",
  "Ashley",
  "Tim",
  "Katherine",
  "Josh",
];

const _lastNames = [
  "Smith",
  "Johnson",
  "Williams",
  "Jones",
  "Brown",
  "Davis",
  "Miller",
  "Wilson",
  "Moore",
  "Taylor",
  "Anderson",
  "Thomas",
  "Jackson",
  "White",
  "Harris",
  "Martin",
  "Thompson",
  "Garcia",
  "Martinez",
  "Robinson",
  "Clark",
  "Rodriguez",
  "Lewis",
  "Lee",
  "Walker",
  "Hall",
  "Allen",
  "Young",
  "Hernandez",
  "King",
  "Wright",
  "Lopez",
  "Hill",
  "Scott",
  "Green",
  "Adams",
  "Baker",
  "Gonzalez",
  "Nelson",
  "Carter",
  "Mitchell",
  "Perez",
  "Roberts",
  "Turner",
  "Phillips",
  "Campbell",
];

const _patientTags = [
  "Diabetic",
  "Hypertensive",
  "Asthmatic",
  "Heart Patient",
  "Conservative",
  "Smoker",
];

const _preOpNotes = [
  "routine dental checkup.",
  "root canal treatment.",
  "dental implant placement.",
  "dental bridge placement.",
  "dental cleaning.",
  "dental filling.",
  "dental crown placement.",
  "dental extraction.",
  "dental veneer placement.",
  "dental whitening.",
  "dental bonding.",
  "dental inlay placement.",
  "dental onlay placement.",
  "dental veneer removal.",
  "dental bonding removal.",
  "dental inlay removal.",
  "dental onlay removal.",
  "dental whitening removal.",
  "dental brackets removal.",
  "dental brackets placement.",
  "wisdom tooth removal.",
];

const _postOpNotes = [
  "Done with no complications.",
  "Bleeding stopped.",
  "No complications.",
  "Prescription given.",
  "Next appointment scheduled.",
  "Follow-up required",
  "Fractured tooth.",
  "Fractured instrument",
  "Infection",
  "Nerve damage.",
  "Pain management is required.",
  "Given prescription for pain management.",
  "Prescription for antibiotics.",
  "Full recovery expected.",
  "Patient is recovering well.",
  "Patient is recovering slowly.",
  "Slow healing process.",
  "Oral hygiene instructions given.",
  "Patient is not responding well.",
  "Patient is in pain.",
  "Patient is not comfortable.",
  "Patient is not happy with the result.",
  "Patient is not satisfied with the result.",
  "Over the counter medication given.",
  "Over instrumentation was done.",
  "Can not be done.",
  "Expectation of the patient can not be met.",
  "Reassurance given.",
];

const _suppliersNames = [
  "Globaldentix",
  "Pattersen Dental",
  "UMGROUP",
  "Bingo Dental"
];

const List<String> _teeth = [
  "11",
  "12",
  "14",
  "18",
  "32",
  "21",
  "22",
  "24",
  "25",
  "26",
  "31",
  "33",
  "35",
  "36",
  "27",
  "41",
  "42",
  "42",
  "43"
];

const List<String> _teethNotes = [
  "extraction",
  "filling",
  "pulpotomy",
  "rCT",
  "re-RCT",
  "ortho",
  "whitening",
  "clean",
  "implant",
  "surgery",
  "crown",
  "veneer",
  "bridge",
  "overlay",
  "temporary",
  "other",
];

const List<String> _prescriptions = [
  "Amoxicillin 500mg 1x3 - 5 days",
  "Azithromycin 500mg 1x3 - 5 days",
  "Flagyl 500mg 1x3 - 5 days",
  "Ibuprofen 400mg on need",
  "Dexamethosone 8mg ampoule 1x1 - 2 days"
];

const List<String> _labs = [
  "Master Design Lab",
  "Everest Dental Lab",
  "Galaxy Orthodontics Lab",
  "Royal Dental Lab",
  "Acer Veneers Lab",
];

const List<String> _labworkNotes = [
  "Zirconia Crown",
  "Ceramic Crown",
  "Lithium Disilicate Crown",
  "Resin Crown",
  "Onlay",
  "Inlay",
  "Inlay and Onlay",
  "Dental Veneer",
  "Dental Veneer and Crown",
  "Hyrax",
  "Expander",
  "Retainer",
  "Invisalign",
  "Invisalign Teen",
  "Invisalign Express",
  "Invisalign Lite",
  "Aligners",
  "Quad-Helix",
];

const List<String> _receiptItems = [
  "Paper",
  "Ink",
  "Toner",
  "Toner Cartridge",
  "Pens",
  "Stapler",
  "Mosquito",
  "Bond",
  "Composite",
  "Braces",
  "Screw",
  "Dental Implant",
  "Strip",
  "Forceps",
  "Gutta Percha",
  "Gutta Percha Rod",
  "X-ray Film",
  "X-ray Film Holder",
  "Alcohol",
  "Cotton",
  "Gauze",
  "Gauze Roll",
  "Gauze Pad",
  "Sterilizer",
  "Sterilizer Bag",
  "Sterilizer Tray",
  "Surgical Instruments",
  "Chlorhexidine",
  "Chlorhexidine Gauze",
  "Solvent",
  "3D Printing Resin",
  "FEP Film",
  "Water",
  "Rubber Dam",
  "Celluloid Strip",
  "Posterior Composite",
  "Dental Cement",
  "Dental Adhesive",
  "Dental Adhesive Remover",
  "Burs",
  "Dental Drill",
  "Dental burs",
  "Anesthetic",
  "Needles",
  "Gloves",
  "Masks",
  "Cotton",
  "Gauze",
  "Saliva",
  "Prophy",
  "Fluoride",
  "Impression",
  "Alginate",
  "Composite",
  "Etching",
  "Matrix",
  "Wedges",
  "Explorers",
  "Scalers",
  "Curettes",
  "Excavators",
  "Forceps",
  "Elevators",
  "Rubber",
  "Rubber",
  "Endodontic",
  "Gutta-percha",
  "Temporary crown",
  "Surgical",
  "Bone",
  "Implant",
  "Protective",
  "Disinfectants",
  "Autoclave",
  "Sterilization",
  "Tray",
  "Suction",
  "Mixing pad",
  "Applicator",
  "Polishing",
];

String _generateName() {
  final random = Random();
  final firstName = _firstNames[random.nextInt(_firstNames.length)];
  final lastName = _lastNames[random.nextInt(_lastNames.length)];
  return "$firstName $lastName";
}

String _generateEmail(String name) {
  return "${name.replaceAll(" ", ".")}@gmail.com";
}

String _randomAddress() {
  final random = Random();
  return "${random.nextInt(1000)} ${_lastNames[random.nextInt(_lastNames.length)]} St";
}

List<Patient> _savedPatients = [];
List<RecordModel> _savedAccounts = [];
List<Expense> _savedSuppliers = [];

Patient _demoPatient() {
  final name = _generateName();
  return Patient.fromJson({
    "title": name,
    "gender": Random().nextInt(5).isEven ? 0 : 1,
    "phone": "+1 555-555-5555",
    "address": _randomAddress(),
    "birth": DateTime.now().year - 5 - Random().nextInt(55),
    "tags": List.generate(Random().nextInt(5).isEven ? 0 : 1,
        (_) => _patientTags[Random().nextInt(_patientTags.length)]),
  });
}

Appointment _demoAppointment() {
  final patient = _savedPatients[Random().nextInt(_savedPatients.length)];
  final price = Random().nextInt(1000);
  final date = DateTime.now()
      .add(Duration(hours: Random().nextInt(24 * 30)))
      .subtract(Duration(hours: Random().nextInt(24 * 200)));
  final future = date.isAfter(DateTime.now());
  return Appointment.fromJson({
    "date": date.millisecondsSinceEpoch / 60000,
    "isDone": future
        ? false
        : Random().nextInt(10) == 5
            ? false
            : true,
    "patientID": patient.id,
    "preOpNotes": _preOpNotes[Random().nextInt(_preOpNotes.length)],
    "postOpNotes":
        future ? "" : _postOpNotes[Random().nextInt(_postOpNotes.length)],
    "prescriptions": [
      if (Random().nextBool())
        _prescriptions[Random().nextInt(_prescriptions.length)]
    ],
    "hasLabwork": price > 500,
    "labworkNotes": _labworkNotes[Random().nextInt(_labworkNotes.length)],
    "labName": _labs[Random().nextInt(_labs.length)],
    "labworkReceived": DateTime.now().difference(date).inDays > 30,
    "price": price,
    "teeth": {
      if (Random().nextBool())
        _teeth[Random().nextInt(_labs.length)]:
            _teethNotes[Random().nextInt(_labs.length)],
      if (Random().nextBool())
        _teeth[Random().nextInt(_labs.length)]:
            _teethNotes[Random().nextInt(_labs.length)],
    },
    "paid": future
        ? null
        : Random().nextInt(20) == 15
            ? Random().nextInt(1500)
            : price,
  });
}

RecordModel _demoAccount() {
  final name = _generateName();
  return RecordModel.fromJson({
    "id": uuid(),
    "email": _generateEmail(name),
    "name": name,
    "operate": 1,
    "permissions": fullPermissions,
    "type": "admin"
  });
}

Expense _demoExpense() {
  final date = DateTime.now()
      .add(Duration(hours: Random().nextInt(24 * 30)))
      .subtract(Duration(hours: Random().nextInt(24 * 200)));
  final future = date.isAfter(DateTime.now());
  final price = Random().nextInt(700);
  return Expense.fromJson({
    "supplierId": _savedSuppliers[Random().nextInt(_savedSuppliers.length)].id,
    "date": (date.millisecondsSinceEpoch / (60 * 60 * 1000)).toInt(),
    "items": List.generate(Random().nextInt(12) + 1,
        (_) => _receiptItems[Random().nextInt(_receiptItems.length)]),
    "cost": price,
    "paidAmount": future ? 0 : price,
    "processed": future ? false : true
  });
}

List<RecordModel> demoAccounts(int length) {
  _savedAccounts = List.generate(length, (_) => _demoAccount());
  return _savedAccounts;
}

List<Patient> demoPatients(int length) {
  _savedPatients = List.generate(length, (_) => _demoPatient());
  return _savedPatients;
}

List<Appointment> demoAppointments(int length) {
  return List.generate(length, (_) => _demoAppointment());
}

List<Expense> _demoSuppliers() {
  return _suppliersNames
      .map((name) =>
          Expense.fromJson({"isSupplier": true, "supplierName": name}))
      .toList();
}

List<Expense> demoExpenses(int length) {
  _savedSuppliers = _demoSuppliers();
  return [..._savedSuppliers, ...List.generate(length, (_) => _demoExpense())];
}

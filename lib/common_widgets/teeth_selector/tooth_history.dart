/// Read-only presentation of an existing patient or appointment record.
class ToothHistory {
  const ToothHistory(
      {required this.label,
      required this.teeth,
      required this.notes,
      this.date,
      this.appointmentId});
  final String label;
  final Map<String, String> teeth;
  final Map<String, String> notes;
  final DateTime? date;

  /// The appointment this record came from, when it came from one. Records
  /// that belong to the patient's own chart carry no id, and the card only
  /// offers to open the ones that can be opened.
  final String? appointmentId;
}

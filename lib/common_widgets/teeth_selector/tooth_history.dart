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

  /// Null for records from the patient's own chart; only records with an id
  /// can be opened.
  final String? appointmentId;
}

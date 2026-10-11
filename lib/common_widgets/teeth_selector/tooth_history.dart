/// Read-only presentation of an existing patient or appointment record.
class ToothHistory {
  const ToothHistory(
      {required this.label,
      required this.teeth,
      required this.notes,
      this.date});
  final String label;
  final Map<String, String> teeth;
  final Map<String, String> notes;
  final DateTime? date;
}

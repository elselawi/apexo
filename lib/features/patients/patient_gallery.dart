import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/appointments/open_appointment.dart';
import 'package:apexo/features/appointments/visit_gallery.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';

List<Appointment> patientGalleryVisits(Patient patient) {
  final seen = <String>{};
  return [
    ...patient.appointmentsWithImages,
    ...patient.appointmentsWithDcmImgs,
  ].where((visit) => seen.add(visit.id)).toList()
    ..sort((a, b) => b.date.compareTo(a.date));
}

/// Every photo and X-ray of [patient], one [VisitPhotosCard] per visit — the
/// files belong to the visit, so this is only a way to see them all at once.
class PatientGallery extends StatelessWidget {
  const PatientGallery(this.patient, {super.key, this.onOpenVisit});

  final Patient patient;

  /// Overrides visit opening so a standalone gallery can make way for the visit.
  final void Function(Appointment appointment, AppointmentWindow window)?
      onOpenVisit;

  @override
  Widget build(BuildContext context) {
    return MStreamBuilder(
      streams: [appointments.observableMap.stream],
      builder: (context, _) {
        final visits = patientGalleryVisits(patient);
        if (visits.isEmpty) {
          return InfoBar(title: Txt(txt("noPhotos")));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (index, visit) in visits.indexed)
              VisitPhotosCard(
                key: ValueKey(visit.id),
                visit,
                number: index + 1,
                onOpen: onOpenVisit,
              ),
          ],
        );
      },
    );
  }
}

import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/appointments/open_appointment.dart';
import 'package:apexo/features/appointments/visit_gallery.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// The visits of [patient] that hold photos or X-rays, newest first.
///
/// A visit that holds both is one entry, not two: the gallery groups by the
/// visit a file belongs to, and a visit listed twice would read as two visits.
List<Appointment> patientGalleryVisits(Patient patient) {
  final seen = <String>{};
  return [
    ...patient.appointmentsWithImages,
    ...patient.appointmentsWithDcmImgs,
  ].where((visit) => seen.add(visit.id)).toList()
    ..sort((a, b) => b.date.compareTo(a.date));
}

/// Every photo and X-ray of [patient], newest visit first.
///
/// One [VisitPhotosCard] per visit — the same card a visit's own gallery lists
/// for the patient's other visits — so the window shows the pictures under the
/// date of the visit holding them, and opens that visit. The files are the
/// visit's own: deleting one, or drawing on it, changes the visit and nothing
/// else. The patient's window is one place to see them all, not a second place
/// they belong to.
class PatientGallery extends StatelessWidget {
  const PatientGallery(this.patient, {super.key, this.onOpenVisit});

  final Patient patient;

  /// How a visit is opened from its card. A window shown on its own passes an
  /// opener that makes way for the visit instead of leaving the gallery open
  /// behind it.
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

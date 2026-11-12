import 'package:apexo/shared/dental_chart/dental_chart_window_spec.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// Patient panel windows, in panel order; [patientWindows] applies permissions.
enum PatientWindow {
  /// The patient's own details — the window that answers most questions.
  details('details', "patientDetails", FluentIcons.medication_admin),

  dentalChart(
      kDentalChartWindowId, kDentalChartDockTitleKey, FluentIcons.teeth),

  /// The visits of this patient.
  appointments('appointments', "appointments", WindowsIcons.calendar),

  /// Every photo and X-ray of this patient, grouped by the visit holding it.
  gallery('gallery', "gallery", WindowsIcons.camera),

  /// The shareable patient page.
  page('page', "patientPage", FluentIcons.q_r_code);

  const PatientWindow(this.id, this.titleKey, this.icon);

  /// The window's [PanelWindow.id], for panels and openers to name it by.
  final String id;

  final String titleKey;
  final IconData icon;
}

double appointmentsListHeight(int count) =>
    (kAppointmentCardHeight * count + kAppointmentsListChrome).clamp(
      appointmentsListMinHeight,
      appointmentsListMaxHeight,
    );

/// A real visit card measures ~188px; the chrome is what surrounds the list.
const double kAppointmentCardHeight = 190;
const double kAppointmentsListChrome = 70;

/// The list's own floor and ceiling, in the window it is drawn in.
const double appointmentsListMinHeight = 320;
const double appointmentsListMaxHeight = 640;

/// The patient's windows for the current user, in panel order.
List<PatientWindow> patientWindows() => [
      PatientWindow.details,
      PatientWindow.dentalChart,
      if (login.perm(Perm.appointments).some) PatientWindow.appointments,
      PatientWindow.gallery,
      PatientWindow.page,
    ];

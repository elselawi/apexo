import 'package:apexo/shared/dental_chart/dental_chart_window_spec.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// The windows a patient's panel offers, in the order it offers them.
///
/// The panel builds its list from [patientWindows], and row menus and table
/// cells name a window through [PatientWindow] rather than counting them, so
/// none of them can drift when a window is added, removed or moved.
enum PatientWindow {
  /// The patient's own details — the window that answers most questions.
  details('details', "patientDetails", FluentIcons.medication_admin),

  /// The dental chart, beside the details: the record's own teeth — its history,
  /// and the treatments planned on it.
  dentalChart(kDentalChartWindowId, kDentalChartTitleKey, FluentIcons.teeth),

  /// The visits of this patient.
  appointments('appointments', "appointments", WindowsIcons.calendar),

  /// The shareable patient page.
  page('page', "patientPage", FluentIcons.q_r_code);

  const PatientWindow(this.id, this.titleKey, this.icon);

  /// The window's [PanelWindow.id], for panels and openers to name it by.
  final String id;

  final String titleKey;
  final IconData icon;
}

/// The height a patient's visit list wants: one card per visit, inside the
/// window's floor and ceiling.
///
/// A visit's card is a fixed layout, so counting them is enough to say how much
/// room the list needs — a patient with two visits gets a short window instead of
/// a tall one with two cards and a gap, and one with eight is not squeezed into
/// half a screen.
double appointmentsListHeight(int count) =>
    (kAppointmentCardHeight * count + kAppointmentsListChrome).clamp(
      appointmentsListMinHeight,
      appointmentsListMaxHeight,
    );

/// Roughly one visit's card — measured, not guessed: a visit card is 188 tall in
/// the app's own layout — and what surrounds the list.
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
      PatientWindow.page,
    ];

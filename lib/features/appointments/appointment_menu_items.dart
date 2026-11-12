import 'dart:async';

import 'package:apexo/common_widgets/contact_buttons.dart';
import 'package:apexo/common_widgets/context_menu_region.dart';
import 'package:apexo/common_widgets/delete_button.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/appointments/open_appointment.dart';
import 'package:apexo/features/patients/open_patient_panel.dart';
import 'package:apexo/features/patients/patient_windows.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// The patient record already offers its history, record and phone actions.
enum AppointmentMenuContext { calendar, patientRecord }

/// The visit's context menu, shared by agenda, timeline and history so
/// permissions match. [menuContext] hides only what the patient record offers.
List<MenuFlyoutItemBase> appointmentMenuItems({
  required Appointment item,
  required void Function(AppointmentWindow window) onOpenWindow,
  required FlyoutController controller,
  AppointmentMenuContext menuContext = AppointmentMenuContext.calendar,
}) {
  final inPatientRecord = menuContext == AppointmentMenuContext.patientRecord;
  final patient = item.patient;
  final phones = patient?.phone ?? const [];
  final email = patient?.email ?? '';
  return [
    for (final window in appointmentWindows(item))
      MenuFlyoutItem(
        text: menuTitleSuffix(
          Txt(txt(window.titleKey)),
          switch (window) {
            AppointmentWindow.dentalChart => menuCountSuffix(item.teeth.length),
            AppointmentWindow.labwork => menuPresenceSuffix(item.hasLabwork),
            AppointmentWindow.gallery => menuCountSuffix(
                item.viewableImgs.length + item.viewableDcmImgs.length),
            _ => null,
          },
        ),
        leading: Icon(window.icon),
        onPressed: () {
          // From the calendar, labwork and gallery ask to stand on their own, so
          // the visit's panel does not bury them; with no panel on screen they do,
          // and beside one the visit's panel takes them. Inside the record they
          // stay in its panel.
          final standalone = menuContext == AppointmentMenuContext.calendar &&
              (window == AppointmentWindow.labwork ||
                  window == AppointmentWindow.gallery);
          if (standalone) {
            unawaited(openAppointmentWindowOnItsOwn(item, window));
          } else {
            onOpenWindow(window);
          }
        },
      ),
    if (login.perm(Perm.appointments).some) ...[
      const MenuFlyoutSeparator(),
      MenuFlyoutItem(
        text: Txt(txt(item.isDone ? "markAsPending" : "markAsDone")),
        leading:
            Icon(item.isDone ? FluentIcons.hour_glass : WindowsIcons.completed),
        onPressed: () =>
            appointmentCommand(item.id, (draft) => draft.isDone = !item.isDone),
      ),
    ],
    if (!inPatientRecord &&
        patient != null &&
        (login.perm(Perm.appointments).some ||
            login.perm(Perm.patients).some)) ...[
      const MenuFlyoutSeparator(),
      if (login.perm(Perm.appointments).some)
        MenuFlyoutItem(
          text: menuTitleSuffix(
            Txt(txt("allAppointments")),
            menuCountSuffix(patient.allAppointments.length),
          ),
          leading: const Icon(WindowsIcons.calendar),
          onPressed: () =>
              unawaited(openPatient(patient, PatientWindow.appointments)),
        ),
      if (login.perm(Perm.patients).some)
        MenuFlyoutItem(
          // `{name}` stays in the localized sentence so each language can place it.
          text:
              Txt(txt("openPatientRecord").replaceAll("{name}", patient.title)),
          leading: const Icon(FluentIcons.medication_admin),
          onPressed: () => unawaited(openPatient(patient)),
        ),
    ],
    if ((!inPatientRecord && phones.isNotEmpty) || email.isNotEmpty)
      ...contactMenuItems(
        phones: inPatientRecord ? const [] : phones,
        email: email,
      ),
    // Archiving takes the clinical record with it, so it needs full visits access.
    if (login.perm(Perm.appointments).full) ...[
      const MenuFlyoutSeparator(),
      confirmDeleteMenuItem(
        controller: controller,
        preview: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 5,
          children: [
            const Icon(WindowsIcons.calendar),
            Txt("${txt("appointment")} ${DF.commonDate(item.date)}"),
          ],
        ),
        onConfirm: () => appointments.archive(item.id),
      ),
    ],
  ];
}

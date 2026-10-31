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

/// The items a visit's context menu offers, wherever the visit is shown: one per
/// window of its panel, then the actions the row itself carries.
///
/// Shared by the agenda, timeline and patient history, so every view keeps the
/// same window and action permissions.
///
/// [onOpenWindow] receives the window the user picked; the caller decides how to
/// open it (the agenda's rows know their own `Item` type, the timeline works on
/// `Appointment`).
///
/// [controller] is the context menu's own controller, used to anchor the delete
/// confirmation to the row rather than to another target.
/// [menuContext] omits history, patient navigation and phone actions already
/// available in the patient's record, without changing the visit's actions.
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
          // What the window holds, appended after the title: how many teeth
          // this visit treated, whether it placed a labwork order, and how many
          // photos and X-rays its gallery has.
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
          // From the calendar's menus these two are the order and the photos,
          // not the visit: opening the patient panel as well buries the window
          // under the record it came from. Inside the patient's own record the
          // same choices stay in that record's panel.
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
      // The checkbox lives in the tile, but a finger reaching for the row
      // should be able to finish the visit from here too.
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
      // The patient's whole history beside the visit being looked at: the list
      // includes this visit, and every other one opens from it.
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
          // Whose record, not just "the record": a visit row says a name, and
          // the menu is where the record behind it is reached. The name sits
          // inside the sentence so each language can put it in its own place.
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
    // Archiving a visit takes its clinical record with it: full access to
    // visits, not the personal level that may edit the ones it owns.
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

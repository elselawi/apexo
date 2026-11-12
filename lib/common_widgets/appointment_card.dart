import 'dart:async';

import 'dart:math';
import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/delete_button.dart';
import 'package:apexo/common_widgets/error_dialog.dart';
import 'package:apexo/common_widgets/money_display.dart';
import 'package:apexo/common_widgets/teeth_selector/tx_options.dart';
import 'package:apexo/core/model.dart';
import 'package:apexo/features/accounts/accounts_controller.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/utils/color_based_on_payment.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/features/appointments/appointment_owner_line.dart';
import 'package:apexo/features/appointments/open_appointment.dart';
import 'package:apexo/common_widgets/item_title.dart';
import 'package:apexo/common_widgets/grid_gallery.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/ui/design/fluent_materials.dart';
import 'package:apexo/utils/constants.dart';
import 'package:apexo/utils/logger.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';

enum AppointmentSections {
  patient,
  doctors,
  photos,
  preNotes,
  postNotes,
  dentalNotes,
  prescriptions,
  labworks,
  pay,
  appointmentNumber,
  timeDifference,
  openAppointmentButton,
  paymentSummary,
}

class AppointmentCard extends StatelessWidget {
  const AppointmentCard({
    super.key,
    required this.appointment,
    this.difference,
    this.readOnly = false,
    required this.number,
    this.hide = const [],
    this.photosClipCount = 3,
    this.showLeftBorder = true,
    this.showSectionTitle = true,
    this.openButtonColor = const Color(0xFF0078D4),
    this.openOnWindow = AppointmentWindow.details,
    this.onOpen,
    this.onTapDcm,
    this.canDeletePhotos,
  });
  final Appointment appointment;
  final List<AppointmentSections> hide;
  final String? difference;
  final int number;
  final int photosClipCount;
  final bool readOnly;
  final bool showLeftBorder;
  final bool showSectionTitle;
  final Color openButtonColor;
  final AppointmentWindow openOnWindow;

  final void Function(Appointment appointment, AppointmentWindow window)?
      onOpen;

  final void Function(BuildContext context, String rowId, String dcmName)?
      onTapDcm;

  /// Null uses the photos permission alone; deleting a file writes to its
  /// visit, so callers showing files elsewhere check the visit permission too.
  final bool? canDeletePhotos;

  void _open(AppointmentWindow window) {
    final open = onOpen;
    if (open != null) {
      open(appointment, window);
      return;
    }
    unawaited(openAppointment(appointment, window));
  }

  VoidCallback? _sectionOpener(AppointmentWindow window) {
    if (hide.contains(AppointmentSections.openAppointmentButton) ||
        !appointmentWindows(appointment).contains(window)) {
      return null;
    }
    return () => _open(window);
  }

  @override
  Widget build(BuildContext context) {
    final color = appointment.archived == true
        ? (FluentTheme.of(context).iconTheme.color ?? Colors.grey)
        : (appointment.isMissed)
            ? Colors.red
            : appointment.color;

    return Padding(
      padding: showLeftBorder
          ? const EdgeInsets.fromLTRB(7, 15, 15, 0)
          : const EdgeInsetsGeometry.all(7),
      child: Column(
        spacing: 10,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (readOnly == false)
                Column(
                  key: WK.acSideIcons,
                  spacing: 10,
                  children: [
                    _doneCheckBox(color),
                    if (appointment.isMissed == true)
                      Icon(FluentIcons.event_date_missed12, color: color)
                    else if (!appointment.fullPaid)
                      Icon(FluentIcons.money, color: color),
                    DeleteButton(
                      onConfirm: () {
                        appointments.archive(appointment.id);
                      },
                      preview: Txt(
                          "${txt("appointment")} ${DF.commonDate(appointment.date)}"),
                      actionText: txt("delete"),
                      actionIcon: WindowsIcons.delete,
                      restorable: true,
                      style: ButtonStyle(
                          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
                              borderRadius: BorderRadiusGeometry.circular(5),
                              side: BorderSide(
                                  color: FluentTheme.of(context)
                                      .inactiveColor
                                      .withAlpha(100))))),
                      child: const Icon(WindowsIcons.delete, size: 13),
                    )
                  ],
                ),
              if (readOnly == false) const SizedBox(width: 4),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                      borderRadius: FluentMaterials.surfaceRadius,
                      color: FluentMaterials.of(context).card,
                      border: Border.all(
                        color: FluentMaterials.of(context).hairline,
                        width: FluentMaterials.hairlineWidth,
                      ),
                      boxShadow: FluentMaterials.of(context).windowShadow),
                  child: Container(
                    decoration:
                        showLeftBorder ? _coloredHandleDecoration(color) : null,
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      spacing: 5,
                      children: [
                        _buildHeader(context, color),
                        if (appointment.patient != null &&
                            !hide.contains(AppointmentSections.patient)) ...[
                          const Divider(
                            direction: Axis.horizontal,
                          ),
                          _buildSection(
                              txt("patient"),
                              ItemTitle(item: appointment.patient!),
                              FluentIcons.medical,
                              color,
                              context,
                              onOpen:
                                  _sectionOpener(AppointmentWindow.details)),
                        ],
                        if (appointment.operatorsIDs.isNotEmpty &&
                            !hide.contains(AppointmentSections.doctors)) ...[
                          const Divider(
                            direction: Axis.horizontal,
                          ),
                          _buildSection(
                              txt("doctors"),
                              Column(
                                children: appointment.operatorsIDs
                                    .map((id) => ItemTitle(
                                        item: Model.fromJson({
                                          "title":
                                              accounts.nameOrEmailFromID(id)
                                        }),
                                        maxWidth: 115))
                                    .toList(),
                              ),
                              FluentIcons.medical,
                              color,
                              context,
                              onOpen:
                                  _sectionOpener(AppointmentWindow.details)),
                        ],
                        if ((appointment.imgs.isNotEmpty ||
                                appointment.dcmImgs.isNotEmpty) &&
                            !hide.contains(AppointmentSections.photos)) ...[
                          const Divider(
                            direction: Axis.horizontal,
                          ),
                          _buildSection(
                              txt("photos"),
                              GridGallery(
                                canDelete: canDeletePhotos ??
                                    login.perm(Perm.photos).exact(1),
                                rowId: appointment.id,
                                owner: () => appointmentOwnerLine(appointment),
                                imgs: appointment.imgs,
                                dcmImgs: appointment.dcmImgs,
                                onTapDcm: onTapDcm,
                                countPerLine: 4,
                                clipCount: photosClipCount,
                                rowWidth: 200,
                                size: 43,
                                drawings: appointment.drawings,
                                onSaveDrawing: (img, drawing) =>
                                    appointmentCommand(
                                        appointment.id,
                                        (draft) =>
                                            draft.drawings[img] = drawing),
                                onTapClip: () {
                                  _open(AppointmentWindow.gallery);
                                },
                                onPressDelete: (img) async {
                                  try {
                                    await appointments.deleteImg(
                                      appointment.id,
                                      img,
                                    );
                                    appointmentCommand(appointment.id, (draft) {
                                      draft.drawings.remove(img);
                                      draft.imgs.remove(img);
                                    });
                                  } catch (e, s) {
                                    showErrorMessage(
                                        e, "deletingPatientImageFromServer");
                                    login.askForLoginAgain(e);
                                    logger(
                                        "Error during deleting image: $e", s);
                                  }
                                },
                                onPressDeleteDcm: (dcmName) async {
                                  try {
                                    await appointments.deleteDcmImg(
                                      appointment.id,
                                      dcmName,
                                    );
                                    appointmentCommand(
                                        appointment.id,
                                        (draft) =>
                                            draft.dcmImgs.remove(dcmName));
                                  } catch (e, s) {
                                    showErrorMessage(
                                        e, "deletingPatientImageFromServer");
                                    login.askForLoginAgain(e);
                                    logger(
                                        "Error during deleting DCM image: $e",
                                        s);
                                  }
                                },
                              ),
                              WindowsIcons.camera,
                              color,
                              context,
                              onOpen:
                                  _sectionOpener(AppointmentWindow.gallery)),
                        ],
                        if (appointment.preOpNotes.isNotEmpty &&
                            !hide.contains(AppointmentSections.preNotes)) ...[
                          const Divider(
                            direction: Axis.horizontal,
                          ),
                          _buildSection(
                              txt("pre-opNotes"),
                              Txt(
                                appointment.preOpNotes,
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w500),
                              ),
                              WindowsIcons.quick_note,
                              color,
                              context,
                              onOpen:
                                  _sectionOpener(AppointmentWindow.details)),
                        ],
                        if (appointment.postOpNotes.isNotEmpty &&
                            !hide.contains(AppointmentSections.postNotes)) ...[
                          const Divider(
                            direction: Axis.horizontal,
                          ),
                          _buildSection(
                              txt("post-opNotes"),
                              Txt(
                                appointment.postOpNotes,
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w500),
                              ),
                              WindowsIcons.quick_note,
                              color,
                              context,
                              onOpen:
                                  _sectionOpener(AppointmentWindow.details)),
                        ],
                        if (appointment.teeth.isNotEmpty &&
                            !hide
                                .contains(AppointmentSections.dentalNotes)) ...[
                          const Divider(
                            direction: Axis.horizontal,
                          ),
                          _buildSection(
                              txt("dentalNotes"),
                              Padding(
                                padding: const EdgeInsets.only(top: 5),
                                child: TreatmentLabels(
                                    showPalmer: true,
                                    labels: appointment.teeth.entries
                                        .map((e) => TreatmentLabel(
                                            string: e.value,
                                            color: labelToColor(e.value),
                                            icon: labelToIcon(e.value),
                                            iso: e.key,
                                            extraNote: appointment
                                                .teethExtraNotes[e.key]))
                                        .toList()),
                              ),
                              FluentIcons.teeth,
                              color,
                              context,
                              onOpen: _sectionOpener(
                                  AppointmentWindow.dentalChart)),
                        ],
                        if (appointment.hasLabwork &&
                            !hide.contains(AppointmentSections.labworks)) ...[
                          const Divider(
                            direction: Axis.horizontal,
                          ),
                          _buildSection(
                              txt("labwork"),
                              Txt(
                                "${appointment.labworkNotes}\n${appointment.labworkReceived ? ("➡️ ${txt("received")}") : ("⚠️ ${txt("due")}")}",
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w500),
                              ),
                              FluentIcons.manufacturing,
                              color,
                              context,
                              onOpen:
                                  _sectionOpener(AppointmentWindow.labwork)),
                        ],
                        if (appointment.prescriptions.isNotEmpty &&
                            !hide.contains(
                                AppointmentSections.prescriptions)) ...[
                          const Divider(
                            direction: Axis.horizontal,
                          ),
                          _buildSection(
                              txt("prescription"),
                              Txt(
                                appointment.prescriptions.join("\n"),
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w500),
                              ),
                              FluentIcons.pill,
                              color,
                              context,
                              onOpen:
                                  _sectionOpener(AppointmentWindow.operative)),
                        ],
                        if ((appointment.price != 0 || appointment.paid != 0) &&
                            !hide.contains(AppointmentSections.pay) &&
                            (login.perm(Perm.revenue).read ||
                                appointment.userIsOperator)) ...[
                          const Divider(
                            direction: Axis.horizontal,
                          ),
                          _buildSection(
                            "${txt("pay")}\n${currency()}",
                            _paymentPills(context),
                            FluentIcons.money,
                            color,
                            context,
                            onOpen: _sectionOpener(AppointmentWindow.operative),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (difference != null) _buildTimeDifference()
        ],
      ),
    );
  }

  Widget _doneCheckBox(Color color) {
    return Checkbox(
      key: WK.acCheckBox,
      checked: appointment.isDone,
      onChanged: (checked) => appointmentCommand(
          appointment.id, (draft) => draft.isDone = checked == true),
      style: CheckboxThemeData(
        checkedDecoration: WidgetStatePropertyAll(
          BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(5),
          ),
        ),
      ),
    );
  }

  Center _buildTimeDifference() {
    return Center(
        child: Row(
      spacing: 5,
      mainAxisAlignment: MainAxisAlignment.center,
      textDirection: TextDirection.ltr,
      children: [
        const SpacerIcon(flip: 1),
        TimeDifference(difference: difference),
        const SpacerIcon(flip: -1),
      ],
    ));
  }

  Column _paymentPills(BuildContext context) {
    final bgColor = colorBasedOnPayments(appointment.paid, appointment.price);
    final txtColor =
        bgColor ?? FluentTheme.of(context).iconTheme.color ?? Colors.grey;
    return Column(
      spacing: 5,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          spacing: 5,
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            PaymentPill(
              title: txt("price"),
              amount: appointment.price.toStringAsFixed(2),
              finalTextColor: txtColor,
            ),
            PaymentPill(
              title: txt("paid"),
              amount: appointment.paid.toStringAsFixed(2),
              finalTextColor: txtColor,
            ),
          ],
        ),
        if (appointment.paid != appointment.price)
          PaymentPill(
            title: appointment.overPaid ? txt("overpaid") : txt("underpaid"),
            amount: appointment.paymentDifference.toStringAsFixed(2),
            color: bgColor?.withAlpha(50),
            finalTextColor: txtColor,
          )
      ],
    );
  }

  Widget _buildSection(
    String title,
    Widget child,
    IconData icon,
    Color color,
    BuildContext context, {
    VoidCallback? onOpen,
  }) {
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (showSectionTitle) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 7),
            child: Row(
              spacing: 5,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(icon, size: 16),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 95),
                  child: Txt(
                    title,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 5),
        ],
        Expanded(child: child),
        if (onOpen != null) ...[
          const SizedBox(width: 6),
          Icon(
            Directionality.of(context) == TextDirection.rtl
                ? WindowsIcons.chevron_left
                : WindowsIcons.chevron_right,
            size: 11,
            color: FluentTheme.of(context).inactiveColor,
          ),
        ],
      ],
    );
    if (onOpen == null) return row;
    return Tooltip(
      message: title,
      child: Button(
        onPressed: onOpen,
        style: ButtonStyle(
          padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 2, vertical: 4)),
          backgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.pressed)
                  ? color.withValues(alpha: 0.16)
                  : states.contains(WidgetState.hovered)
                      ? color.withValues(alpha: 0.08)
                      : Colors.transparent),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          )),
        ),
        // one tap target per section: thumbnails open the gallery, where files
        // are edited.
        child: IgnorePointer(child: row),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (number > 0 &&
                  !hide.contains(AppointmentSections.appointmentNumber))
                Txt(
                  "${txt("appointment")}: $number",
                  style: TextStyle(
                    fontSize: 10,
                    color: color.withValues(alpha: 0.5),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              const SizedBox(height: 3),
              _buildFormattedDate(color),
            ],
          ),
        ),
        if (!hide.contains(AppointmentSections.openAppointmentButton)) ...[
          IconButton(
            icon: const Icon(FluentIcons.go, size: 17, color: Colors.white),
            onPressed: () => _open(openOnWindow),
            iconButtonMode: IconButtonMode.large,
            style: filledButtonStyle(openButtonColor),
          ),
        ]
      ],
    );
  }

  Text _buildFormattedDate(Color color) {
    return Txt(
      DF.full(appointment.date),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: showLeftBorder ? color : null,
        fontSize: 13,
        fontWeight: FontWeight.bold,
        fontStyle: showLeftBorder ? FontStyle.normal : FontStyle.italic,
      ),
    );
  }

  BoxDecoration _coloredHandleDecoration(Color color) {
    return BoxDecoration(
      border: BorderDirectional(
        start: BorderSide(
          color: color,
          width: 5,
        ),
      ),
    );
  }
}

class PaymentPill extends StatelessWidget {
  const PaymentPill({
    super.key,
    required this.finalTextColor,
    required this.title,
    required this.amount,
    this.color,
  });

  final Color finalTextColor;
  final String title;
  final String amount;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 60),
      decoration: BoxDecoration(
        color: (color ?? finalTextColor).withAlpha(20),
        borderRadius: BorderRadius.circular(5),
      ),
      padding: const EdgeInsets.all(7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 3,
        children: [
          Txt(
            title,
            style: TextStyle(
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.bold,
              fontSize: 11.5,
              color: finalTextColor,
            ),
          ),
          MoneyDisplay(
            amount,
            style: TextStyle(color: finalTextColor, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class TimeDifference extends StatelessWidget {
  const TimeDifference({
    super.key,
    required this.difference,
  });

  final String? difference;

  @override
  Widget build(BuildContext context) {
    return Txt(
      difference!,
      style: TextStyle(
        fontSize: 12,
        color: FluentTheme.of(context).inactiveColor.withAlpha(100),
        fontWeight: FontWeight.bold,
      ),
    );
  }
}

class SpacerIcon extends StatelessWidget {
  const SpacerIcon({super.key, required this.flip});
  final int flip;

  @override
  Widget build(BuildContext context) {
    return Transform.flip(
      flipX: flip == 1 ? true : false,
      flipY: false,
      child: Transform.translate(
        offset: Offset(0, flip < 1 ? 2.0 * flip : 5.0 * flip),
        child: Transform.rotate(
          angle: (pi / (flip == 1 ? 2 : 1)) * flip,
          child: Icon(
            color: FluentTheme.of(context).inactiveColor.withAlpha(100),
            FluentIcons.turn_right,
            size: 14,
          ),
        ),
      ),
    );
  }
}

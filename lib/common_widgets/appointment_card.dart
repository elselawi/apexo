import 'dart:math';
import 'package:apexo/common_widgets/error_dialog.dart';
import 'package:apexo/common_widgets/money_display.dart';
import 'package:apexo/common_widgets/teeth_selector/tx_options.dart';
import 'package:apexo/core/model.dart';
import 'package:apexo/features/accounts/accounts_controller.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/utils/color_based_on_payment.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/features/appointments/open_appointment_panel.dart';
import 'package:apexo/common_widgets/item_title.dart';
import 'package:apexo/common_widgets/grid_gallery.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/settings/settings_stores.dart';
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
}

class AppointmentCard extends StatelessWidget {
  final Appointment appointment;
  final List<AppointmentSections> hide;
  final String? difference;
  final int number;
  final int photosClipCount;
  final bool readOnly;
  final bool showLeftBorder;
  final bool showSectionTitle;
  final Color openButtonColor;
  const AppointmentCard({
    super.key,
    required this.appointment,
    this.difference,
    this.readOnly = false,
    required this.number,
    this.hide = const [],
    this.photosClipCount = 2,
    this.showLeftBorder = true,
    this.showSectionTitle = true,
    this.openButtonColor = const Color(0xFF0078D4),
  });

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
                    if (appointment.archived == true)
                      const Icon(FluentIcons.archive)
                    else if (appointment.isMissed == true)
                      Icon(FluentIcons.event_date_missed12, color: color)
                    else if (!appointment.fullPaid)
                      Icon(FluentIcons.money, color: color),
                  ],
                ),
              if (readOnly == false) const SizedBox(width: 4),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                      borderRadius: const BorderRadius.all(Radius.circular(5)),
                      color: FluentTheme.of(context).micaBackgroundColor,
                      boxShadow: const [
                        BoxShadow(
                          offset: Offset(0.0, 8.0),
                          blurRadius: 17.0,
                          spreadRadius: 2.0,
                          color: Color.fromARGB(14, 0, 0, 0),
                        ),
                        BoxShadow(
                          offset: Offset(0.0, 5.0),
                          blurRadius: 22.0,
                          spreadRadius: 4.0,
                          color: Color(0x1F000000),
                        ),
                      ]),
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
                              context),
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
                              context),
                        ],
                        if (appointment.imgs.isNotEmpty &&
                            !hide.contains(AppointmentSections.photos)) ...[
                          const Divider(
                            direction: Axis.horizontal,
                          ),
                          _buildSection(
                              txt("photos"),
                              GridGallery(
                                canDelete: login.permissions[PInt.photos] == 1,
                                rowId: appointment.id,
                                imgs: appointment.imgs,
                                countPerLine: 4,
                                clipCount: photosClipCount,
                                rowWidth: 200,
                                size: 43,
                                progress: false,
                                drawings: appointment.drawings,
                                onSaveDrawing: (img, drawing) {
                                  appointment.drawings[img] = drawing;
                                  appointments.set(appointment);
                                },
                                onPressDelete: (img) async {
                                  try {
                                    await appointments.deleteImg(
                                      appointment.id,
                                      img,
                                    );
                                    appointment.drawings.remove(img);
                                    appointments
                                        .set(appointment..imgs.remove(img));
                                  } catch (e, s) {
                                    showErrorMessage(
                                        e, "deletingPatientImageFromServer");
                                    login.askForLoginAgain(e);
                                    logger(
                                        "Error during deleting image: $e", s);
                                  }
                                },
                                showDeleteMiniButton: false,
                              ),
                              FluentIcons.camera,
                              color,
                              context),
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
                              FluentIcons.quick_note,
                              color,
                              context),
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
                              FluentIcons.quick_note,
                              color,
                              context),
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
                                            iso: e.key))
                                        .toList()),
                              ),
                              FluentIcons.teeth,
                              color,
                              context),
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
                              context),
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
                              context),
                        ],
                        if ((appointment.price != 0 || appointment.paid != 0) &&
                            !hide.contains(AppointmentSections.pay)) ...[
                          const Divider(
                            direction: Axis.horizontal,
                          ),
                          _buildSection(
                              "${txt("pay")}\n${currency()}",
                              _paymentPills(context),
                              FluentIcons.money,
                              color,
                              context),
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
      onChanged: (checked) {
        appointment.isDone = checked == true;
        appointments.set(appointment);
      },
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

  Row _buildSection(
    String title,
    Widget child,
    IconData icon,
    Color color,
    context,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (showSectionTitle) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 7),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(icon, size: 16),
                const SizedBox(width: 7),
                Txt(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 5),
        ],
        Expanded(child: child),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
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
        IconButton(
          icon: const Icon(FluentIcons.go, size: 17, color: Colors.white),
          onPressed: () => openAppointment(appointment),
          iconButtonMode: IconButtonMode.large,
          style: ButtonStyle(
            backgroundColor: WidgetStatePropertyAll(openButtonColor),
          ),
        )
      ],
    );
  }

  Text _buildFormattedDate(Color color) {
    return Txt(
      DF.full(appointment.date),
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
      border: Border(
        left: BorderSide(
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
      decoration: BoxDecoration(
          color: color?.withAlpha(40), borderRadius: BorderRadius.circular(5)),
      padding: const EdgeInsets.fromLTRB(10, 5, 10, 0),
      height: 35,
      child: Wrap(
        spacing: 10,
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

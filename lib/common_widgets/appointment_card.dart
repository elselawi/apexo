import 'dart:math';

import 'package:apexo/utils/color_based_on_payment.dart';
import 'package:apexo/utils/colors_without_yellow.dart';
import 'package:apexo/utils/get_deterministic_item.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/features/appointments/open_appointment_panel.dart';
import 'package:apexo/features/patients/open_patient_panel.dart';
import 'package:apexo/common_widgets/item_title.dart';
import 'package:apexo/common_widgets/grid_gallery.dart';
import 'package:apexo/features/doctors/open_doctor_panel.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart' as intl;

enum AppointmentSections {
  patient,
  doctors,
  photos,
  preNotes,
  postNotes,
  dentalNotes,
  prescriptions,
  pay
}

class AppointmentCard extends StatelessWidget {
  final Appointment appointment;
  final List<AppointmentSections> hide;
  final String? difference;
  final int number;
  const AppointmentCard(
      {super.key,
      required this.appointment,
      this.difference,
      required this.number,
      this.hide = const []});

  @override
  Widget build(BuildContext context) {
    final color = appointment.archived == true
        ? (FluentTheme.of(context).iconTheme.color ?? Colors.grey)
        : (appointment.isMissed)
            ? Colors.red
            : getDeterministicItem(colorsWithoutYellow, appointment.id).light;

    return Padding(
      padding: const EdgeInsets.fromLTRB(7, 15, 15, 0),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                key: WK.acSideIcons,
                children: [
                  _doneCheckBox(color),
                  if (appointment.archived == true) ...[
                    _verticalSpacing(10),
                    const Icon(FluentIcons.archive),
                  ] else if (appointment.isMissed == true) ...[
                    _verticalSpacing(10),
                    Icon(FluentIcons.event_date_missed12, color: color),
                  ] else if (!appointment.fullPaid) ...[
                    _verticalSpacing(10),
                    Icon(FluentIcons.money, color: color),
                  ],
                ],
              ),
              _horizontalSpacing(4),
              Expanded(
                child: Acrylic(
                  elevation: 100,
                  blurAmount: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(5)),
                  child: Container(
                    decoration: _coloredHandleDecoration(color),
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      children: [
                        _buildHeader(context, color),
                        if (appointment.patient != null &&
                            !hide.contains(AppointmentSections.patient)) ...[
                          ..._betweenSections,
                          _buildSection(
                            txt("patient"),
                            GestureDetector(
                                onTap: () {
                                  openPatient(appointment.patient);
                                },
                                child: ItemTitle(item: appointment.patient!)),
                            FluentIcons.medical,
                            color,
                          ),
                        ],
                        if (appointment.operators.isNotEmpty &&
                            !hide.contains(AppointmentSections.doctors)) ...[
                          ..._betweenSections,
                          _buildSection(
                            txt("doctors"),
                            Column(
                              children: appointment.operators
                                  .map((e) => GestureDetector(
                                      onTap: () {
                                        openDoctor(e);
                                      },
                                      child: ItemTitle(item: e, maxWidth: 115)))
                                  .toList(),
                            ),
                            FluentIcons.medical,
                            color,
                          ),
                        ],
                        if (appointment.imgs.isNotEmpty &&
                            !hide.contains(AppointmentSections.photos)) ...[
                          ..._betweenSections,
                          _buildSection(
                            txt("photos"),
                            GridGallery(
                              rowId: appointment.id,
                              imgs: appointment.imgs,
                              countPerLine: 4,
                              clipCount: 4,
                              rowWidth: 200,
                              size: 43,
                              progress: false,
                            ),
                            FluentIcons.camera,
                            color,
                          ),
                        ],
                        if (appointment.preOpNotes.isNotEmpty &&
                            !hide.contains(AppointmentSections.preNotes)) ...[
                          ..._betweenSections,
                          _buildSection(
                            txt("pre-opNotes"),
                            Txt(
                              appointment.preOpNotes,
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w500),
                            ),
                            FluentIcons.quick_note,
                            color,
                          ),
                        ],
                        if (appointment.postOpNotes.isNotEmpty &&
                            !hide.contains(AppointmentSections.postNotes)) ...[
                          ..._betweenSections,
                          _buildSection(
                            txt("post-opNotes"),
                            Txt(
                              appointment.postOpNotes,
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w500),
                            ),
                            FluentIcons.quick_note,
                            color,
                          ),
                        ],
                        if (appointment.teeth.isNotEmpty &&
                            !hide
                                .contains(AppointmentSections.dentalNotes)) ...[
                          ..._betweenSections,
                          _buildSection(
                            txt("dentalNotes"),
                            Wrap(
                              spacing: 5,
                              children: appointment.teeth.keys
                                  .map((iso) => toothHasNotes(color, iso, appointment.teeth[iso]!))
                                  .toList(),
                            ),
                            FluentIcons.teeth,
                            color,
                          ),
                        ],
                        if (appointment.prescriptions.isNotEmpty &&
                            !hide.contains(
                                AppointmentSections.prescriptions)) ...[
                          ..._betweenSections,
                          _buildSection(
                            txt("prescription"),
                            Txt(
                              appointment.prescriptions.join("\n"),
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w500),
                            ),
                            FluentIcons.pill,
                            color,
                          ),
                        ],
                        if ((appointment.price != 0 || appointment.paid != 0) &&
                            !hide.contains(AppointmentSections.pay)) ...[
                          ..._betweenSections,
                          _buildSection(
                            "${txt("pay")}\n${globalSettings.get("currency_______").value}",
                            _paymentPills(context),
                            FluentIcons.money,
                            color,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          _verticalSpacing(),
          if (difference != null) _buildTimeDifference()
        ],
      ),
    );
  }

  Widget toothHasNotes(Color color, String iso, String note) {
    final borderSide = BorderSide(color: color, width: 2);
    final int isoInt = int.parse(iso);
    String arch = iso[0];
    String tooth = iso[1];

    if (isoInt > 48) {
      if (tooth == "1") tooth = "A";
      if (tooth == "2") tooth = "B";
      if (tooth == "3") tooth = "C";
      if (tooth == "4") tooth = "D";
      if (tooth == "5") tooth = "E";
    }

    if (arch == "5") arch = "1";
    if (arch == "6") arch = "2";
    if (arch == "7") arch = "3";
    if (arch == "8") arch = "4";

    final bool upper = arch == "1" || arch == "2";
    final bool left = arch == "2" || arch == "3";

    return Tooltip(
      enableFeedback: true,
      triggerMode: TooltipTriggerMode.tap,
      message: note,
      child: Container(
        decoration: BoxDecoration(
          color: color.withAlpha(10),
          border: Border(
            bottom: upper ? borderSide : BorderSide.none,
            top: upper == false ? borderSide : BorderSide.none,
            left: left ? borderSide : BorderSide.none,
            right: left == false ? borderSide : BorderSide.none,
          ),
        ),
        width: 20,
        height: 20,
        padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 0),
        child: Text(
          tooth,
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Padding _doneCheckBox(Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Checkbox(
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
      ),
    );
  }

  Center _buildTimeDifference() {
    return Center(
        child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      textDirection: TextDirection.ltr,
      children: [
        _spacerIcon(1),
        _horizontalSpacing(),
        TimeDifference(difference: difference),
        _horizontalSpacing(),
        _spacerIcon(-1),
      ],
    ));
  }

  Column _paymentPills(BuildContext context) {
    final color = colorBasedOnPayments(appointment.paid, appointment.price);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _paymentPill(txt("price"), appointment.price.toString(), context,
                null, color),
            _horizontalSpacing(),
            _paymentPill(
                txt("paid"), appointment.paid.toString(), context, null, color),
          ],
        ),
        _verticalSpacing(),
        if (appointment.paid != appointment.price)
          _paymentPill(
            appointment.overPaid ? txt("overpaid") : txt("underpaid"),
            appointment.paymentDifference.toString(),
            context,
            colorBasedOnPayments(appointment.paid, appointment.price),
          )
      ],
    );
  }

  PaymentPill _paymentPill(String title, String amount, BuildContext context,
      [Color? color, Color? textColor]) {
    final Color finalTextColor = textColor ??
        (color == null
            ? (FluentTheme.of(context).iconTheme.color ?? Colors.grey)
            : Colors.white);
    return PaymentPill(
        finalTextColor: finalTextColor,
        amount: amount,
        title: title,
        color: color);
  }

  List<Widget> get _betweenSections {
    return [_verticalSpacing(), _divider(), _verticalSpacing()];
  }

  Divider _divider() => const Divider(size: 300);

  Transform _spacerIcon([flip = 1]) {
    return Transform.flip(
      flipX: flip == 1 ? true : false,
      flipY: false,
      child: Transform.translate(
        offset: Offset(0, flip < 1 ? 2.0 * flip : 5.0 * flip),
        child: Transform.rotate(
          angle: (pi / (flip == 1 ? 2 : 1)) * flip,
          child: Icon(
            color: Colors.grey.withValues(alpha: 0.3),
            FluentIcons.turn_right,
            size: 14,
          ),
        ),
      ),
    );
  }

  Row _buildSection(String title, Widget child, IconData icon, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(
                icon,
                size: 13,
                color: color.withValues(alpha: 0.5),
              ),
            ),
            Acrylic(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(50)),
              elevation: 100,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                child: Txt(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
          ],
        ),
        _horizontalSpacing(),
        Expanded(child: child),
      ],
    );
  }

  SizedBox _horizontalSpacing([double n = 5]) => SizedBox(width: n);

  SizedBox _verticalSpacing([double n = 10.0]) => SizedBox(height: n);

  Widget _buildHeader(BuildContext context, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Txt(
              "${txt("appointment")}: $number",
              style: TextStyle(
                fontSize: 10,
                color: color.withValues(alpha: 0.5),
                fontWeight: FontWeight.bold,
              ),
            ),
            _verticalSpacing(3),
            Row(
              children: [
                Icon(FluentIcons.clock, color: color),
                _horizontalSpacing(),
                _buildFormattedDate(color),
              ],
            ),
          ],
        ),
        IconButton(
          icon: const Icon(FluentIcons.edit, size: 17),
          onPressed: () {
            openAppointment(appointment);
          },
          iconButtonMode: IconButtonMode.large,
        )
      ],
    );
  }

  Text _buildFormattedDate(Color color) {
    final df =
        localSettings.dateFormat.startsWith("d") == true ? "d/MM" : "MM/d";
    return Txt(
      intl.DateFormat("E $df yyyy - hh:mm a", locale.s.$code)
          .format(appointment.date),
      style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold),
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
    return Acrylic(
      luminosityAlpha: 1,
      tintAlpha: 1,
      blurAmount: 100,
      elevation: 20,
      tint: color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(5),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 5, 10, 0),
        child: Wrap(
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
            const SizedBox(width: 5),
            const Divider(direction: Axis.vertical, size: 10),
            const SizedBox(width: 5),
            Txt(
              amount,
              style: TextStyle(color: finalTextColor, fontSize: 12),
            ),
          ],
        ),
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
          color: Colors.grey.withValues(alpha: 0.5),
          fontWeight: FontWeight.bold),
    );
  }
}

import 'package:apexo/app/routes.dart';
import 'package:apexo/common_widgets/appointments_list_footer.dart';
import 'package:apexo/common_widgets/teeth_selector/teeth_selector.dart';
import 'package:apexo/common_widgets/teeth_selector/tx_options.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/services/archived.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/utils/color_based_on_payment.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/utils/constants.dart';
import 'package:apexo/utils/iso_to_textual.dart';
import 'package:apexo/utils/print/print_link.dart';
import 'package:apexo/common_widgets/appointment_card.dart';
import 'package:apexo/common_widgets/call_button.dart';
import 'package:apexo/common_widgets/qrlink.dart';
import 'package:apexo/common_widgets/tag_input.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart' hide TextBox;
import 'package:flutter/cupertino.dart';

Future<Patient> openPatient([Patient? patient]) {
  final editingCopy = Patient.fromJson(patient?.toJson() ?? {});
  final panel = Panel<Patient>(
    item: editingCopy,
    store: patients,
    icon: FluentIcons.medication_admin,
    title: patients.get(editingCopy.id) == null
        ? txt("newPatient")
        : editingCopy.title,
    tabs: [
      PanelTab(
        title: txt("patientDetails"),
        icon: FluentIcons.medication_admin,
        body: _PatientDetails(editingCopy),
      ),
      PanelTab(
        title: txt("dentalNotes"),
        icon: FluentIcons.teeth,
        body: MStreamBuilder(
            streams: [appointments.observableMap.stream, showArchived.stream],
            builder: (context, asyncSnapshot) {
              return InfoLabel(
                label: "${txt("dentalNotes")}:",
                child: Container(
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: Colors.grey.withAlpha(100))),
                  padding: const EdgeInsets.all(4),
                  child: TeethSelector(
                    type: StateType.state,
                    onNote: (x, y) {
                      if (y != null) {
                        editingCopy.teeth[x] = y;
                      } else {
                        editingCopy.teeth.remove(x);
                      }
                    },
                    notation: (isoString) => isoToTextualNotation(isoString),
                    rightString: txt("right"),
                    leftString: txt("left"),
                    currentNotes: editingCopy.teeth,
                    oldNotes: editingCopy.allAppointmentsDentalNotes
                      ..removeWhere((k, v) => editingCopy.teeth.containsKey(k)),
                    showPrimary: editingCopy.age < 14,
                  ),
                ),
              );
            }),
      ),
      if (login.permissions[PInt.appointments] > 0)
        PanelTab(
          title: txt("appointments"),
          icon: FluentIcons.calendar,
          body: _PatientAppointments(editingCopy),
          footer: AppointmentsListFooter(forPatientID: editingCopy.id),
          onlyIfSaved: true,
          padding: 0,
        ),
      PanelTab(
        title: txt("patientPage"),
        icon: FluentIcons.q_r_code,
        body: _PatientQrPage(editingCopy: editingCopy),
        onlyIfSaved: true,
      ),
    ],
  );
  routes.openPanel(panel);
  return panel.result.future;
}

class _PatientQrPage extends StatefulWidget {
  const _PatientQrPage({
    required this.editingCopy,
  });

  final Patient editingCopy;

  @override
  State<_PatientQrPage> createState() => _PatientQrPageState();
}

class _PatientQrPageState extends State<_PatientQrPage> {
  String language = locale.list[localSettings.selectedLocale].$code;
  String qrType = "telegram";

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            ComboBox(
              items: List.generate(
                  locale.list.length,
                  (i) => ComboBoxItem(
                      value: locale.list[i].$code,
                      child: Txt(locale.list[i].$name))),
              value: language,
              onChanged: (v) => setState(() => language = v!),
            ),
            const SizedBox(width: 10),
            ComboBox(
              items: [
                ComboBoxItem(value: "web", child: Txt(txt("web"))),
                ComboBoxItem(value: "telegram", child: Txt(txt("telegram"))),
              ],
              value: qrType,
              onChanged: (v) => setState(() => qrType = v!),
            )
          ],
        ),
        const SizedBox(height: 10),
        _PatientWebPage(widget.editingCopy, language, qrType),
        _PrintQRButton(widget.editingCopy, language, qrType)
      ],
    );
  }
}

class _PrintQRButton extends StatelessWidget {
  final Patient patient;
  final String language;
  final String qrType;
  const _PrintQRButton(this.patient, this.language, this.qrType);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FilledButton(
              child: Row(
                children: [
                  const Icon(FluentIcons.print),
                  const SizedBox(width: 5),
                  Txt(txt("printQR"))
                ],
              ),
              onPressed: () {
                printingQRCode(
                  context,
                  qrType == "web"
                      ? patient.webPageLink(language)
                      : patient.telegramLink(language),
                  "Access your information",
                  "Scan to visit link:\n${qrType == "web" ? patient.webPageLink(language) : patient.telegramLink(language)}\nto access your appointments, payments and photos.",
                );
              }),
        ],
      ),
    );
  }
}

class _PatientWebPage extends StatelessWidget {
  final Patient patient;
  final String language;
  final String qrType;
  const _PatientWebPage(this.patient, this.language, this.qrType);

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      InfoBar(
        title: Txt(txt("patientCanUseTheFollowing")),
      ),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(5),
        ),
        child: SelectableText(qrType == "web"
            ? patient.webPageLink(language)
            : patient.telegramLink(language)),
      ),
      QRLink(
          link: qrType == "web"
              ? patient.webPageLink(language)
              : patient.telegramLink(language)),
    ]);
  }
}

class _PatientAppointments extends StatelessWidget {
  final Patient patient;
  const _PatientAppointments(this.patient);
  @override
  Widget build(BuildContext context) {
    return MStreamBuilder(
        streams: [appointments.observableMap.stream, showArchived.stream],
        builder: (context, snapshot) {
          return Column(
            children: patient.allAppointments.isEmpty
                ? [
                    InfoBar(title: Txt(txt("noAppointmentsFound"))),
                  ]
                : [
                    ...List.generate(patient.allAppointments.length, (index) {
                      final appointment = patient.allAppointments[index];
                      String? difference;
                      if (patient.allAppointments.last != appointment) {
                        int differenceInDays = appointment.date
                            .difference(patient.allAppointments[index + 1].date)
                            .inDays
                            .abs();

                        difference =
                            "${txt("after")} $differenceInDays ${txt("day${(differenceInDays > 1) ? "s" : ""}")}";
                      }
                      return AppointmentCard(
                        key: Key(appointment.id),
                        appointment: appointment,
                        difference: difference,
                        hide: const [AppointmentSections.patient],
                        number: index + 1,
                      );
                    }),
                    const Divider(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 10, 12, 50),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(5),
                          boxShadow: [
                            BoxShadow(
                              offset: const Offset(0.0, 6.0),
                              blurRadius: 30.0,
                              spreadRadius: 5.0,
                              color: Colors.grey.withAlpha(50),
                            )
                          ],
                          border: Border(
                              top: BorderSide(
                            color: (colorBasedOnPayments(patient.paymentsMade,
                                        patient.pricesGiven) ??
                                    FluentTheme.of(context).cardColor)
                                .withValues(alpha: 0.3),
                            width: 5,
                          )),
                        ),
                        child: Column(
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 5),
                              child: Txt(
                                  "${txt("paymentSummary")} (${globalSettings.get("currency_______").value})",
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey)),
                            ),
                            const SizedBox(height: 10),
                            const Divider(),
                            const SizedBox(height: 15),
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                PaymentPill(
                                  finalTextColor: Colors.grey,
                                  title: txt("cost"),
                                  amount: patient.pricesGiven.toString(),
                                  color: Colors.white,
                                ),
                                PaymentPill(
                                  finalTextColor: Colors.grey,
                                  title: txt("paid"),
                                  amount: patient.paymentsMade.toString(),
                                  color: Colors.white,
                                ),
                                PaymentPill(
                                  finalTextColor: Colors.grey,
                                  title: patient.overPaid
                                      ? txt("overpaid")
                                      : patient.underPaid
                                          ? txt("underpaid")
                                          : txt("fullyPaid"),
                                  amount: (patient.paymentsMade -
                                          patient.pricesGiven)
                                      .abs()
                                      .toString(),
                                )
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
          );
        });
  }
}

class _PatientDetails extends StatefulWidget {
  final Patient patient;
  const _PatientDetails(this.patient);

  @override
  State<_PatientDetails> createState() => _PatientDetailsState();
}

class _PatientDetailsState extends State<_PatientDetails> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InfoLabel(
          label: "${txt("name")}:",
          isHeader: true,
          child: CupertinoTextField(
            key: WK.fieldPatientName,
            placeholder: "${txt("name")}...",
            controller: TextEditingController(text: widget.patient.title),
            onChanged: (value) => widget.patient.title = value,
          ),
        ),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Expanded(
            child: InfoLabel(
              label: "${txt("birthYear")}:",
              isHeader: true,
              child: CupertinoTextField(
                key: WK.fieldPatientYOB,
                placeholder: "${txt("birthYear")}...",
                controller: TextEditingController(
                    text: widget.patient.birth.toString()),
                onChanged: (value) => widget.patient.birth =
                    int.tryParse(value) ?? widget.patient.birth,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: InfoLabel(
              label: "${txt("gender")}:",
              isHeader: true,
              child: ComboBox<int>(
                key: WK.fieldPatientGender,
                isExpanded: true,
                items: [
                  ComboBoxItem<int>(
                    value: 1,
                    child: Txt("♂️ ${txt("male")}"),
                  ),
                  ComboBoxItem<int>(
                    value: 0,
                    child: Txt("♀️ ${txt("female")}"),
                  )
                ],
                value: widget.patient.gender,
                onChanged: (value) {
                  setState(() {
                    widget.patient.gender = value ?? widget.patient.gender;
                  });
                },
              ),
            ),
          ),
        ]),
        Row(children: [
          Expanded(
            child: InfoLabel(
              label: "${txt("phone")}:",
              isHeader: true,
              child: CupertinoTextField(
                key: WK.fieldPatientPhone,
                placeholder: "${txt("phone")}...",
                controller: TextEditingController(text: widget.patient.phone),
                onChanged: (value) => widget.patient.phone = value,
                prefix: CallIconButton(phoneNumber: widget.patient.phone),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: InfoLabel(
              label: "${txt("email")}:",
              isHeader: true,
              child: CupertinoTextField(
                key: WK.fieldPatientEmail,
                placeholder: "${txt("email")}...",
                controller: TextEditingController(text: widget.patient.email),
                onChanged: (value) => widget.patient.email = value,
              ),
            ),
          ),
        ]),
        InfoLabel(
          label: "${txt("address")}:",
          isHeader: true,
          child: CupertinoTextField(
            key: WK.fieldPatientAddress,
            controller: TextEditingController(text: widget.patient.address),
            onChanged: (value) => widget.patient.address = value,
            placeholder: "${txt("address")}...",
          ),
        ),
        InfoLabel(
          label: "${txt("notes")}:",
          isHeader: true,
          child: CupertinoTextField(
            key: WK.fieldPatientNotes,
            controller: TextEditingController(text: widget.patient.notes),
            onChanged: (value) => widget.patient.notes = value,
            maxLines: null,
            placeholder: "${txt("notes")}...",
          ),
        ),
        InfoLabel(
          label: "${txt("patientTags")}:",
          isHeader: true,
          child: TagInputWidget(
            key: WK.fieldPatientTags,
            suggestions: patients.allTags
                .map((t) => TagInputItem(value: t, label: t))
                .toList(),
            onChanged: (tags) {
              widget.patient.tags = List<String>.from(
                  tags.map((e) => e.value).where((e) => e != null));
            },
            initialValue: widget.patient.tags
                .map((e) => TagInputItem(value: e, label: e))
                .toList(),
            strict: false,
            limit: 9999,
            placeholder: "${txt("patientTags")}...",
          ),
        )
      ].map((e) => [e, const SizedBox(height: 10)]).expand((e) => e).toList(),
    );
  }
}

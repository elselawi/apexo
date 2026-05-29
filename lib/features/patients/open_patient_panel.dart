import 'package:apexo/app/routes.dart';
import 'package:apexo/common_widgets/appointments_list_footer.dart';
import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/contact_buttons.dart';
import 'package:apexo/common_widgets/error_dialog.dart';
import 'package:apexo/common_widgets/teeth_selector/teeth_selector.dart';
import 'package:apexo/common_widgets/teeth_selector/tx_options.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/services/archived.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/utils/color_based_on_payment.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/utils/constants.dart';
import 'package:apexo/utils/iso_to_textual.dart';
import 'package:apexo/utils/logger.dart';
import 'package:apexo/utils/parsed_phone_number.dart';
import 'package:apexo/utils/phone_numbers_extractor.dart';
import 'package:apexo/utils/print/print_link.dart';
import 'package:apexo/common_widgets/appointment_card.dart';
import 'package:apexo/common_widgets/qrlink.dart';
import 'package:apexo/common_widgets/tag_input.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart' hide TextBox;
import 'package:flutter/cupertino.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart';

Future<Patient> openPatient([Patient? patient, int? selectedTabIndex]) {
  final editingCopy = Patient.fromJson(patient?.toJson() ?? {});
  final panel = Panel<Patient>(
    singularName: "patient",
    unicodeSymbol: "👤",
    selectedTabIndex: selectedTabIndex,
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
          icon: WindowsIcons.calendar,
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
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 25),
        Center(
          child: FilledButton(
            child: ButtonContent(FluentIcons.q_r_code, txt("generateQRLink")),
            onPressed: () async {
              final pID = widget.editingCopy.id;
              final p = patients.get(pID);
              if (p == null) {
                return;
              } else {
                try {
                  p.link = await p.generatePatientLink();
                } catch (e, stacktrace) {
                  showErrorMessage(e, "generatingPatientLink");
                  login.askForLoginAgain(e);
                  logger("error while generating patient link $e", stacktrace);
                }
                patients.set(p);
                widget.editingCopy.link = p.link;
              }
              setState(() {});
            },
          ),
        ),
        if (widget.editingCopy.shortLink.isNotEmpty) ...[
          const SizedBox(height: 10),
          _PatientWebPage(widget.editingCopy),
          _PrintQRButton(widget.editingCopy)
        ]
      ],
    );
  }
}

class _PrintQRButton extends StatelessWidget {
  final Patient patient;
  const _PrintQRButton(this.patient);

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
                  patient.shortLink,
                  "Access your information",
                  "Scan to visit link:\n${patient.shortLink}\nto access your appointments, payments and photos.",
                );
              }),
        ],
      ),
    );
  }
}

class _PatientWebPage extends StatelessWidget {
  final Patient patient;
  const _PatientWebPage(this.patient);

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
        child: SelectableText(patient.shortLink),
      ),
      QRLink(link: patient.shortLink),
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
          final apts = patient.allAppointments;
          return Column(
            children: apts.isEmpty
                ? [
                    InfoBar(title: Txt(txt("noAppointmentsFound"))),
                  ]
                : [
                    ...List.generate(apts.length, (index) {
                      final appointment = apts[index];
                      String? difference;
                      if (apts.last != appointment) {
                        int differenceInDays = appointment.date
                            .difference(apts[index + 1].date)
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
                                  "${txt("paymentSummary")} (${currency()})",
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
                                  amount:
                                      patient.pricesGiven.toStringAsFixed(2),
                                  color: Colors.white,
                                ),
                                PaymentPill(
                                  finalTextColor: Colors.grey,
                                  title: txt("paid"),
                                  amount:
                                      patient.paymentsMade.toStringAsFixed(2),
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
                                      .toStringAsFixed(2),
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
  final phoneTextController = PhoneTextEditingController();
  final emailTextController = TextEditingController();
  final phoneFlyoutController = FlyoutController();
  final nameController = TextEditingController();
  final yobController = TextEditingController();
  final addressController = TextEditingController();
  final notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    phoneTextController.text = widget.patient.phonesString;
    emailTextController.text = widget.patient.email;
    nameController.text = widget.patient.title;
    yobController.text = widget.patient.birth.toString();
    addressController.text = widget.patient.address;
    notesController.text = widget.patient.notes;
  }

  @override
  void dispose() {
    phoneTextController.dispose();
    emailTextController.dispose();
    phoneFlyoutController.dispose();
    nameController.dispose();
    yobController.dispose();
    addressController.dispose();
    notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    phoneTextController.accentColor = FluentTheme.of(context).accentColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InfoLabel(
          label: "${txt("name")}:",
          isHeader: true,
          child: CupertinoTextField(
            key: WK.fieldPatientName,
            placeholder: "${txt("name")}...",
            controller: nameController,
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
                controller: yobController,
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
        InfoLabel(
          label: "${txt("email")}:",
          isHeader: true,
          child: CupertinoTextField(
            textDirection: TextDirection.ltr,
            key: WK.fieldPatientEmail,
            placeholder: "${txt("email")}...",
            controller: emailTextController,
            onChanged: (value) {
              setState(() {
                widget.patient.email = value;
              });
            },
            suffix: widget.patient.email.isNotEmpty
                ? EmailButton(email: widget.patient.email)
                : null,
          ),
        ),
        InfoLabel(
          label: "${txt("phone")}:",
          isHeader: true,
          child: CupertinoTextField(
            suffix: phoneTextController.text.isNotEmpty &&
                    widget.patient.phone.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(5),
                    child: Icon(
                      WindowsIcons.warning,
                      color: Colors.warningPrimaryColor,
                    ),
                  )
                : null,
            textDirection: TextDirection.ltr,
            key: WK.fieldPatientPhone,
            placeholder: "${txt("phone")}...",
            controller: phoneTextController,
            onChanged: (value) {
              setState(() {
                widget.patient.phone = PhoneNumberExtractor.extract(value)
                    .map((s) => ParsedPhoneNumber(s))
                    .toList();
              });
            },
          ),
        ),
        if (phoneTextController.text.isNotEmpty && widget.patient.phone.isEmpty)
          Txt(txt("noValidNumbersFound")),
        if (widget.patient.phone.isNotEmpty)
          Text("${txt("theFollowingPhoneNumbersAreDetected")}:"),
        ...widget.patient.phone.map((p) => PhoneNumberButton(
              onlyIcon: false,
              phoneNumbers: [p],
            )),
        const SizedBox(height: 10),
        InfoLabel(
          label: "${txt("address")}:",
          isHeader: true,
          child: CupertinoTextField(
            key: WK.fieldPatientAddress,
            controller: addressController,
            onChanged: (value) => widget.patient.address = value,
            placeholder: "${txt("address")}...",
          ),
        ),
        InfoLabel(
          label: "${txt("notes")}:",
          isHeader: true,
          child: CupertinoTextField(
            key: WK.fieldPatientNotes,
            controller: notesController,
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

class PhoneTextEditingController extends TextEditingController {
  Color? accentColor;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final List<TextSpan> children = [];
    final List<String> parts = text.split(' ');

    for (int i = 0; i < parts.length; i++) {
      final String part = parts[i];
      if (PhoneNumber.parse(part,
              destinationCountry:
                  IsoCode.values.byName(globalSettings.isoCountryCode))
          .isValid()) {
        children.add(
          TextSpan(
            text: part,
            style: style?.copyWith(
              decoration: TextDecoration.underline,
              decorationColor: accentColor,
              decorationThickness: 2,
            ),
          ),
        );
      } else {
        children.add(
          TextSpan(
            text: part,
            style: style?.copyWith(
              decoration: TextDecoration.underline,
              decorationColor: Colors.red,
              decorationThickness: 2,
            ),
          ),
        );
      }
      if (i < parts.length - 1) {
        children.add(TextSpan(text: ' ', style: style));
      }
    }

    return TextSpan(children: children, style: style);
  }
}

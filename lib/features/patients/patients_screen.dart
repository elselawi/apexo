import 'dart:math';

import 'package:apexo/app/routes.dart';
import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/contact_buttons.dart';
import 'package:apexo/common_widgets/dialogs/close_dialog_button.dart';
import 'package:apexo/common_widgets/dialogs/export_patients_dialog.dart';
import 'package:apexo/common_widgets/item_title.dart';
import 'package:apexo/common_widgets/money_display.dart';
import 'package:apexo/common_widgets/teeth_selector/tx_options.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/patients/open_patient_panel.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/services/archived.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/common_widgets/archive_toggle.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/utils/flyout_focus_fix.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/cupertino.dart';

final treatments = txOptions.where((x) => x.type != StateType.state).toList();

class PatientsScreen extends StatelessWidget {
  const PatientsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      key: WK.patientsScreen,
      padding: EdgeInsets.zero,
      content: MStreamBuilder(
          streams: [
            patients.observableMap.stream,
            appointments.observableMap.stream,
            showArchived.stream,
            routes.panels.stream
          ],
          builder: (context, snapshot) {
            // ignore: prefer_const_constructors
            return _PatientsPage();
          }),
    );
  }
}

class _PatientsPage extends StatefulWidget {
  const _PatientsPage();

  @override
  State<_PatientsPage> createState() => _PatientsPageState();
}

class _PatientsPageState extends State<_PatientsPage> {
  List<String> selected = [];
  String? byTreatment;
  int sortBy = -1;
  int sortDirection = 1;
  int slice = 10;

  double calSpacing(double x) => (((3 / 205) * x) - (87 / 41)).clamp(5.0, 15.0);
  double calWidth(double x) => ((2 / 41) * x + (2580 / 41)).clamp(100, 130.0);

  List<String>? _labels;
  List<String> get labels {
    return _labels ??= patients.present.values.fold(
        <String>{},
        (labels, item) => labels
          ..addAll((item.tableLabels
              .where((x) => x.sortable)
              .map((x) => x.title)
              .toList()))).toList()
      ..sort((a, b) => a.compareTo(b));
  }

  List<Patient> get filteredItems {
    final searchString = searchController.text;

    final words =
        searchString.toLowerCase().replaceAll(RegExp("أ|إ"), "ا").split(" ");
    final List<Patient> candidates = [];
    for (var item in patients.present.values) {
      final searchIn = (item.title +
              item.tableLabels.map((x) => x.searchableString).join(" "))
          .toLowerCase()
          .replaceAll(RegExp("أ|إ"), "ا");
      final bool allTermsFound = words
              .map((word) => searchIn.contains(word))
              .where((x) => x == true)
              .length ==
          words.length;
      if (allTermsFound) candidates.add(item);
    }

    if (byTreatment != null) {
      return candidates.where((patient) {
        if (byTreatment != "bridge") {
          return patient.allPredefinedTreatments.contains(byTreatment);
        } else {
          return patient.allPredefinedTreatments.contains("abutment") ||
              patient.allPredefinedTreatments.contains("pontic") ||
              patient.allPredefinedTreatments.contains("bridge");
        }
      }).toList();
    }

    return candidates;
  }

  List<Patient> get sortedItems {
    List<Patient> result = List<Patient>.from(filteredItems);
    if (sortBy < 0) {
      result.sort((a, b) {
        return a.title.toLowerCase().compareTo(b.title.toLowerCase()) *
            sortDirection;
      });
    } else {
      final sorted = List<_SortableItem>.from(result.map((e) {
        final label = e.tableLabels
            .where((element) => element.title == labels[sortBy])
            .firstOrNull;
        final double value = label?.value ?? double.negativeInfinity;
        return _SortableItem(value, e);
      }))
        ..sort((a, b) {
          return a.value.compareTo(b.value) * sortDirection;
        });
      result = sorted.map((e) => e.item).toList();
    }

    return result.sublist(0, min(result.length, slice));
  }

  TextEditingController searchController = TextEditingController();
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCommandBar(),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              _buildSearch(),
            ],
          ),
        ),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
              border: BorderDirectional(
                  bottom:
                      BorderSide(color: Colors.grey.withValues(alpha: 0.1))),
              gradient: LinearGradient(colors: [
                Colors.blue.withAlpha(50),
                FluentTheme.of(context).activeColor.withAlpha(20),
              ])),
          padding: const EdgeInsetsDirectional.only(
            start: 8.0,
            end: 0,
            top: 8.0,
            bottom: 8.0,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsetsDirectional.only(end: 8.0),
            scrollDirection: Axis.horizontal,
            physics: const AlwaysScrollableScrollPhysics(),
            child: Row(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.center,
              spacing: 5,
              children: [
                _buildTxFilter(),
                _buildsortByTitle(),
                ..._buildSortByLabels()
              ],
            ),
          ),
        ),
        _buildTable(),
        _buildShowMore(context),
        const SizedBox(height: 5)
      ],
    );
  }

  Expanded _buildTable() {
    return Expanded(
      child: LayoutBuilder(builder: (context, constraints) {
        final searchStringLowerCased = searchController.text.toLowerCase();
        return ListView.builder(
            controller: _scrollController,
            itemCount: sortedItems.length,
            padding: const EdgeInsets.all(0),
            itemBuilder: (context, index) {
              final patient = sortedItems[index];
              final calculatedWidth = calWidth(constraints.maxWidth);
              final calculatedSpacing = calSpacing(constraints.maxWidth);
              return _buildRow(
                patient,
                context,
                constraints,
                calculatedSpacing,
                calculatedWidth,
                searchStringLowerCased,
              );
            });
      }),
    );
  }

  ListTile _buildRow(
    Patient patient,
    BuildContext context,
    BoxConstraints constraints,
    double calculatedSpacing,
    double calculatedWidth,
    String searchStringLowerCased,
  ) {
    return ListTile.selectable(
      key: ValueKey(patient.id),
      selected: selected.contains(patient.id),
      selectionMode: ListTileSelectionMode.multiple,
      onSelectionChange: (isSelected) {
        if (isSelected) {
          selected.add(patient.id);
        } else {
          selected.remove(patient.id);
        }
        setState(() {});
      },
      margin: const EdgeInsets.all(0),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(0),
          side: BorderSide(
              width: .3,
              color: (selected.contains(patient.id)
                      ? Colors.blue
                      : Colors.transparent)
                  .withValues(alpha: .2))),
      tileColor: WidgetStateColor.resolveWith((states) {
        if (states.contains(WidgetState.hovered)) {
          return Colors.blue.withAlpha(20);
        } else if (selected.contains(patient.id)) {
          return Colors.blue.withAlpha(20);
        }
        return FluentTheme.of(context).cardColor;
      }),
      title: buildSinglePatientTile(
        patient,
        constraints,
        calculatedSpacing,
        calculatedWidth,
        searchStringLowerCased,
      ),
      contentPadding: EdgeInsetsDirectional.zero,
      trailing: _buildTrailingButtons(patient),
    );
  }

  GestureDetector buildSinglePatientTile(
      Patient patient,
      BoxConstraints constraints,
      double calculatedSpacing,
      double calculatedWidth,
      String searchStringLowerCased) {
    return GestureDetector(
      onTap: () {
        openPatient(patient);
      },
      child: Row(
        spacing: 5,
        children: [
          const Divider(size: 65, direction: Axis.vertical),
          Column(
            spacing: 5,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ItemTitle(item: patient),
                  _buildTreatmentLabels(constraints, patient)
                ],
              ),
              _buildBottomLabels(
                constraints,
                calculatedSpacing,
                patient,
                calculatedWidth,
                searchStringLowerCased,
              )
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildShowMore(BuildContext context) {
    final theme = FluentTheme.of(context);
    final sorted = [...sortedItems];
    final filtered = [...filteredItems];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.resources.cardBackgroundFillColorDefault,
        border: Border(
          top: BorderSide(
            color: theme.resources.cardStrokeColorDefault,
            width: 1.0,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Txt(
            "${txt("showing")} ${sorted.length}/${filtered.length}",
            style: theme.typography.caption?.copyWith(
              color: theme.resources.textFillColorSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (filtered.length > sorted.length)
            FilledButton(
              onPressed: showMore,
              style: const ButtonStyle(
                padding: WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(FluentIcons.double_chevron_down, size: 12),
                  const SizedBox(width: 6),
                  Txt(txt("showMore"), style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTreatmentLabels(BoxConstraints constraints, Patient patient) {
    return GestureDetector(
      onTap: () {
        openPatient(patient, 1);
      },
      child: SizedBox(
        width: constraints.maxWidth - 296,
        height: 30,
        child: ListView(
          reverse: true,
          scrollDirection: Axis.horizontal,
          children: patient.treatmentLabels
              .map((txLabel) => SingleTreatmentLabel(
                    label: txLabel,
                    showPalmer: false,
                    showToolTip: false,
                  ))
              .toList(),
        ),
      ),
    );
  }

  SizedBox _buildBottomLabels(BoxConstraints constraints, double cS,
      Patient patient, double cW, String searchStringLowerCased) {
    return SizedBox(
      width: constraints.maxWidth - 96,
      height: 33,
      child: ListView.separated(
          separatorBuilder: (_, __) => SizedBox(width: cS),
          itemCount: patient.tableLabels.length,
          scrollDirection: Axis.horizontal,
          itemBuilder: (context, index) {
            final label = patient.tableLabels.toList()[index];
            final color = patient.tableLabels.toList()[index].color ??
                FluentTheme.of(context).inactiveColor;

            return ClickableBottomLabel(
              cW: cW,
              searchStringLowerCased: searchStringLowerCased,
              label: label,
              color: color,
              patient: patient,
              targetTab: label.tab,
            );
          }),
    );
  }

  Widget _buildTrailingButtons(Patient patient) {
    return Dismissible(
      key: Key(patient.id),
      direction: DismissDirection.horizontal,
      dismissThresholds: const {
        DismissDirection.startToEnd: .5,
        DismissDirection.endToStart: .5,
      },
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          routes.panels().removeWhere((p) => p.identifier == patient.id);
          routes.panels(routes.panels());
        } else if (direction == DismissDirection.endToStart) {
          openPatient(patient, 2);
        }
        return false;
      },
      child: Container(
        decoration: BoxDecoration(
            color: routes.panels().lastOrNull?.identifier == patient.id
                ? FluentTheme.of(context).accentColor
                : Colors.grey,
            border: Border.all(
                color: FluentTheme.of(context).inactiveColor.withAlpha(50)),
            borderRadius: const BorderRadiusDirectional.only(
              topStart: Radius.circular(10),
              bottomStart: Radius.circular(10),
            )),
        child: Column(
          spacing: 0,
          children: [
            _PatientTabOpener(
                patient: patient,
                tabIndex: 0,
                icon: FluentIcons.contact,
                title: "patientDetails"),
            _PatientTabOpener(
                patient: patient,
                tabIndex: 1,
                icon: FluentIcons.teeth,
                title: "dentalNotes"),
            _PatientTabOpener(
              patient: patient,
              tabIndex: 2,
              icon: WindowsIcons.calendar,
              title: "appointments",
            ),
          ],
        ),
      ),
    );
  }

  ComboBox<String> _buildTxFilter() {
    return ComboBox<String>(
      onChanged: (treatment) => setState(() => byTreatment = treatment),
      value: byTreatment,
      placeholder: Txt(txt("treatment")),
      items: [
        ComboBoxItem<String>(
          value: null,
          child: Txt(txt("allTreatments")),
        ),
        ...List.generate(
          treatments.length - 3,
          (i) {
            final o = treatments[i];
            return ComboBoxItem<String>(
              value: o.label,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(o.icon, color: o.color, size: 14),
                  const SizedBox(width: 6),
                  Container(
                    decoration: BoxDecoration(
                        color: o.color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                        border:
                            Border.all(color: o.color.withValues(alpha: 0.3))),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Txt(
                      txt(o.label),
                      style: TextStyle(
                          color: o.color,
                          fontWeight: FontWeight.w600,
                          fontSize: 11),
                    ),
                  ),
                ],
              ),
            );
          },
        )
      ],
    );
  }

  ToggleButton _buildsortByTitle() {
    return ToggleButton(
        checked: sortBy == -1,
        onChanged: (s) {
          s ? setSortBy(-1) : toggleSortDirection();
        },
        child: Row(
          spacing: 3,
          mainAxisSize: MainAxisSize.min,
          children: [
            sortBy == -1
                ? (sortDirection == -1
                    ? const Icon(FluentIcons.sort_down)
                    : const Icon(FluentIcons.sort_up))
                : const SizedBox.shrink(),
            Txt(txt("byTitle"))
          ],
        ));
  }

  Iterable<Widget> _buildSortByLabels() {
    return labels.map(
      (label) => ToggleButton(
          checked: sortBy == labels.indexOf(label),
          onChanged: (s) {
            s ? setSortBy(labels.indexOf(label)) : toggleSortDirection();
          },
          child: Row(
            spacing: 3,
            mainAxisSize: MainAxisSize.min,
            children: sortBy == labels.indexOf(label)
                ? [
                    sortDirection == -1
                        ? const Icon(FluentIcons.sort_down)
                        : const Icon(FluentIcons.sort_up),
                    Txt(label)
                  ]
                : [Txt(label)],
          )),
    );
  }

  void setSortBy(int? index) {
    setState(() {
      sortBy = index ?? -1;
    });
  }

  void toggleSortDirection() {
    setState(() {
      sortDirection = sortDirection * -1;
    });
  }

  void showMore() {
    setState(() {
      slice = slice + 10;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        scrollToBottom();
      });
    });
  }

  final ScrollController _scrollController = ScrollController();

  void scrollToBottom() {
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
    );
  }

  final archiveSelectedFlyout = FlyoutController();

  Widget _buildCommandBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            offset: const Offset(0.0, 6.0),
            blurRadius: 30.0,
            spreadRadius: 5.0,
            color: Colors.grey.withAlpha(50),
          )
        ],
        color: FluentTheme.of(context).menuColor,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            spacing: 8,
            children: [
              IconButton(
                icon: ButtonContent(FluentIcons.add_friend, txt("add")),
                onPressed: () {
                  openPatient();
                },
              ),
              const Divider(size: 20, direction: Axis.vertical),
              if (selected.isNotEmpty) ...[
                FlyoutTarget(
                  controller: archiveSelectedFlyout,
                  child: IconButton(
                    icon: ButtonContent(FluentIcons.archive,
                        "${txt("archive")} (${selected.length})"),
                    onPressed: () async {
                      final ids = selected;
                      if (ids.isEmpty) return;
                      await flyoutFocusFix(null);
                      archiveSelectedFlyout.showFlyout(builder: (context) {
                        return FlyoutContent(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Txt("${txt("sureArchiveSelected")} (${ids.length})"),
                              const SizedBox(height: 12.0),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  FilledButton(
                                    style: filledButtonStyle(
                                        Colors.warningPrimaryColor),
                                    onPressed: () {
                                      Flyout.of(context).close();
                                      for (var id in ids) {
                                        patients.archive(id);
                                      }
                                    },
                                    child: Row(
                                      children: [
                                        const Icon(FluentIcons.archive,
                                            size: 16),
                                        const SizedBox(width: 5),
                                        Txt(txt("archive")),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  const CloseButtonInDialog(),
                                ],
                              ),
                            ],
                          ),
                        );
                      });
                    },
                  ),
                ),
                IconButton(
                    icon: ButtonContent(WindowsIcons.save_copy,
                        "${txt("export")} (${selected.length})"),
                    onPressed: () {
                      showDialog(
                          context: context,
                          builder: (BuildContext context) {
                            return ExportPatientsDialog(ids: selected);
                          });
                    }),
              ]
            ],
          ),
          const ArchiveToggle()
        ],
      ),
    );
  }

  Widget _buildSearch() {
    return Expanded(
      child: CupertinoTextField(
        prefix: const Text("🔍"),
        decoration: BoxDecoration(
            color: Colors.transparent,
            border: Border.all(color: Colors.transparent)),
        placeholder: txt("searchPlaceholder"),
        controller: searchController,
        onChanged: (text) {
          setState(() {});
        },
      ),
    );
  }
}

class _PatientTabOpener extends StatelessWidget {
  const _PatientTabOpener({
    required this.patient,
    required this.tabIndex,
    required this.icon,
    required this.title,
  });
  final Patient patient;
  final int tabIndex;
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: txt(title),
      child: IconButton(
        style: const ButtonStyle(
          iconSize: WidgetStatePropertyAll(16),
          padding: WidgetStatePropertyAll(EdgeInsetsGeometry.zero),
        ),
        icon: Container(
          padding: const EdgeInsetsDirectional.only(
              top: 4, bottom: 4, start: 7, end: 10),
          child: Icon(icon, color: Colors.white),
        ),
        onPressed: () {
          openPatient(patient, tabIndex);
        },
      ),
    );
  }
}

class ClickableBottomLabel extends StatelessWidget {
  ClickableBottomLabel({
    super.key,
    required this.cW,
    required this.searchStringLowerCased,
    required this.label,
    required this.color,
    required this.patient,
    required this.targetTab,
  });

  final double cW;
  final String searchStringLowerCased;
  final PatientTableLabel label;
  final Color color;
  final Patient patient;
  final int targetTab;
  final GlobalKey<PhoneNumberButtonState> phoneButtonKey =
      GlobalKey<PhoneNumberButtonState>();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (label.title == txt("phone")) {
          phoneButtonKey.currentState?.showFlyout();
        } else {
          openPatient(patient, targetTab);
        }
      },
      child: Container(
        width: cW,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        decoration:
            searchStringLowerCased == label.searchableString.toLowerCase() &&
                    searchStringLowerCased.isNotEmpty
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(5),
                    color: color.withValues(alpha: .1))
                : null,
        child: Row(
          spacing: 5,
          children: [
            if (label.title == txt("phone") && label.color == null)
              PhoneNumberButton(phoneNumber: label.content, key: phoneButtonKey)
            else
              Icon(label.icon, size: 18, color: color),
            Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTitle(),
                label.content.contains(".")
                    ? _buildMoneyContent()
                    : _buildRegularContent(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Txt _buildTitle() {
    return Txt(
      label.title,
      style: TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 11,
        color: color,
      ),
    );
  }

  MoneyDisplay _buildMoneyContent() {
    return MoneyDisplay(label.content,
        style: TextStyle(fontSize: 11, color: color));
  }

  Txt _buildRegularContent() {
    return Txt(
      label.content.length > 10
          ? '${label.content.substring(0, 10)}...'
          : label.content,
      overflow: TextOverflow.clip,
      style: TextStyle(fontSize: 11, color: color),
    );
  }
}

class _SortableItem {
  double value;
  Patient item;
  _SortableItem(this.value, this.item);
}

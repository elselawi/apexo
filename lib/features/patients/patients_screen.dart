import 'dart:math';

import 'package:apexo/app/routes.dart';
import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/contact_buttons.dart';
import 'package:apexo/common_widgets/dialogs/export_patients_dialog.dart';
import 'package:apexo/common_widgets/item_title.dart';
import 'package:apexo/common_widgets/money_display.dart';
import 'package:apexo/common_widgets/show_more_bar.dart';
import 'package:apexo/common_widgets/teeth_selector/tx_options.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/patients/open_patient_panel.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/utils/parsed_phone_number.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:apexo/common_widgets/screen_command_bar.dart';
import 'package:flutter/foundation.dart';

final treatments = txOptions.where((x) => x.type != StateType.state).toList();

class PatientsScreen extends StatelessWidget {
  const PatientsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MStreamBuilder(
        streams: [
          patients.observableMap.stream,
          appointments.observableMap.stream,
          routes.panels.stream
        ],
        builder: (context, snapshot) {
          // ignore: prefer_const_constructors
          return _PatientsPage(DateTime.now().millisecondsSinceEpoch);
        });
  }
}

class _PatientsPage extends StatefulWidget {
  const _PatientsPage(this.tick);
  final int tick;
  @override
  State<_PatientsPage> createState() => _PatientsPageState();
}

class _PatientsPageState extends State<_PatientsPage> {
  Set<String> selected = {};
  String? byTreatment;
  int sortBy = -1;
  int sortDirection = 1;
  int slice = 10;

  List<Patient> _displayedItems = [];
  int _totalFilteredCount = 0;

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final archiveSelectedFlyout = FlyoutController();

  double calSpacing(double x) => (((3 / 205) * x) - (87 / 41)).clamp(5.0, 15.0);
  double calWidth(double x) => ((2 / 41) * x + (2580 / 41)).clamp(125, 145.0);

  @override
  void didUpdateWidget(covariant _PatientsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If parent streams emit a modification, recalculate the visible records
    if (oldWidget.tick != widget.tick) {
      _updateItems();
    }
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _updateItems();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _scrollController.dispose();
    archiveSelectedFlyout.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _updateItems();
  }

  void _updateItems() {
    final searchString = _searchController.text;
    final words =
        searchString.toLowerCase().replaceAll(RegExp("أ|إ"), "ا").split(" ");

    List<Patient> candidates = [];

    for (var item in patients.present.values) {
      final bool allTermsFound =
          words.every((word) => item.searchString.contains(word));
      if (allTermsFound) candidates.add(item);
    }

    if (byTreatment != null) {
      candidates = candidates.where((patient) {
        if (byTreatment != "bridge") {
          return patient.allPredefinedTreatments.contains(byTreatment);
        } else {
          return patient.allPredefinedTreatments.contains("abutment") ||
              patient.allPredefinedTreatments.contains("pontic") ||
              patient.allPredefinedTreatments.contains("bridge");
        }
      }).toList();
    }

    _totalFilteredCount = candidates.length;

    List<Patient> result = List<Patient>.from(candidates);
    if (sortBy < 0) {
      result.sort((a, b) {
        final aTitle = a.title.toLowerCase();
        final bTitle = b.title.toLowerCase();
        return aTitle.compareTo(bTitle) * sortDirection;
      });
    } else {
      result.sort((a, b) {
        final aVal = a.tableLabels[sortBy].value;
        final bVal = b.tableLabels[sortBy].value;
        return aVal.compareTo(bVal) * sortDirection;
      });
    }

    if (result.length > slice) {
      result = result.sublist(0, min(result.length, slice));
    }

    if (listEquals(_displayedItems, result)) return;

    setState(() {
      _displayedItems = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCommandBar(context),
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
          decoration: topBarDecoration(context, Colors.grey),
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
        ShowMoreBar(
          all: _totalFilteredCount,
          slice: _displayedItems.length,
          scrollController: _scrollController,
          callBack: () {
            slice = slice + 10;
            _updateItems();
          },
        ),
      ],
    );
  }

  ScreenCommandBar _buildCommandBar(BuildContext context) {
    return ScreenCommandBar(
      mainButton: IconButton(
        icon: ButtonContent(FluentIcons.add, txt("newPatient")),
        onPressed: () {
          openPatient();
        },
      ),
      otherButtons: [
        IconButton(
            icon: ButtonContent(WindowsIcons.copy, txt("import")),
            onPressed: () {
              showDialog(
                  barrierDismissible: true,
                  dismissWithEsc: true,
                  context: context,
                  builder: (BuildContext context) {
                    return const ImportPatientsDialog();
                  });
            }),
        if (selected.isNotEmpty)
          IconButton(
              icon: ButtonContent(
                  WindowsIcons.copy, "${txt("export")} (${selected.length})"),
              onPressed: () {
                showDialog(
                    barrierDismissible: true,
                    dismissWithEsc: true,
                    context: context,
                    builder: (BuildContext context) {
                      return ExportPatientsDialog(ids: selected);
                    });
              })
      ],
    );
  }

  Widget _buildTable() {
    return Expanded(
      child: LayoutBuilder(builder: (context, constraints) {
        final searchStringLowerCased = _searchController.text.toLowerCase();
        final calculatedWidth = calWidth(constraints.maxWidth);
        final calculatedSpacing = calSpacing(constraints.maxWidth);

        return ListView.builder(
            controller: _scrollController,
            itemCount: _displayedItems.length,
            padding: const EdgeInsets.all(0),
            itemExtent: 95,
            itemBuilder: (context, index) {
              final patient = _displayedItems[index];
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
      margin: const EdgeInsets.only(bottom: 0),
      shape: listDividerBorder(context),
      tileColor: WidgetStateColor.resolveWith((states) {
        if (selected.contains(patient.id)) {
          return Colors.blue.withAlpha(20);
        } else if (states.contains(WidgetState.hovered)) {
          return FluentTheme.of(context).resources.controlAltFillColorTertiary;
        }
        return FluentTheme.of(context).resources.solidBackgroundFillColorBase;
      }),
      title: buildSinglePatientTile(
        patient,
        constraints,
        calculatedSpacing,
        calculatedWidth,
        searchStringLowerCased,
      ),
      contentPadding:
          const EdgeInsetsDirectional.only(top: 0, bottom: 5, start: 5, end: 0),
    );
  }

  Widget buildSinglePatientTile(
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

  Widget _buildTreatmentLabels(BoxConstraints constraints, Patient patient) {
    return GestureDetector(
      onTap: () {
        openPatient(patient, 1);
      },
      child: SizedBox(
        width: constraints.maxWidth - 255,
        height: 30,
        child: SingleChildScrollView(
          reverse: true,
          scrollDirection: Axis.horizontal,
          child: Row(
            children: patient.treatmentLabels
                .map((e) => SingleTreatmentLabel(
                      label: e,
                      showPalmer: false,
                      showToolTip: false,
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomLabels(BoxConstraints constraints, double cS,
      Patient patient, double cW, String searchStringLowerCased) {
    final labelsList = patient.tableLabels;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 5),
      width: constraints.maxWidth - 52,
      height: 48,
      child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List.generate(labelsList.length, (i) {
              final label = labelsList[i];
              if (label.view == false) return const SizedBox.shrink();
              final color =
                  label.color ?? FluentTheme.of(context).inactiveColor;
              return ClickableBottomLabel(
                cW: cW,
                searchStringLowerCased: searchStringLowerCased,
                label: label,
                color: color,
                patient: patient,
                targetTab: label.tab,
              );
            }),
          )),
    );
  }

  ComboBox<String> _buildTxFilter() {
    return ComboBox<String>(
      onChanged: (treatment) {
        byTreatment = treatment;
        _updateItems();
      },
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
            Txt(txt("byName"))
          ],
        ));
  }

  Iterable<Widget> _buildSortByLabels() sync* {
    final labels = patients.present.values.firstOrNull?.tableLabels ?? [];
    for (int i = 0; i < labels.length; i++) {
      final label = labels[i];

      if (label.sortable == false) continue;

      yield ToggleButton(
        checked: sortBy == i,
        onChanged: (s) {
          s ? setSortBy(i) : toggleSortDirection();
        },
        child: Row(
          spacing: 3,
          mainAxisSize: MainAxisSize.min,
          children: sortBy == i
              ? [
                  sortDirection == -1
                      ? const Icon(FluentIcons.sort_down)
                      : const Icon(FluentIcons.sort_up),
                  Txt(label.title)
                ]
              : [Txt(label.title)],
        ),
      );
    }
  }

  void setSortBy(int? index) {
    sortBy = index ?? -1;
    _updateItems();
  }

  void toggleSortDirection() {
    sortDirection = sortDirection * -1;
    _updateItems();
  }

  Widget _buildSearch() {
    return Expanded(
      child: TopSearch(controller: _searchController, setState: setState),
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
    return Tooltip(
      message: "${label.title}: ${label.content}",
      child: GestureDetector(
        onTap: () {
          if (label.title == txt("phone")) {
            phoneButtonKey.currentState?.showMenu();
          } else {
            openPatient(patient, targetTab);
          }
        },
        child: Container(
          width: cW + 5,
          padding: const EdgeInsets.symmetric(horizontal: 2),
          decoration:
              searchStringLowerCased == label.searchableString.toLowerCase() &&
                      searchStringLowerCased.isNotEmpty
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(5),
                      color: color.withValues(alpha: .1))
                  : BoxDecoration(
                      color: Colors.transparent,
                      border: BorderDirectional(
                          end: BorderSide(
                              color: FluentTheme.of(context)
                                  .resources
                                  .dividerStrokeColorDefault)),
                    ),
          child: Row(
            spacing: 5,
            children: [
              if (label.title == txt("phone") && label.color == null)
                PhoneNumberButton(
                    phoneNumbers: label.content
                        .split(" ")
                        .map((e) => ParsedPhoneNumber(e))
                        .toList(),
                    key: phoneButtonKey)
              else
                IconButton(
                  icon: Icon(label.icon,
                      color: label.color == null ? null : Colors.white),
                  style: darkIconButtonStyle(context, label.color),
                  onPressed: () {
                    openPatient(patient, targetTab);
                  },
                ),
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
      ),
    );
  }

  Widget _buildTitle() {
    return SizedBox(
      width: 89,
      child: Txt(
        label.title,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 11,
          color: color,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildMoneyContent() {
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

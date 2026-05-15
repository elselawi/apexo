import 'dart:math';

import 'package:apexo/common_widgets/no_items_found.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/appointments/open_appointment_panel.dart';
import 'package:apexo/features/labwork/labworks_ctrl.dart';
import 'package:apexo/services/archived.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/common_widgets/archive_toggle.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/utils/constants.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/cupertino.dart';

class LabworksScreen extends StatelessWidget {
  const LabworksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      key: WK.labworksScreen,
      padding: EdgeInsets.zero,
      content: Column(
        children: [
          Expanded(
            child: MStreamBuilder(
                streams: [
                  appointments.observableMap.stream,
                  showArchived.stream
                ],
                builder: (context, snapshot) {
                  // ignore: prefer_const_constructors
                  return LabworksTable();
                }),
          ),
        ],
      ),
    );
  }
}

class LabworksTable extends StatefulWidget {
  const LabworksTable({super.key});

  @override
  State<LabworksTable> createState() => _LabworksTableState();
}

class _LabworksTableState extends State<LabworksTable> {
  bool canEdit(List<String> operatorIDs) {
    if (login.isAdmin) return true;
    if (login.permissions[PInt.appointments] > 1) return true;
    if (operatorIDs.contains(login.currentAccountID)) return true;
    return false;
  }

  bool showReceived = false;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  int _maxShowingItems = 20;
  String _sortColumn = 'date';
  bool _sortAscending = false;
  TextEditingController searchController = TextEditingController();

  List<Appointment> get filteredAndSorted {
    List<Appointment> result = showReceived
        ? labworks.appointmentsWithLabworks
        : <Appointment>{...labworks.due, ...labworks.notDelivered}.toList();

    // filtering by search
    final q = searchController.text;
    if (q.isNotEmpty) {
      result = result.where((lab) {
        return (lab.patient?.title ?? "")
                .toLowerCase()
                .contains(q.toLowerCase()) ||
            lab.date.toString().toLowerCase().contains(q.toLowerCase()) ||
            lab.labName.toLowerCase().contains(q.toLowerCase()) ||
            lab.labworkNotes.toLowerCase().contains(q.toLowerCase());
      }).toList();
    }

    // sorting
    result.sort((a, b) {
      int compare = 0;
      switch (_sortColumn) {
        case 'patient':
          compare =
              (a.patient?.title ?? "").compareTo((b.patient?.title ?? ""));
          break;
        case 'date':
          compare =
              a.date.toIso8601String().compareTo(b.date.toIso8601String());
          break;
        case 'operators':
          compare = a.operatorsNames.compareTo(b.operatorsNames);
        case 'laboratory':
          compare = a.labName.toLowerCase().compareTo(b.labName.toLowerCase());
          break;
        case 'notes':
          compare = a.labworkNotes.compareTo(b.labworkNotes);
        case 'status':
          compare =
              a.labworkStatus.toString().compareTo(b.labworkStatus.toString());
          break;
      }
      return _sortAscending ? compare : -compare;
    });

    return result;
  }

  List<Appointment> get truncated {
    return filteredAndSorted.sublist(
        0, min(_maxShowingItems, filteredAndSorted.length));
  }

  void _toggleSort(String column) {
    setState(() {
      if (_sortColumn == column) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = column;
        _sortAscending = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCommandBar(),
        _buildGrayBar(),
        filteredAndSorted.isEmpty
            ? const NoItemsFound()
            : _buildInnerTable(context),
      ],
    );
  }

  Expanded _buildInnerTable(BuildContext context) {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: FluentTheme.of(context).resources.cardStrokeColorDefault,
          ),
          borderRadius: BorderRadius.circular(8),
          color:
              FluentTheme.of(context).resources.cardBackgroundFillColorDefault,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTable(context),
            _buildTableFooter(context),
          ],
        ),
      ),
    );
  }

  Container _buildTableFooter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: FluentTheme.of(context).resources.cardStrokeColorDefault,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Txt(
            "${txt("showing")} ${min(_maxShowingItems, truncated.length)}/${filteredAndSorted.length}",
            style: FluentTheme.of(context).typography.body,
          ),
          Row(
            children: [
              if (filteredAndSorted.length > truncated.length)
                FilledButton(
                  child: Row(
                    children: [
                      const Icon(FluentIcons.double_chevron_down),
                      const SizedBox(width: 8),
                      Txt(txt("showMore")),
                    ],
                  ),
                  onPressed: () {
                    setState(() {
                      _maxShowingItems = _maxShowingItems + 10;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _scrollController.animateTo(
                          _scrollController.position.maxScrollExtent,
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeOut,
                        );
                      });
                    });
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Expanded _buildTable(BuildContext context) {
    return Expanded(
      child: LayoutBuilder(builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Container(
            constraints:
                BoxConstraints(maxWidth: max(constraints.maxWidth, 950)),
            child: Column(
              children: [
                _buildTableHeader(context),
                _buildTableItems(),
              ],
            ),
          ),
        );
      }),
    );
  }

  Expanded _buildTableItems() {
    return Expanded(
      child: ListView.builder(
        controller: _scrollController,
        itemCount: truncated.length,
        itemBuilder: (context, index) {
          final apt = truncated[index];
          return HoverButton(
            onPressed: () {
              openAppointment(appointments.get(apt.id));
            },
            builder: (context, states) {
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: states.isHovered
                      ? FluentTheme.of(context)
                          .resources
                          .subtleFillColorSecondary
                      : Colors.transparent,
                  border: Border(
                    bottom: BorderSide(
                      color: states.isHovered
                          ? FluentTheme.of(context)
                              .resources
                              .accentTextFillColorDisabled
                          : FluentTheme.of(context)
                              .resources
                              .dividerStrokeColorDefault,
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Checkbox(
                        style: CheckboxThemeData(
                          icon: apt.labworkReceived
                              ? WindowsIcons.completed
                              : FluentIcons.hour_glass,
                          uncheckedIconColor: WidgetStatePropertyAll(
                              FluentTheme.of(context).inactiveColor),
                        ),
                        checked: apt.labworkReceived,
                        onChanged: (checked) {
                          if (!canEdit(apt.operatorsIDs)) return;
                          apt.labworkReceived = checked == true;
                          appointments.set(apt);
                        }),
                    const SizedBox(width: 5),
                    _buildDataCell(apt.patient?.title ?? "",
                        cross: apt.labworkStatus == "done"),
                    _buildDataCell(apt.date.toString().split(" ").first),
                    _buildDataCell(apt.operatorsNames),
                    _buildDataCell(apt.labName),
                    _buildDataCell(apt.labworkNotes),
                    _buildDataCell(
                        "${apt.labworkStatus == txt("receivedAndDelivered") ? "✅" : apt.labworkStatus == txt("undelivered") ? "📌" : "⏳"} ${apt.labworkStatus.substring(0, 1).toUpperCase()}${apt.labworkStatus.substring(1)}"),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Container _buildTableHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: FluentTheme.of(context).resources.subtleFillColorSecondary,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(8),
          topRight: Radius.circular(8),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 15),
          _buildHeaderCell(txt("patient"), 'patient'),
          _buildHeaderCell(txt("date"), 'date'),
          _buildHeaderCell(txt("doctors"), 'operators'),
          _buildHeaderCell(txt("laboratory"), 'laboratory'),
          _buildHeaderCell(txt("notes"), 'notes'),
          _buildHeaderCell(txt("status"), "status")
        ],
      ),
    );
  }

  Padding _buildGrayBar() {
    return Padding(
      padding: const EdgeInsetsGeometry.all(10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Txt(
            "${txt("showing")} ${min(_maxShowingItems, truncated.length)}/${filteredAndSorted.length}",
            style: TextStyle(
                color: Colors.grey.toAccentColor().lightest,
                fontSize: 11,
                fontWeight: FontWeight.bold),
          ),
          ToggleButton(
            onChanged: (checked) {
              setState(() {
                showReceived = checked;
              });
            },
            checked: showReceived,
            child: Row(
              children: [
                const Icon(FluentIcons.view, size: 17),
                const SizedBox(width: 10),
                Txt(txt("showDone")),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommandBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
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
          Expanded(
            child: CupertinoTextField(
              decoration: BoxDecoration(
                  color: Colors.transparent,
                  border: Border.all(color: Colors.transparent)),
              placeholder: "🔍 ${txt("searchPlaceholder")}",
              controller: searchController,
              onChanged: (text) {
                setState(() {});
              },
            ),
          ),
          const ArchiveToggle()
        ],
      ),
    );
  }

  Widget _buildHeaderCell(String title, String column, {double width = 150}) {
    final isActive = _sortColumn == column;
    return SizedBox(
      width: width,
      child: IconButton(
          onPressed: () => _toggleSort(column),
          icon: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: FluentTheme.of(context).typography.bodyStrong?.copyWith(
                      color: isActive ? Colors.blue : null,
                    ),
              ),
              const SizedBox(
                width: 10,
              ),
              if (isActive) ...[
                const SizedBox(width: 4),
                Icon(
                  _sortAscending
                      ? FluentIcons.chevron_up
                      : FluentIcons.chevron_down,
                  size: 12,
                  color: Colors.blue,
                ),
              ],
            ],
          )),
    );
  }

  Widget _buildDataCell(String text, {double width = 150, bool cross = false}) {
    return SizedBox(
      width: width,
      child: Text(
        text,
        style: FluentTheme.of(context)
            .typography
            .body
            ?.copyWith(decoration: cross ? TextDecoration.lineThrough : null),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}

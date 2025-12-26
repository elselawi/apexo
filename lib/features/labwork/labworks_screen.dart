import 'dart:math';

import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/appointments/open_appointment_panel.dart';
import 'package:apexo/services/archived.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/common_widgets/archive_toggle.dart';
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
                streams: [appointments.observableMap.stream, showArchived.stream],
                builder: (context, snapshot) {
                  return LabworksTable(
                      labworks:
                          appointments.present.values.where((appointment) {
                    return appointment.hasLabwork;
                  }).map((appointment) {
                    return LabworkItem(
                      appointmentId: appointment.id,
                      patient: appointment.patient,
                      date: appointment.date,
                      laboratory: appointment.labName,
                      notes: appointment.labworkNotes,
                      status: appointment.labworkReceived,
                    );
                  }).toList());
                }),
          ),
        ],
      ),
    );
  }
}

class LabworksTable extends StatefulWidget {
  const LabworksTable({super.key, required this.labworks});
  final List<LabworkItem> labworks;

  @override
  State<LabworksTable> createState() => _LabworksTableState();
}

class _LabworksTableState extends State<LabworksTable> {
  bool showReceived = false;
  final TextEditingController _searchController = TextEditingController();
  int _maxShowingItems = 20;
  String _sortColumn = 'patient';
  bool _sortAscending = true;
  TextEditingController searchController = TextEditingController();

  List<LabworkItem> get filteredAndSorted {
    List<LabworkItem> result = widget.labworks.toSet().toList();

    // if we're not showing received orders
    if (!showReceived) {
      result = result.where((lab) => lab.status == false).toList();
    }

    // filtering by search
    final q = searchController.text;
    if (q.isNotEmpty) {
      result = result.where((lab) {
        return (lab.patient?.title ?? "")
                .toLowerCase()
                .contains(q.toLowerCase()) ||
            lab.date.toString().toLowerCase().contains(q.toLowerCase()) ||
            lab.laboratory.toLowerCase().contains(q.toLowerCase()) ||
            lab.notes.toLowerCase().contains(q.toLowerCase());
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
        case 'laboratory':
          compare =
              a.laboratory.toLowerCase().compareTo(b.laboratory.toLowerCase());
          break;
        case 'notes':
          compare = a.notes.compareTo(b.notes);
        case 'status':
          compare = a.status.toString().compareTo(b.status.toString());
          break;
      }
      return _sortAscending ? compare : -compare;
    });

    return result;
  }

  List<LabworkItem> get truncated {
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
    return NavigationView(
      content: ScaffoldPage(
        padding: EdgeInsets.zero,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCommandBar(),
            _buildGrayBar(),
            filteredAndSorted.isEmpty ? _buildNoItemsFound() : _buildInnerTable(context),
          ],
        ),
      ),
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Container(
              constraints: BoxConstraints(
                  maxWidth: max(constraints.maxWidth, 800)),
              child: Column(
                children: [
                  _buildTableHeader(context),
                  _buildTableItems(),
                ],
              ),
            ),
          );
        }
      ),
    );
  }

  Expanded _buildTableItems() {
    return Expanded(
      child: ListView.builder(
        itemCount: truncated.length,
        itemBuilder: (context, index) {
          final lab = truncated[index];
          return HoverButton(
            onPressed: () {
              openAppointment(appointments.get(lab.appointmentId));
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
                    _buildDataCell(lab.patient?.title ?? ""),
                    _buildDataCell(lab.date.toString().split(" ").first),
                    _buildDataCell(lab.laboratory),
                    _buildDataCell(lab.notes),
                    lab.status == true
                        ? _buildDataCell("➡️ ${txt("received")}")
                        : _buildDataCell("⚠️ ${txt("due")}"),
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
          _buildHeaderCell(txt("patient"), 'patient'),
          _buildHeaderCell(txt("date"), 'date'),
          _buildHeaderCell(txt("laboratory"), 'laboratory'),
          _buildHeaderCell(txt("notes"), 'notes'),
          _buildHeaderCell(txt("status"), "status")
        ],
      ),
    );
  }

  Widget _buildNoItemsFound() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: InfoBar(
          isIconVisible: true,
          severity: InfoBarSeverity.warning,
          title: Txt(txt("noItemsFound")),
        ),
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
                Txt(txt("showReceived"))
              ],
            ),
          ),
        ],
      ),
    );
  }

  Acrylic _buildCommandBar() {
    return Acrylic(
      elevation: 150,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
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

  Widget _buildDataCell(String text, {double width = 150}) {
    return SizedBox(
      width: width,
      child: Text(
        text,
        style: FluentTheme.of(context).typography.body,
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

import 'dart:math';
import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/no_items_found.dart';
import 'package:apexo/common_widgets/show_more_bar.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/labwork/labworks_ctrl.dart';
import 'package:apexo/features/labwork/open_labwork_panel.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/archived.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/utils/constants.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:apexo/common_widgets/screen_command_bar.dart';

class LabworksScreen extends StatelessWidget {
  const LabworksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: MStreamBuilder(
              streams: [appointments.observableMap.stream, showArchived.stream],
              builder: (context, snapshot) {
                // ignore: prefer_const_constructors
                return LabworksTable();
              }),
        ),
      ],
    );
  }
}

class LabworksTable extends StatefulWidget {
  const LabworksTable({super.key});

  @override
  State<LabworksTable> createState() => _LabworksTableState();
}

class _LabworksTableState extends State<LabworksTable> {
  bool showReceived = false;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController searchController = TextEditingController();
  int slice = 20;
  String _sortColumn = 'date';
  bool _sortAscending = false;

  @override
  void dispose() {
    searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool canEdit(List<String> operatorIDs) {
    if (login.isAdmin) return true;
    if (login.permissions[PInt.appointments] > 1) return true;
    if (operatorIDs.contains(login.currentAccountID)) return true;
    return false;
  }

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
    return filteredAndSorted.sublist(0, min(slice, filteredAndSorted.length));
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
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            spacing: 3,
            children: [_buildSearch(), _buildShowingToggle()],
          ),
        ),
        filteredAndSorted.isEmpty
            ? const NoItemsFound()
            : _buildInnerTable(context),
      ],
    );
  }

  Expanded _buildInnerTable(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTable(context),
          ShowMoreBar(
            scrollController: _scrollController,
            callBack: () {
              setState(() {
                slice = slice + 10;
              });
            },
            all: filteredAndSorted.length,
            slice: truncated.length,
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

  bool canEditLabwork(Appointment? appointment) {
    return login.permissions[PInt.postOp] == 2 ||
        (login.permissions[PInt.postOp] == 1 &&
            appointment?.operatorsIDs.contains(login.currentAccountID) == true);
  }

  Expanded _buildTableItems() {
    return Expanded(
      child: ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: truncated.length,
        itemBuilder: (context, index) {
          final apt = truncated[index];
          return HoverButton(
            onPressed: () {
              if (canEditLabwork(apt) == false) return;
              openLabworkPanel(apt);
              return;
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
                      : FluentTheme.of(context)
                          .resources
                          .solidBackgroundFillColorBase,
                  border: listDividerBorder(context),
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
                    _buildDataCell("📅 ${DF.allNumbers(apt.date)}"),
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
        horizontal: 8,
        vertical: 8,
      ),
      decoration: topBarDecoration(context, Colors.grey),
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

  ToggleButton _buildShowingToggle() {
    return ToggleButton(
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
    );
  }

  Widget _buildCommandBar() {
    return ScreenCommandBar(
      mainButton: (login.permissions[PInt.postOp] == 0 ||
              login.permissions[PInt.appointments] == 0)
          ? const SizedBox.shrink()
          : IconButton(
              icon: ButtonContent(WindowsIcons.add, txt("newLabwork")),
              onPressed: () {
                openLabworkPanel(null);
              }),
    );
  }

  Expanded _buildSearch() {
    return Expanded(
      child: TopSearch(controller: searchController, setState: setState),
    );
  }

  Widget _buildHeaderCell(String title, String column, {double width = 155}) {
    final isActive = _sortColumn == column;
    return SizedBox(
      width: width,
      child: IconButton(
          onPressed: () => _toggleSort(column),
          icon: Row(
            children: [
              if (isActive) ...[
                const SizedBox(width: 10),
                Icon(
                  _sortAscending ? FluentIcons.sort_up : FluentIcons.sort_down,
                  size: 16,
                ),
              ],
              Text(
                title,
                style: isActive
                    ? const TextStyle(fontWeight: FontWeight.w500)
                    : null,
              ),
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
}

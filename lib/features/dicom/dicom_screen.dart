import 'dart:math';

import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/dialogs/dialog_styling.dart';
import 'package:apexo/common_widgets/show_more_bar.dart';
import 'package:apexo/common_widgets/screen_command_bar.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/features/dicom/dicom_auto_import_toggle.dart';
import 'package:apexo/features/dicom/dicom_controller.dart';
import 'package:apexo/features/dicom/dicom_dir_manager.dart';
import 'package:apexo/features/dicom/open_dicom_viewer_panel.dart';
import 'package:apexo/features/patients/open_patient_panel.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/dicom/persistence/dicom_linked_store.dart';
import 'package:apexo/services/dicom/dicom_importer.dart'
    show DicomPendingImport, DicomParsedFile, ScanPhase;
import 'package:apexo/services/dicom/dicom_io_service.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';

// ── Helpers ───────────────────────────────────────────────────────────────

String _shortName(String path) => path.split(RegExp(r'[/\\]')).last;

String _fmtDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

// ── Screen ────────────────────────────────────────────────────────────────

class DicomScreen extends StatelessWidget {
  const DicomScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MStreamBuilder(
      streams: [
        dicomCtrl.pending.stream,
        dicomCtrl.importProgress.stream,
        dicomCtrl.scanPhase.stream,
        dicomCtrl.scanFileProgress.stream,
        globalSettings.observableMap.stream,
        dicomLinks.version.stream,
      ],
      builder: (context, _) {
        final tick = dicomCtrl.pending().hashCode +
            dicomCtrl.importProgress().hashCode +
            dicomCtrl.scanPhase().index;
        return _DicomPage(tick);
      },
    );
  }
}

class _DicomPage extends StatefulWidget {
  const _DicomPage(this.tick);
  final int tick;

  @override
  State<_DicomPage> createState() => _DicomPageState();
}

class _DicomPageState extends State<_DicomPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final Set<String> _selected = {};
  int _slice = 15;
  bool _showOnlyMatched = false;
  int _sortDirection = 1;

  @override
  void didUpdateWidget(covariant _DicomPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tick != widget.tick) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(() {});
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  List<DicomPendingImport> get _filtered {
    var items = [...dicomCtrl.pending()];
    final q = _searchCtrl.text.toLowerCase();
    if (q.isNotEmpty) {
      items = items.where((p) {
        return p.dicomPatientName.toLowerCase().contains(q) ||
            p.dicomPatientId.toLowerCase().contains(q) ||
            (p.matchedPatient?.title ?? '').toLowerCase().contains(q) ||
            (p.matchedPatient?.searchString ?? '').contains(q);
      }).toList();
    }
    if (_showOnlyMatched) {
      items = items.where((p) => p.matchedPatient != null).toList();
    }
    items.sort((a, b) {
      // 1. Confirmed matches first
      final aConf = a.isConfirmed ? 1.0 : 0.0;
      final bConf = b.isConfirmed ? 1.0 : 0.0;
      final c = bConf.compareTo(aConf);
      if (c != 0) return c * _sortDirection;
      // 2. Confidence descending
      final d = b.confidence.compareTo(a.confidence);
      if (d != 0) return d * _sortDirection;
      // 3. Deterministic tiebreaker: DICOM patient ID ascending (stable identity)
      return a.dicomPatientId.compareTo(b.dicomPatientId) * _sortDirection;
    });
    return items;
  }

  List<DicomPendingImport> get _truncated =>
      _filtered.sublist(0, min(_slice, _filtered.length));

  @override
  Widget build(BuildContext context) {
    final progress = dicomCtrl.importProgress();
    final phase = dicomCtrl.scanPhase();
    final fileProg = dicomCtrl.scanFileProgress();
    final isScanning = dicomCtrl.isScanning;
    final watchDirsEmpty = dicomCtrl.watchDirs.isEmpty;
    final importing = dicomCtrl.isImporting;
    final items = _truncated;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildCommandBar(),
        if (progress.total > 0) _ImportProgressBar(progress: progress),
        if (isScanning) _ScanProgressOverlay(phase: phase, fileProg: fileProg),
        if (!isScanning && !importing) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Row(children: [_buildSearch()]),
          ),
          Container(
            padding: const EdgeInsetsDirectional.only(
              start: 8.0,
              end: 0,
              top: 8.0,
              bottom: 8.0,
            ),
            width: double.infinity,
            decoration: topBarDecoration(context, Colors.grey),
            child: Row(
              spacing: 5,
              children: [
                _buildSortDirectionSwitch(),
                _buildMatchFilter(),
                _buildScanButton(isScanning, watchDirsEmpty),
              ],
            ),
          )
        ],
        if (items.isEmpty && !isScanning)
          _EmptyState(watchDirEmpty: watchDirsEmpty),
        if (items.isNotEmpty) _buildList(items, importing),
        ShowMoreBar(
          all: _filtered.length,
          slice: items.length,
          scrollController: _scrollCtrl,
          callBack: () => setState(() => _slice += 10),
        ),
      ],
    );
  }

  Button _buildScanButton(bool isScanning, bool watchDirsEmpty) {
    return Button(
      onPressed:
          isScanning || watchDirsEmpty ? null : () => dicomCtrl.refresh(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isScanning)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: SizedBox(
                  width: 14, height: 14, child: ProgressRing(strokeWidth: 2)),
            )
          else
            const Icon(FluentIcons.sync, size: 14),
          const SizedBox(width: 8),
          Txt(txt("scanNow")),
        ],
      ),
    );
  }

  Widget _buildCommandBar() {
    final linkedTxt =
        "${txt("dicomLinkedPatients")}: ${dicomCtrl.linkedPatients.length}";
    return ScreenCommandBar(
      mainButton: _DirectoryButton(),
      farItems: [
        Button(
            onPressed: () {
              showDialog(
                  barrierDismissible: true,
                  dismissWithEsc: true,
                  context: context,
                  builder: (ctx) {
                    return StatefulBuilder(builder: (context, setDialogState) {
                      return ContentDialog(
                        style: dialogStyling(context, false, false),
                        title: Txt(linkedTxt),
                        content: const _LinkedPatients(),
                        actions: [
                          Button(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: ButtonContent(
                              FluentIcons.cancel,
                              txt("close"),
                            ),
                          ),
                          Row(
                            spacing: 10,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              DicomAutoImportToggle(
                                updater: () => setDialogState(() {}),
                              ),
                              Txt(txt("dicomAutoImport")),
                            ],
                          ),
                        ],
                        constraints:
                            const BoxConstraints(maxHeight: 400, maxWidth: 350),
                      );
                    });
                  });
            },
            child: ButtonContent(FluentIcons.link, linkedTxt)),
      ],
      otherButtons: [
        if (_selected.isNotEmpty)
          IconButton(
            icon: ButtonContent(
                WindowsIcons.copy, '${txt("approve")} (${_selected.length})'),
            onPressed: () {
              dicomCtrl.batchApprove(_selected);
              _selected.clear();
            },
          ),
      ],
    );
  }

  Widget _buildSearch() {
    return Expanded(
      child: TopSearch(controller: _searchCtrl, setState: setState),
    );
  }

  Widget _buildMatchFilter() {
    return ToggleButton(
      checked: _showOnlyMatched,
      onChanged: (v) => setState(() => _showOnlyMatched = v),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(FluentIcons.filter, size: 16),
          const SizedBox(width: 6),
          Txt(txt("dicomFilterMatched")),
        ],
      ),
    );
  }

  Widget _buildSortDirectionSwitch() {
    return Button(
      onPressed: () => setState(() => _sortDirection = _sortDirection * -1),
      child: ButtonContent(
        _sortDirection == 1 ? FluentIcons.sort_up : FluentIcons.sort_down,
        "${txt("sort")} ${txt(_sortDirection == 1 ? "ascending" : "descending")}",
      ),
    );
  }

  Widget _buildList(List<DicomPendingImport> items, bool importing) {
    return Expanded(
      child: ListView.builder(
        controller: _scrollCtrl,
        itemCount: items.length,
        padding: EdgeInsets.zero,
        itemBuilder: (context, i) => _PendingImportCard(
          pending: items[i],
          selected: _selected.contains(items[i].dicomPatientId),
          importing: importing,
          onToggle: () {
            setState(() {
              final id = items[i].dicomPatientId;
              _selected.contains(id) ? _selected.remove(id) : _selected.add(id);
            });
          },
        ),
      ),
    );
  }
}

class _LinkedPatients extends StatelessWidget {
  const _LinkedPatients();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: dicomCtrl.pending.stream,
      builder: (context, snapshot) => dicomCtrl.linkedPatients.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(txt("dicomNoLinks"),
                  style: TextStyle(
                      fontStyle: FontStyle.italic,
                      color: const Color.fromARGB(255, 12, 12, 11)
                          .withAlpha(180))),
            )
          : ListView.builder(
              itemCount: dicomCtrl.linkedPatients.entries.length,
              itemBuilder: (context, index) {
                final entry = dicomCtrl.linkedPatients.entries.elementAt(index);
                return _LinkedPatientRow(
                  dicomId: entry.key,
                  apexoId: entry.value,
                );
              },
            ),
    );
  }
}

// ── Directory button ──────────────────────────────────────────────────────

class _DirectoryButton extends StatefulWidget {
  @override
  State<_DirectoryButton> createState() => _DirectoryButtonState();
}

class _DirectoryButtonState extends State<_DirectoryButton> {
  Future<void> _openManageDirsDialog() async {
    List<String> dirs = List<String>.from(globalSettings.dicomWatchDirs);

    final confirmed = await showDialog<bool>(
      barrierDismissible: true,
      context: context,
      builder: (ctx) => ContentDialog(
        style: dialogStyling(context, false, true),
        title: Txt(txt("dicomWatchDirs_dialogTitle")),
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 500),
        content: StatefulBuilder(
          builder: (ctx, setDialogState) {
            return DicomDirectoryManager(
              dirs: dirs,
              onChanged: (newDirs) => setDialogState(() => dirs = newDirs),
            );
          },
        ),
        actions: [
          Button(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Txt(txt("cancel")),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Txt(txt("save")),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      globalSettings.dicomWatchDirs = dirs;
      if (mounted) setState(() {});
      await dicomCtrl.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final watchDirs = dicomCtrl.watchDirs;
    return Button(
      onPressed: _openManageDirsDialog,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(WindowsIcons.folder, size: 14),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 70),
            child: Text(
              watchDirs.isEmpty
                  ? txt("add")
                  : watchDirs.length == 1
                      ? watchDirs.first
                      : "${watchDirs.length} ${txt("dicomFolders")}",
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Import progress bar ───────────────────────────────────────────────────

class _ImportProgressBar extends StatelessWidget {
  const _ImportProgressBar({required this.progress});
  final ({int current, int total}) progress;

  @override
  Widget build(BuildContext context) {
    final pct = progress.total > 0 ? progress.current / progress.total : 0.0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: FluentTheme.of(context).accentColor.withAlpha(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            txt("dicomImportingFiles")
                .replaceAll("{current}", progress.current.toString())
                .replaceAll("{total}", progress.total.toString()),
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 6),
          ProgressBar(value: pct * 100),
        ],
      ),
    );
  }
}

// ── Scan progress overlay ─────────────────────────────────────────────────

class _ScanProgressOverlay extends StatelessWidget {
  const _ScanProgressOverlay({required this.phase, required this.fileProg});
  final ScanPhase phase;
  final ({int current, int total, String path, bool cacheHit}) fileProg;

  String _phaseLabel(ScanPhase p) {
    switch (p) {
      case ScanPhase.idle:
        return '';
      case ScanPhase.snapshotting:
        return txt("dicomScanSnapshotting");
      case ScanPhase.listingDir:
        return txt("dicomScanListingDir");
      case ScanPhase.scanningFiles:
        return txt("dicomScanScanningFiles");
      case ScanPhase.persisting:
        return txt("dicomScanPersisting");
      case ScanPhase.matching:
        return txt("dicomScanMatching");
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = _phaseLabel(phase);
    final hasFileProgress =
        phase == ScanPhase.scanningFiles && fileProg.total > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: FluentTheme.of(context).accentColor.withAlpha(18),
        border: Border(
          bottom: BorderSide(
              color: FluentTheme.of(context).accentColor.withAlpha(40)),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(
              width: 16, height: 16, child: ProgressRing(strokeWidth: 2)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: FluentTheme.of(context).accentColor)),
                if (hasFileProgress) ...[
                  const SizedBox(height: 4),
                  Text(
                    _fileLabel(),
                    style: TextStyle(
                        fontSize: 11,
                        color: FluentTheme.of(context).accentColor),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  ProgressBar(
                      value: (fileProg.current / fileProg.total * 100)
                          .clamp(0.0, 100.0)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Button(
            onPressed: () => dicomCtrl.cancelScan(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(FluentIcons.cancel, size: 12),
                const SizedBox(width: 6),
                Txt(txt("dicomScanHalt")),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fileLabel() {
    final name = _shortName(fileProg.path);
    final kind =
        fileProg.cacheHit ? txt("dicomScanCacheHit") : txt("dicomScanParsing");
    return '$kind ${fileProg.current}/${fileProg.total} — $name';
  }
}

// ── Empty state ───────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.watchDirEmpty});
  final bool watchDirEmpty;

  @override
  Widget build(BuildContext context) {
    final txtColor = FluentTheme.of(context).resources.textFillColorDisabled;
    return Expanded(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 60),
          child: Column(
            children: [
              const Icon(FluentIcons.generic_scan, size: 48),
              const SizedBox(height: 16),
              Txt(
                watchDirEmpty
                    ? txt("dicomWatchDir_notSet")
                    : txt("dicomNoNewFiles"),
                style: TextStyle(
                  color: txtColor,
                  fontStyle: FontStyle.italic,
                ),
              ),
              if (!watchDirEmpty) ...[
                const SizedBox(height: 8),
                Text(txt("dicomNoNewFiles_desc"),
                    style: TextStyle(fontSize: 11, color: txtColor)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Pending import card (checkbox + PatientsScreen-style tile) ─────────────

class _PendingImportCard extends StatefulWidget {
  const _PendingImportCard({
    required this.pending,
    required this.selected,
    required this.importing,
    required this.onToggle,
  });
  final DicomPendingImport pending;
  final bool selected;
  final bool importing;
  final VoidCallback onToggle;

  @override
  State<_PendingImportCard> createState() => _PendingImportCardState();
}

class _PendingImportCardState extends State<_PendingImportCard> {
  @override
  Widget build(BuildContext context) {
    final p = widget.pending;
    final matched = p.matchedPatient;
    final dateInfo = matched != null ? _buildDateMatchInfo(matched.id) : null;
    final importing = widget.importing;
    final theme = FluentTheme.of(context);

    return ListTile.selectable(
      selected: widget.selected,
      selectionMode: ListTileSelectionMode.multiple,
      key: ValueKey(p.dicomPatientId),
      margin: const EdgeInsets.only(bottom: 0),
      onSelectionChange: (_) => widget.onToggle(),
      shape: listDividerBorder(context),
      tileColor: WidgetStateColor.resolveWith((states) {
        if (widget.selected) {
          return Colors.blue.withAlpha(20);
        } else if (states.contains(WidgetState.hovered)) {
          return theme.resources.controlAltFillColorTertiary;
        }
        return theme.resources.solidBackgroundFillColorBase;
      }),
      title: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          spacing: 10,
          children: [
            const Divider(size: 65, direction: Axis.vertical),
            Expanded(
              child: Column(
                spacing: 5,
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Title: ApexoName → DICOMName
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (matched != null) ...[
                        _NamePill(
                          name: matched.title,
                          icon: FluentIcons.contact,
                          color: Colors.blue,
                          onPress: () {
                            openPatient(matched);
                          },
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child: Icon(WindowsIcons.chrome_switch, size: 14),
                        ),
                      ],
                      _NamePill(
                        name: p.dicomPatientName.isEmpty
                            ? txt("dicomUnknownPatient")
                            : p.dicomPatientName,
                        icon: FluentIcons.generic_scan,
                        color: Colors.warningPrimaryColor,
                      ),
                      const SizedBox(width: 4),
                      _ConfidenceBadge(confidence: p.confidence),
                    ],
                  ),
                  // Meta row
                  Expander(
                      headerShape: (_) => Border.all(color: Colors.transparent),
                      contentPadding: EdgeInsets.zero,
                      headerBackgroundColor: WidgetStatePropertyAll(
                          theme.resources.solidBackgroundFillColorBase),
                      header: Row(
                        spacing: 5,
                        children: [
                          if (matched != null)
                            _DateMatchPill(pending: p, dateInfo: dateInfo),
                          Text(
                            '${p.fileCount} ${txt("dicomFiles")}'
                            '  ·  ${p.dates.length} ${txt("dicomDates")}',
                            style: TextStyle(
                                fontSize: 11,
                                color: theme.resources.textFillColorSecondary),
                          ),
                        ],
                      ),
                      content: _FileList(pending: p)),

                  // Match pill
                  if (matched == null) _NoMatchPill(),
                  Row(
                    spacing: 5,
                    children: [
                      if (matched != null)
                        FilledButton(
                          onPressed:
                              importing ? null : () => dicomCtrl.approve(p),
                          child: ButtonContent(
                              FluentIcons.accept, txt("approve"),
                              size: 12),
                        ),
                      Button(
                        onPressed: importing
                            ? null
                            : () => _showPatientPicker(context, p),
                        child: ButtonContent(
                            FluentIcons.switch_user, txt("change"),
                            size: 12),
                      ),
                      if (matched != null)
                        Button(
                          onPressed:
                              importing ? null : () => dicomCtrl.unmatch(p),
                          child: ButtonContent(
                              FluentIcons.cancel, txt("unmatch"),
                              size: 12),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _buildDateMatchInfo(String apexoId) {
    final matching = dicomCtrl.matchingDates(widget.pending, apexoId);
    final mismatching = dicomCtrl.mismatchingDates(widget.pending, apexoId);
    if (mismatching.isEmpty && matching.isNotEmpty) return 'all_match';
    if (matching.isEmpty) return 'none_match';
    return 'partial';
  }

  Future<void> _showPatientPicker(
      BuildContext context, DicomPendingImport p) async {
    final selected = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      dismissWithEsc: true,
      builder: (ctx) => _PatientPickerDialog(pending: p),
    );
    if (selected != null && context.mounted) {
      await dicomCtrl.manualMatch(p, selected);
    }
  }
}

class _NamePill extends StatelessWidget {
  final String name;
  final Color color;
  final IconData icon;
  final VoidCallback? onPress;

  const _NamePill({
    required this.name,
    required this.color,
    required this.icon,
    this.onPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPress,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 5,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: color.withValues(alpha: 0.2),
        ),
        child: Row(
          spacing: 5,
          children: [
            Icon(
              icon,
              size: 13,
              color: color,
            ),
            Text(name,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: color),
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

// ── File list (expandable per card) ───────────────────────────────────────

class _FileList extends StatelessWidget {
  const _FileList({required this.pending});
  final DicomPendingImport pending;

  @override
  Widget build(BuildContext context) {
    final byDate = <DateTime, List<DicomParsedFile>>{};
    for (final f in pending.files) {
      final day = f.dcmDate ?? DateTime(1970);
      byDate.putIfAbsent(day, () => []).add(f);
    }
    final sortedDates = byDate.keys.toList()..sort();

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluentTheme.of(context).menuColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final date in sortedDates) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Text(
                    '${txt("date")}: ${_fmtDate(date)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  if (pending.matchedPatient != null) ...[
                    const SizedBox(width: 6),
                    _DateMatchIcon(
                      matches: dicomCtrl
                          .matchingDates(pending, pending.matchedPatient!.id)
                          .contains(date),
                    ),
                  ],
                ],
              ),
            ),
            for (final f in byDate[date]!)
              Padding(
                padding: const EdgeInsets.only(left: 12, bottom: 2),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: HyperlinkButton(
                    onPressed: () async {
                      final bytes = await DicomIO.readBytes(f.path);
                      if (bytes != null && context.mounted) {
                        openDicomFromBytes(context, bytes);
                      }
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          FluentIcons.file_image,
                          size: 12,
                          color: FluentTheme.of(context)
                              .resources
                              .textFillColorPrimary,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            _shortName(f.path),
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11,
                                color: FluentTheme.of(context)
                                    .resources
                                    .textFillColorPrimary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

// ── Match pill ────────────────────────────────────────────────────────────

/// A tiny green ✓ or red ✗ indicating whether a single study date matches
/// an existing appointment for the matched patient.
class _DateMatchIcon extends StatelessWidget {
  const _DateMatchIcon({required this.matches});
  final bool matches;

  @override
  Widget build(BuildContext context) {
    final color = matches ? Colors.green : Colors.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        spacing: 3,
        children: [
          Icon(
            matches ? WindowsIcons.check_mark : WindowsIcons.warning,
            size: 16,
            color: color,
          ),
          Txt(
            txt(matches ? "foundAppointment" : "willBeCreated"),
            style: TextStyle(
                fontSize: 12, color: color, fontWeight: FontWeight.w600),
          )
        ],
      ),
    );
  }
}

class _DateMatchPill extends StatelessWidget {
  const _DateMatchPill({required this.pending, this.dateInfo});
  final DicomPendingImport pending;
  final String? dateInfo;

  @override
  Widget build(BuildContext context) {
    final dateColor = dateInfo == 'all_match'
        ? Colors.green
        : dateInfo == 'none_match'
            ? Colors.red
            : Colors.orange;
    final dateIcon = dateInfo == 'all_match'
        ? FluentIcons.calendar
        : dateInfo == 'none_match'
            ? FluentIcons.calendar_reply
            : FluentIcons.calendar;
    final dateLabel = dateInfo == 'all_match'
        ? '  ${txt("dicomDatesMatch")}'
        : dateInfo == 'none_match'
            ? '  ${txt("dicomDatesNoMatch")}'
            : '  ${txt("dicomDatesPartial")}';

    return dateInfo != null
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: dateColor.withAlpha(20),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(dateIcon, size: 11, color: dateColor),
                Text(dateLabel,
                    style: TextStyle(fontSize: 11, color: dateColor)),
              ],
            ),
          )
        : const SizedBox();
  }
}

class _NoMatchPill extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.orange.withAlpha(20),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(FluentIcons.warning, size: 12, color: Colors.orange),
              const SizedBox(width: 4),
              Text(txt("dicomNoMatch"),
                  style: TextStyle(fontSize: 12, color: Colors.orange)),
            ],
          ),
        ),
      ],
    );
  }
}

class _ConfidenceBadge extends StatelessWidget {
  const _ConfidenceBadge({required this.confidence});
  final double confidence;

  Color get _color {
    if (confidence >= 0.8) return Colors.green;
    if (confidence >= 0.5) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _color.withAlpha(30),
        border: Border.all(color: _color.withAlpha(120)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '${(confidence * 100).round()}%',
        style:
            TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _color),
      ),
    );
  }
}

// ── Patient picker dialog (with date alignment) ───────────────────────────

class _PatientPickerDialog extends StatefulWidget {
  const _PatientPickerDialog({required this.pending});
  final DicomPendingImport pending;

  @override
  State<_PatientPickerDialog> createState() => _PatientPickerDialogState();
}

class _PatientPickerDialogState extends State<_PatientPickerDialog> {
  List<Patient> _results = const [];
  String? _confirmingId;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  void _search(String q) {
    final query = q.toLowerCase();
    _results = patients.present.values
        .where((p) {
          return p.title.toLowerCase().contains(query) ||
              p.searchString.contains(query);
        })
        .take(50)
        .toList();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_confirmingId != null) {
      return _DateAlignmentDialog(
        pending: widget.pending,
        apexoId: _confirmingId!,
        onConfirm: () => Navigator.of(context).pop(_confirmingId),
        onBack: () => setState(() => _confirmingId = null),
      );
    }

    return ContentDialog(
      style: dialogStyling(context, false, true),
      title: Text(
          '${txt("dicomSelectPatient")}: ${widget.pending.dicomPatientName}'),
      constraints: const BoxConstraints(maxWidth: 550, maxHeight: 550),
      content: Column(
        children: [
          TextBox(
            placeholder: txt("dicomSearchPatient"),
            onChanged: _search,
            autofocus: true,
            prefix: const Icon(FluentIcons.search, size: 14),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.builder(
              itemCount: _results.length,
              itemBuilder: (context, i) {
                final patient = _results[i];
                final matchCount =
                    dicomCtrl.matchingDates(widget.pending, patient.id).length;
                final totalDates = widget.pending.dates.length;
                final dateLabel = totalDates > 0
                    ? '$matchCount/$totalDates ${txt("dicomDatesMatch")}'
                    : '';

                return ListTile(
                  leading: const Icon(FluentIcons.contact),
                  title: Text(patient.title),
                  subtitle: dateLabel.isNotEmpty
                      ? Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: matchCount == totalDates
                                    ? Colors.green.withAlpha(20)
                                    : matchCount > 0
                                        ? Colors.orange.withAlpha(20)
                                        : Colors.red.withAlpha(20),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                dateLabel,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: matchCount == totalDates
                                      ? Colors.green
                                      : matchCount > 0
                                          ? Colors.orange
                                          : Colors.red,
                                ),
                              ),
                            ),
                          ],
                        )
                      : null,
                  onPressed: () => setState(() => _confirmingId = patient.id),
                );
              },
            ),
          ),
        ],
      ),
      actions: [
        Button(
          onPressed: () => Navigator.of(context).pop(),
          child: Txt(txt("cancel")),
        ),
      ],
    );
  }
}

class _DateAlignmentDialog extends StatelessWidget {
  const _DateAlignmentDialog({
    required this.pending,
    required this.apexoId,
    required this.onConfirm,
    required this.onBack,
  });
  final DicomPendingImport pending;
  final String apexoId;
  final VoidCallback onConfirm;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final matching = dicomCtrl.matchingDates(pending, apexoId);
    final mismatching = dicomCtrl.mismatchingDates(pending, apexoId);
    final patient = patients.get(apexoId);

    return ContentDialog(
      style: dialogStyling(context, false, true),
      title: Txt(txt("dicomDateAlignment")),
      constraints: const BoxConstraints(maxWidth: 480, maxHeight: 450),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            spacing: 5,
            children: [
              Text(
                '${txt("dicomMatchingPatient")}:',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              _NamePill(
                  name: patient?.title ?? apexoId,
                  color: Colors.blue,
                  icon: FluentIcons.contact),
              const Icon(WindowsIcons.chrome_switch, size: 14),
              _NamePill(
                  name: pending.dicomPatientName,
                  color: Colors.warningPrimaryColor,
                  icon: FluentIcons.generic_scan),
            ],
          ),
          const SizedBox(height: 14),
          if (matching.isNotEmpty) ...[
            Text(txt("dicomDatesMatchList"),
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.green)),
            const SizedBox(height: 4),
            ...matching.map((d) => Padding(
                  padding: const EdgeInsets.only(left: 12, bottom: 2),
                  child: Row(
                    children: [
                      Icon(FluentIcons.calendar, size: 12, color: Colors.green),
                      const SizedBox(width: 6),
                      Text(_fmtDate(d),
                          style: TextStyle(fontSize: 12, color: Colors.green)),
                    ],
                  ),
                )),
            const SizedBox(height: 10),
          ],
          if (mismatching.isNotEmpty) ...[
            Text(txt("dicomDatesNoMatchList"),
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.red)),
            const SizedBox(height: 4),
            ...mismatching.map((d) => Padding(
                  padding: const EdgeInsets.only(left: 12, bottom: 2),
                  child: Row(
                    children: [
                      Icon(FluentIcons.calendar_reply,
                          size: 12, color: Colors.red),
                      const SizedBox(width: 6),
                      Text(_fmtDate(d),
                          style: TextStyle(fontSize: 12, color: Colors.red)),
                    ],
                  ),
                )),
          ],
        ],
      ),
      actions: [
        Button(onPressed: onBack, child: Txt(txt("back"))),
        FilledButton(onPressed: onConfirm, child: Txt(txt("save"))),
      ],
    );
  }
}

// ── Linked Patients section ───────────────────────────────────────────────

class _LinkedPatientRow extends StatelessWidget {
  const _LinkedPatientRow({required this.dicomId, required this.apexoId});
  final String dicomId;
  final String apexoId;

  @override
  Widget build(BuildContext context) {
    final apexoPatient = patients.get(apexoId);
    final apexoName = apexoPatient?.title ?? txt("dicomPatientDeleted");
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(WindowsIcons.folder,
              size: 14,
              color: FluentTheme.of(context).resources.textFillColorDisabled),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$dicomId → $apexoName',
                    style: const TextStyle(fontSize: 13)),
                if (apexoPatient == null)
                  Text(txt("dicomPatientDeleted_desc"),
                      style: TextStyle(
                          fontSize: 11, color: Colors.red.withAlpha(180))),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Button(
            onPressed: () => dicomCtrl.unlinkPatient(dicomId),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(FluentIcons.remove_link, size: 12),
                const SizedBox(width: 6),
                Txt(txt("dicomUnlink")),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

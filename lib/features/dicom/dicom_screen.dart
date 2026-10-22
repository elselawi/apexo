import 'dart:async';
import 'dart:math';

import 'package:apexo/app/app_context.dart';
import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/dialogs/dialog_styling.dart';
import 'package:apexo/common_widgets/show_more_bar.dart';
import 'package:apexo/common_widgets/screen_command_bar.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/features/dicom/dicom_auto_import_toggle.dart';
import 'package:apexo/features/dicom/dicom_controller.dart';
import 'package:apexo/features/dicom/dicom_dir_manager.dart';
import 'package:apexo/features/dicom/open_dicom_viewer_window.dart';
import 'package:apexo/features/patients/open_patient_panel.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/dicom/persistence/dicom_linked_store.dart';
import 'package:apexo/services/dicom/dicom_importer.dart'
    show DicomPendingImport, DicomParsedFile, ImportPhase, ScanPhase;
import 'package:apexo/services/dicom/dicom_io_service.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';

part 'dicom_tables.dart';
part 'dicom_import_widgets.dart';
part 'dicom_dialogs.dart';

// ── Helpers ───────────────────────────────────────────────────────────────

String _shortName(String path) => path.split(RegExp(r'[/\\]')).last;

String _fmtDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Shows a brief success bar after an import finishes, so the dentist gets
/// confirmation instead of the progress bar silently disappearing.
void _showImportComplete(int batches) {
  if (!bContext.mounted) return;
  unawaited(displayInfoBar(
    bContext,
    builder: (context, close) => InfoBar(
      title: Txt(txt("dicomImportComplete")),
      content: Text('$batches \u00d7 ${txt("dicomFiles")}'),
      severity: InfoBarSeverity.success,
      onClose: close,
    ),
  ));
}

// ── Screen ────────────────────────────────────────────────────────────────

class DicomScreen extends StatelessWidget {
  const DicomScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MStreamBuilder(
      streams: [
        dicomCtrl.pending.stream,
        dicomCtrl.importProgress.stream,
        dicomCtrl.importPhase.stream,
        dicomCtrl.scanPhase.stream,
        dicomCtrl.scanFileProgress.stream,
        globalSettings.observableMap.stream,
        dicomLinks.version.stream,
      ],
      builder: (context, _) {
        final tick = dicomCtrl.pending().hashCode +
            dicomCtrl.importProgress().hashCode +
            dicomCtrl.importPhase().index +
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
    if (oldWidget.tick != widget.tick) {
      // Drop selections whose batch no longer exists (e.g. it was auto-approved
      // in the background) so the count never shows a phantom "Approve (2)".
      final present = dicomCtrl.pending().map((p) => p.selectionKey).toSet();
      _selected.removeWhere((key) => !present.contains(key));
      setState(() {});
    }
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
    final importPhase = dicomCtrl.importPhase();
    final phase = dicomCtrl.scanPhase();
    final fileProg = dicomCtrl.scanFileProgress();
    final isScanning = dicomCtrl.isScanning;
    final watchDirsEmpty = dicomCtrl.watchDirs.isEmpty;
    final importing = dicomCtrl.isImporting;
    final items = _truncated;

    return Column(
      key: WK.dicomScreen,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildCommandBar(),
        if (progress.total > 0)
          _ImportProgressBar(progress: progress, phase: importPhase),
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
      key: WK.dicomScanButton,
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
              unawaited(showDialog(
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
                          Row(
                            children: [
                              Button(
                                onPressed: () => Navigator.of(ctx).pop(false),
                                child: ButtonContent(
                                  FluentIcons.cancel,
                                  txt("close"),
                                ),
                              ),
                            ],
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
                            const BoxConstraints(maxHeight: 560, maxWidth: 720),
                      );
                    });
                  }));
            },
            child: ButtonContent(FluentIcons.link, linkedTxt)),
      ],
      otherButtons: [
        if (_selected.isNotEmpty)
          IconButton(
            icon: ButtonContent(
                WindowsIcons.copy, '${txt("approve")} (${_selected.length})'),
            onPressed: () async {
              final selection = Set<String>.from(_selected);
              final approved = await dicomCtrl.batchApprove(selection);
              if (!mounted) return;
              setState(() {
                final present =
                    dicomCtrl.pending().map((p) => p.selectionKey).toSet();
                _selected.removeWhere((key) => !present.contains(key));
              });
              if (approved > 0) _showImportComplete(approved);
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
          selected: _selected.contains(items[i].selectionKey),
          importing: importing,
          onToggle: () {
            setState(() {
              final id = items[i].selectionKey;
              _selected.contains(id) ? _selected.remove(id) : _selected.add(id);
            });
          },
        ),
      ),
    );
  }
}


part of 'dicom_screen.dart';

class _ImportProgressBar extends StatelessWidget {
  const _ImportProgressBar({required this.progress, required this.phase});
  final ({int current, int total}) progress;
  final ImportPhase phase;

  @override
  Widget build(BuildContext context) {
    final syncing = phase == ImportPhase.syncing;
    final pct = progress.total > 0 ? progress.current / progress.total : 0.0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: FluentTheme.of(context).accentColor.withAlpha(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            syncing
                ? txt("dicomSyncingImport")
                : txt("dicomImportingFiles")
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
              Icon(
                FluentIcons.generic_scan,
                size: 48,
                color: txtColor,
              ),
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
      key: WK.dicomPendingCard(p.selectionKey),
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
                            unawaited(openPatient(matched));
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
                          key: WK.dicomApprove,
                          onPressed:
                              importing ? null : () => _approve(widget.pending),
                          child: ButtonContent(
                              FluentIcons.accept, txt("approve"),
                              size: 12),
                        ),
                      Button(
                        key: WK.dicomChangeMatch,
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

  Future<void> _approve(DicomPendingImport p) async {
    await dicomCtrl.approve(p);
    final stillPending =
        dicomCtrl.pending().any((x) => x.selectionKey == p.selectionKey);
    if (!stillPending) _showImportComplete(1);
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
  const _NamePill({
    required this.name,
    required this.color,
    required this.icon,
    this.onPress,
  });
  final String name;
  final Color color;
  final IconData icon;
  final VoidCallback? onPress;

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
      final d = f.effectiveDate;
      final day = DateTime(d.year, d.month, d.day);
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
                        openDicomFromBytes(bytes,
                            name: f.path.split(RegExp(r'[/\\]')).last);
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

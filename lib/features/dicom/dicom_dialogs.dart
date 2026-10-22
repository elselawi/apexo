part of 'dicom_screen.dart';

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
    final theme = FluentTheme.of(context);
    final apexoPatient = patients.get(apexoId);
    final apexoName = apexoPatient?.title ?? txt('dicomPatientDeleted');
    final linked = apexoPatient != null;
    final statusColor = linked ? Colors.green : Colors.red;
    final importedFileCount = dicomLinks.importedFileCountFor(dicomId);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.resources.dividerStrokeColorDefault,
            width: 0.6,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Tooltip(
              message: dicomId,
              child: Text(
                dicomId,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Icon(
                  linked ? FluentIcons.contact : FluentIcons.warning,
                  size: 13,
                  color: statusColor,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Tooltip(
                    message: apexoName,
                    child: Text(
                      apexoName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: linked
                            ? theme.resources.textFillColorPrimary
                            : statusColor,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 100,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Tooltip(
                message: '$importedFileCount ${txt('dicomFiles')}',
                child: Text(
                  importedFileCount.toString(),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 92,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(24),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  txt(linked ? 'dicomLinkActive' : 'dicomLinkBroken'),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 36,
            child: Tooltip(
              message: txt('dicomUnlink'),
              child: IconButton(
                icon: const Icon(FluentIcons.remove_link, size: 13),
                onPressed: () => dicomCtrl.unlinkPatient(dicomId),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

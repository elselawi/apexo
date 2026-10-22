part of 'dicom_screen.dart';

class _LinkedPatients extends StatefulWidget {
  const _LinkedPatients();

  @override
  State<_LinkedPatients> createState() => _LinkedPatientsState();
}

class _LinkedPatientsState extends State<_LinkedPatients> {
  final _searchController = TextEditingController();
  String _query = '';
  _LinkedPatientsSort _sort = _LinkedPatientsSort.dicomId;
  bool _ascending = true;
  bool _showDeleted = true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<MapEntry<String, String>> _entries() {
    final entries = dicomCtrl.linkedPatients.entries.where((entry) {
      final patient = patients.get(entry.value);
      if (!_showDeleted && patient == null) return false;
      if (_query.isEmpty) return true;
      final query = _query.toLowerCase();
      return entry.key.toLowerCase().contains(query) ||
          (patient?.title.toLowerCase().contains(query) ?? false) ||
          entry.value.toLowerCase().contains(query);
    }).toList();

    int compare(MapEntry<String, String> a, MapEntry<String, String> b) {
      final aPatient = patients.get(a.value);
      final bPatient = patients.get(b.value);
      final result = switch (_sort) {
        _LinkedPatientsSort.dicomId =>
          a.key.toLowerCase().compareTo(b.key.toLowerCase()),
        _LinkedPatientsSort.patient => (aPatient?.title ??
                txt('dicomPatientDeleted'))
            .toLowerCase()
            .compareTo(
                (bPatient?.title ?? txt('dicomPatientDeleted')).toLowerCase()),
        _LinkedPatientsSort.files => dicomLinks
            .importedFileCountFor(a.key)
            .compareTo(dicomLinks.importedFileCountFor(b.key)),
        _LinkedPatientsSort.status =>
          (aPatient == null ? 1 : 0).compareTo(bPatient == null ? 1 : 0),
      };
      return _ascending ? result : -result;
    }

    entries.sort(compare);
    return entries;
  }

  void _toggleSort(_LinkedPatientsSort column) {
    setState(() {
      if (_sort == column) {
        _ascending = !_ascending;
      } else {
        _sort = column;
        _ascending = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: dicomLinks.version.stream,
      builder: (context, snapshot) {
        final theme = FluentTheme.of(context);
        final entries = _entries();
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextBox(
                      controller: _searchController,
                      onChanged: (value) => setState(() => _query = value),
                      placeholder: txt('dicomSearchLinkedPatients'),
                      prefix: const Padding(
                        padding: EdgeInsetsDirectional.only(start: 8),
                        child: Icon(FluentIcons.search, size: 14),
                      ),
                      suffix: _query.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(FluentIcons.clear, size: 12),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _query = '');
                              },
                            ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ToggleButton(
                    checked: _showDeleted,
                    onChanged: (value) => setState(() => _showDeleted = value),
                    child: Txt(txt('dicomShowDeletedLinks')),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                Expanded(
                    child: _LinkedHeaderCell(
                  label: txt('dicomPatientId'),
                  active: _sort == _LinkedPatientsSort.dicomId,
                  ascending: _ascending,
                  onPressed: () => _toggleSort(_LinkedPatientsSort.dicomId),
                )),
                Expanded(
                    child: _LinkedHeaderCell(
                  label: txt('patient'),
                  active: _sort == _LinkedPatientsSort.patient,
                  ascending: _ascending,
                  onPressed: () => _toggleSort(_LinkedPatientsSort.patient),
                )),
                SizedBox(
                  width: 100,
                  child: _LinkedHeaderCell(
                    label: txt('dicomImportedFiles'),
                    active: _sort == _LinkedPatientsSort.files,
                    ascending: _ascending,
                    onPressed: () => _toggleSort(_LinkedPatientsSort.files),
                  ),
                ),
                SizedBox(
                  width: 92,
                  child: _LinkedHeaderCell(
                    label: txt('status'),
                    active: _sort == _LinkedPatientsSort.status,
                    ascending: _ascending,
                    onPressed: () => _toggleSort(_LinkedPatientsSort.status),
                  ),
                ),
                const SizedBox(width: 36),
              ],
            ),
            Container(
              height: 1,
              color: theme.resources.dividerStrokeColorDefault,
            ),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Text(
                  dicomCtrl.linkedPatients.isEmpty
                      ? txt('dicomNoLinks')
                      : txt('dicomNoMatchingLinks'),
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    color: theme.resources.textFillColorSecondary,
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return _LinkedPatientRow(
                      dicomId: entry.key,
                      apexoId: entry.value,
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

enum _LinkedPatientsSort { dicomId, patient, files, status }

class _LinkedHeaderCell extends StatelessWidget {
  const _LinkedHeaderCell({
    required this.label,
    required this.active,
    required this.ascending,
    required this.onPressed,
  });

  final String label;
  final bool active;
  final bool ascending;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return IconButton(
      onPressed: onPressed,
      icon: Row(
        children: [
          if (active)
            Icon(
              ascending ? FluentIcons.sort_up : FluentIcons.sort_down,
              size: 12,
              color: theme.accentColor,
            ),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.start,
              style: TextStyle(
                fontSize: 12,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                color: active
                    ? theme.accentColor
                    : theme.resources.textFillColorSecondary,
              ),
            ),
          ),
        ],
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
      // Keep the periodic timer in sync with the configured folders: start it
      // when there is now something to watch and auto-import is on, stop it
      // when the folders were all removed. Then scan immediately so the new
      // folders are reflected without waiting for the next tick.
      if (dicomCtrl.autoImport && dicomCtrl.watchDirs.isNotEmpty) {
        dicomCtrl.startPeriodicScan();
      } else {
        dicomCtrl.stopPeriodicScan();
      }
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

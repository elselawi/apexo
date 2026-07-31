import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/features/dicom/dicom_auto_import_toggle.dart';
import 'package:apexo/features/dicom/dicom_dir_manager.dart';
import 'package:apexo/features/settings/applies_to_indicator.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/dicom/persistence/dicom_linked_store.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// DICOM / RVG sensor settings section (Phase 2).
///
/// Windows-only (RVG sensor software is Windows-only). Gated behind
/// `Platform.isWindows && !kIsWeb` in the parent settings screen, so other
/// platforms never see this section.
///
/// Shows:
///   - Directory picker for the RVG watch folder (`globalSettings.dicomWatchDir`)
///   - Auto-import toggle (`globalSettings.dicomAutoImport`)
///   - Count of linked patients + imported files
///   - "Reset viewer preferences" button (clears `localSettings.dicomViewerPrefs`)
class DicomSettings extends StatefulWidget {
  const DicomSettings({super.key});

  @override
  State<DicomSettings> createState() => _DicomSettingsState();
}

class _DicomSettingsState extends State<DicomSettings> {
  int _importedCount = 0;

  @override
  void initState() {
    super.initState();
    _refreshImportedCount();
  }

  Future<void> _refreshImportedCount() async {
    final count = dicomLinks.importedCount;
    if (mounted) setState(() => _importedCount = count);
  }

  @override
  Widget build(BuildContext context) {
    // Streams: globalSettings (for watch dir + auto-import + links) and
    // localSettings (for viewer prefs). Re-renders when either changes.
    return MStreamBuilder(
      streams: [
        globalSettings.observableMap.stream,
        localSettings.stream,
      ],
      builder: (context, _) {
        final linkedCount = dicomLinks.linkedCount;
        final hasViewerPrefs = localSettings.dicomViewerPrefs.isNotEmpty;

        return Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: Expander(
            leading: const Icon(FluentIcons.generic_scan),
            header: Txt(txt("dicomSettings")),
            trailing: const AppliesToIndicator(scope: Scope.app),
            contentPadding: const EdgeInsets.all(10),
            content: SizedBox(
              width: 450,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Watch directory ──
                  InfoBar(
                    title: Txt(txt("dicomWatchDir")),
                    severity: InfoBarSeverity.info,
                    content: Txt(txt("dicomWatchDir_desc")),
                  ),
                  const SizedBox(height: 10),
                  DicomDirectoryManager(
                    dirs: globalSettings.dicomWatchDirs,
                    onChanged: (dirs) {
                      globalSettings.dicomWatchDirs = dirs;
                    },
                  ),
                  const SizedBox(height: 20),

                  // ── Auto-import toggle ──
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Txt(txt("dicomAutoImport")),
                            const SizedBox(height: 2),
                            Text(
                              txt("dicomAutoImport_desc"),
                              style: const TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      // ignore: prefer_const_constructors
                      DicomAutoImportToggle(
                        updater: () => setState(() {}),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ── Stats ──
                  _StatRow(
                    icon: FluentIcons.people,
                    label: txt("dicomLinkedPatients"),
                    value: linkedCount.toString(),
                  ),
                  const SizedBox(height: 8),
                  _StatRow(
                    icon: FluentIcons.file_image,
                    label: txt("dicomImportedFiles"),
                    value: _importedCount.toString(),
                  ),
                  const SizedBox(height: 20),

                  // ── Reset viewer preferences ──
                  Row(
                    children: [
                      Button(
                        onPressed: hasViewerPrefs
                            ? () {
                                localSettings.dicomViewerPrefs = "";
                                localSettings.notifyAndPersist();
                                setState(() {});
                              }
                            : null,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(FluentIcons.refresh, size: 16),
                            const SizedBox(width: 8),
                            Txt(txt("dicomResetViewerPrefs")),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (!hasViewerPrefs)
                        Text(
                          txt("dicomViewerPrefsDefault"),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.withAlpha(180),
                          ),
                        ),
                    ],
                  ),
                ]
                    .map((e) => [e, const SizedBox(height: 5)])
                    .expand((e) => e)
                    .toList(),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey.withAlpha(180)),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 13)),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

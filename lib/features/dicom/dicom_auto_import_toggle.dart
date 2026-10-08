import 'package:apexo/features/dicom/dicom_controller.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';

class DicomAutoImportToggle extends StatelessWidget {
  const DicomAutoImportToggle({
    super.key,
    required this.updater,
  });
  final VoidCallback updater;

  @override
  Widget build(BuildContext context) {
    return ToggleSwitch(
      key: WK.dicomAutoImportToggle,
      checked: globalSettings.dicomAutoImport,
      onChanged: (v) {
        globalSettings.dicomAutoImport = v;
        // The periodic timer has to mirror the toggle. It may not be running
        // yet (e.g. the watch dirs were empty at login, or this is the first
        // time auto-import was enabled), so start it when turning on and stop
        // it otherwise. `startPeriodicScan` no-ops if dirs are still empty;
        // the directory manager starts it once a folder is added.
        if (v) {
          dicomCtrl.startPeriodicScan();
        } else {
          dicomCtrl.stopPeriodicScan();
        }
        updater();
      },
    );
  }
}

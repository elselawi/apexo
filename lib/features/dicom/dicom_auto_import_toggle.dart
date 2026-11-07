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
        // The timer mirrors the toggle: start it when enabling, stop it otherwise.
        // `startPeriodicScan` no-ops while the watch dirs are empty.
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

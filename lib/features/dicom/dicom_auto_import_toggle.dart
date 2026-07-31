import 'package:apexo/features/settings/settings_stores.dart';
import 'package:fluent_ui/fluent_ui.dart';

class DicomAutoImportToggle extends StatelessWidget {
  final VoidCallback updater;
  const DicomAutoImportToggle({
    super.key,
    required this.updater,
  });

  @override
  Widget build(BuildContext context) {
    return ToggleSwitch(
      checked: globalSettings.dicomAutoImport,
      onChanged: (v) {
        globalSettings.dicomAutoImport = v;
        updater();
      },
    );
  }
}

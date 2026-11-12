import 'package:apexo/common_widgets/app_combo_box.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';

class LanguagePicker extends StatelessWidget {
  const LanguagePicker({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return AppComboBox<String>(
      key: WK.loginLangComboBox,
      value: localSettings.selectedLocale.toString(),
      items: locale.list
          .map((e) => ComboBoxItem(
              value: locale.list.indexOf(e).toString(),
              key: Key(e.$code),
              child: Txt(e.$name)))
          .toList(),
      onChanged: (indexString) {
        localSettings.selectedLocale = int.parse(indexString ?? "0");
        localSettings.notifyAndPersist();
      },
    );
  }
}

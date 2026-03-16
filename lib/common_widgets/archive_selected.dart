import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/dialogs/close_dialog_button.dart';
import 'package:apexo/core/store.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/common_widgets/datatable.dart';
import 'package:apexo/utils/flyout_focus_fix.dart';
import 'package:fluent_ui/fluent_ui.dart';

final flyoutController = FlyoutController();
DataTableAction archiveSelected(Store store) {
  return DataTableAction(
    callback: (ids) async {
      if (ids.isEmpty) return;
      await flyoutFocusFix(null);
      flyoutController.showFlyout(builder: (context) {
        return FlyoutContent(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Txt("${txt("sureArchiveSelected")} (${ids.length})"),
              const SizedBox(height: 12.0),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton(
                    style: filledButtonStyle(Colors.warningPrimaryColor),
                    onPressed: () {
                      Flyout.of(context).close();
                      for (var id in ids) {
                        store.archive(id);
                      }
                    },
                    child: Row(
                      children: [
                        const Icon(FluentIcons.archive, size: 16),
                        const SizedBox(width: 5),
                        Txt(txt("archive")),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  const CloseButtonInDialog(),
                ],
              ),
            ],
          ),
        );
      });
    },
    icon: FluentIcons.archive,
    child: FlyoutTarget(
        controller: flyoutController, child: Txt(txt("archiveSelected"))),
  );
}

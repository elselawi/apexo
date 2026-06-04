import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/no_items_found.dart';
import 'package:apexo/features/network_actions/network_actions_controller.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/utils/flyout_focus_fix.dart';
import 'package:fluent_ui/fluent_ui.dart';

final FlyoutController errorsFlyoutController = FlyoutController();

showErrorsFlyout() async {
  await flyoutFocusFix(null);
  errorsFlyoutController.showFlyout(
    barrierColor: Colors.transparent,
    barrierDismissible: true,
    dismissWithEsc: true,
    builder: (ctx) {
      return FlyoutContent(
        useAcrylic: false,
        constraints: const BoxConstraints(maxWidth: 350, maxHeight: 400),
        child: networkActions.errors.isEmpty
            ? const NoItemsFound()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: Row(
                      children: [
                        Text(
                          txt("errors"),
                          style: FluentTheme.of(ctx).typography.bodyStrong,
                        ),
                      ],
                    ),
                  ),
                  const Divider(),
                  // Error list
                  Expanded(
                    child: ListView(
                      children: networkActions.errors.map((error) {
                        return Container(
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: networkActions.errors.last.message ==
                                        error.message
                                    ? Colors.transparent
                                    : FluentTheme.of(ctx)
                                        .inactiveColor
                                        .withValues(alpha: 0.2),
                              ),
                            ),
                          ),
                          width: 330,
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Colors.red,
                                      borderRadius: BorderRadius.circular(40),
                                    ),
                                    child: const Icon(FluentIcons.error_badge,
                                        color: Colors.white, size: 12),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      txt(error.when),
                                      style: FluentTheme.of(ctx)
                                          .typography
                                          .bodyStrong,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (error.count > 1)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.red.withAlpha(30),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        "×${error.count}",
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.red,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Padding(
                                padding: const EdgeInsets.only(left: 26),
                                child: Text(
                                  error.message,
                                  style: FluentTheme.of(ctx).typography.caption,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  // Reconnect button at the bottom
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: Button(
                        style: filledButtonStyle(Colors.blue),
                        onPressed: () {
                          errorsFlyoutController.close();
                          networkActions.performReconnect();
                        },
                        child: ButtonContent(
                          WindowsIcons.repair,
                          txt("reconnect"),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      );
    },
  );
}

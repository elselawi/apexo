import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/features/login/login_controller.dart';
import 'package:apexo/features/network_actions/network_actions_controller.dart';
import 'package:apexo/common_widgets/transitions/rotate.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/network.dart';
import 'package:fluent_ui/fluent_ui.dart';

class NetworkActions extends StatelessWidget {
  const NetworkActions({super.key});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(3),
      child: MStreamBuilder(
          streams: [
            networkActions.isSyncing.stream,
            loginCtrl.proceededOffline.stream,
            network.isOnline.stream,
            localSettings.stream,
          ],
          builder: (context, _) {
            return Wrap(
              children: [
                ...networkActions.actions.where((action) => action.hidden != true).map(
                      (action) => Container(
                        margin: const EdgeInsets.only(left: 3, top: 7),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            _buildActionIcon(action),
                            if (action.badge != null) _buildBadge(action),
                          ],
                        ),
                      ),
                    )
              ],
            );
          }),
    );
  }

  Container _buildActionIcon(NetworkAction action) {
    return Container(
      margin: action.badge != null ? const EdgeInsets.only(right: 6) : null,
      child: RotatingWrapper(
        key: Key(action.hashCode.toString()),
        rotate: action.animate == true && action.processing == true,
        child: Tooltip(
          message: action.tooltip,
          child: IconButton(
            icon: action.icon,
            onPressed: action.onPressed,
            iconButtonMode: IconButtonMode.large,
            style: ButtonStyle(
                shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(50))),
                iconSize: WidgetStateProperty.all(18),
                foregroundColor: WidgetStatePropertyAll(action.processing ?? false ? Colors.white : null),
                backgroundColor:
                    WidgetStatePropertyAll(action.processing ?? false ? action.activeColor : Colors.transparent)),
          ),
        ),
      ),
    );
  }

  Positioned _buildBadge(NetworkAction action) {
    return Positioned(
      bottom: 0,
      right: 0,
      child: Container(
        height: 14,
        width: 14,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(50),
          boxShadow: kElevationToShadow[2],
        ),
        child: Center(child: Text(action.badge ?? "", style: const TextStyle(fontSize: 10, color: Colors.grey))),
      ),
    );
  }
}

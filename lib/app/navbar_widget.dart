import 'package:apexo/app/routes.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/utils/flyout_focus_fix.dart';
import 'package:fluent_ui/fluent_ui.dart';

class BottomNavBar extends StatelessWidget {
  const BottomNavBar({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 0,
      height: 66,
      width: MediaQuery.of(context).size.width,
      child: Container(
        decoration: BoxDecoration(
          color: FluentTheme.of(context).menuColor,
          boxShadow: [
            BoxShadow(
              offset: const Offset(0.0, -2.0), // Cast shadow upwards
              blurRadius: 15.0,
              spreadRadius: 1.0,
              color: Colors.black.withOpacity(0.05), // Slight, elegant shadow
            ),
          ],
          border: Border(
            top: BorderSide(
              color:
                  FluentTheme.of(context).resources.dividerStrokeColorDefault,
              width: 0.5,
            ),
          ),
        ),
        child: StreamBuilder(
          stream: routes.currentRouteIndex.stream,
          builder: (context, snapshot) {
            return LayoutBuilder(
              builder: (context, constraints) {
                final availableWidth = constraints.maxWidth;
                final allRoutes = routes.allRoutes;
                final int totalRoutes = allRoutes.length;

                // Make it more compact to fit slightly more items
                const double minItemWidth = 52.0;
                int maxVisibleItems = (availableWidth / minItemWidth).floor();

                var visibleRoutes = allRoutes;
                var overflowRoutes = [];
                bool showMore = false;

                if (maxVisibleItems < totalRoutes) {
                  showMore = true;
                  int visibleCount =
                      maxVisibleItems - 1; // Leave space for 'More'
                  if (visibleCount < 1) visibleCount = 1; // Sanity check

                  visibleRoutes = allRoutes.sublist(0, visibleCount);
                  overflowRoutes = allRoutes.sublist(visibleCount);
                }

                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ...visibleRoutes.map((r) => Expanded(
                          child: BottomNavBarButton(
                            icon: r.icon,
                            identifier: r.identifier,
                            title: r.navbarTitle,
                            active:
                                r.identifier == routes.currentRoute.identifier,
                          ),
                        )),
                    if (showMore)
                      Container(
                        width: 1,
                        height:
                            24, // Smaller height to look like a clean vertical divider
                        margin: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 16),
                        color: FluentTheme.of(context)
                            .resources
                            .dividerStrokeColorDefault
                            .withOpacity(0.1),
                      ),
                    if (showMore)
                      Expanded(
                        child: BottomNavBarMoreButton(
                          overflowRoutes: overflowRoutes,
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class BottomNavBarButton extends StatelessWidget {
  final String title;
  final IconData icon;
  final String identifier;
  final bool active;
  const BottomNavBarButton({
    super.key,
    required this.title,
    required this.icon,
    required this.identifier,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final color = active
        ? Colors.blue
        : (theme.typography.body?.color?.withOpacity(0.6) ?? Colors.grey);

    return HoverButton(
      onPressed: () => routes.navigate(identifier),
      builder: (context, states) {
        final isHovered = states.isHovered;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutQuint,
          decoration: BoxDecoration(
            color: active
                ? Colors.blue.withOpacity(0.08) // Indicative active pill
                : (isHovered
                    ? theme.resources.subtleFillColorSecondary
                    : Colors.transparent),
            borderRadius: BorderRadius.circular(8),
          ),
          margin: const EdgeInsets.symmetric(horizontal: 2.0, vertical: 4.0),
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedScale(
                scale: states.isPressed ? 0.9 : (active ? 1.1 : 1.0),
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutBack,
                child: Icon(
                  icon,
                  color: color,
                  size: 20,
                ),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2.0),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                      color: color,
                      fontFamily: theme.typography.body?.fontFamily,
                    ),
                    child: Text(title),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class BottomNavBarMoreButton extends StatefulWidget {
  final List overflowRoutes;
  const BottomNavBarMoreButton({super.key, required this.overflowRoutes});

  @override
  State<BottomNavBarMoreButton> createState() => _BottomNavBarMoreButtonState();
}

class _BottomNavBarMoreButtonState extends State<BottomNavBarMoreButton> {
  final bottomNavFlyoutController = FlyoutController();

  @override
  void dispose() {
    bottomNavFlyoutController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    // Highlight the "More" button if the currently active route is inside it
    final isActive = widget.overflowRoutes
        .any((r) => r.identifier == routes.currentRoute.identifier);
    final color = isActive
        ? Colors.blue
        : (theme.typography.body?.color?.withValues(alpha: .6) ?? Colors.grey);

    return FlyoutTarget(
      controller: bottomNavFlyoutController,
      child: HoverButton(
        onPressed: () async {
          await flyoutFocusFix(null);
          bottomNavFlyoutController.showFlyout(
            autoModeConfiguration: FlyoutAutoConfiguration(
              preferredMode: FlyoutPlacementMode.topCenter,
            ),
            barrierColor: Colors.transparent,
            builder: (context) {
              return MenuFlyout(
                items: widget.overflowRoutes.map((r) {
                  final isItemActive =
                      r.identifier == routes.currentRoute.identifier;
                  return MenuFlyoutItem(
                    text: Text(
                      r.navbarTitle,
                      style: TextStyle(
                        fontWeight:
                            isItemActive ? FontWeight.bold : FontWeight.normal,
                        color: isItemActive ? Colors.blue : null,
                      ),
                    ),
                    leading: Icon(
                      r.icon,
                      color: isItemActive ? Colors.blue : null,
                    ),
                    onPressed: () {
                      routes.navigate(r.identifier);
                      Flyout.of(context).close();
                    },
                  );
                }).toList(),
              );
            },
          );
        },
        builder: (context, states) {
          final isHovered = states.isHovered;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutQuint,
            decoration: BoxDecoration(
              color: isActive
                  ? Colors.blue.withOpacity(0.08)
                  : (isHovered
                      ? theme.resources.subtleFillColorSecondary
                      : Colors.transparent),
              borderRadius: BorderRadius.circular(8),
            ),
            margin: const EdgeInsets.symmetric(horizontal: 2.0, vertical: 4.0),
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedScale(
                  scale: states.isPressed ? 0.9 : (isActive ? 1.1 : 1.0),
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutBack,
                  child: Icon(
                    FluentIcons.more,
                    color: color,
                    size: 20,
                  ),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2.0),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight:
                            isActive ? FontWeight.w600 : FontWeight.w500,
                        color: color,
                        fontFamily: theme.typography.body?.fontFamily,
                      ),
                      child: Text(txt("more")),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

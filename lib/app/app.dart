import 'dart:async';
import 'dart:io';

import 'package:apexo/app/app_context.dart';
import 'package:apexo/app/optional_features.dart';
import 'package:apexo/app/routing/app_route.dart';
import 'package:apexo/app/navbar_widget.dart';
import 'package:apexo/app/nav_badges.dart';
import 'package:apexo/app/title_bar_safe_area.dart';
import 'package:apexo/common_widgets/app_menu_flyout.dart';
import 'package:apexo/ui/workspace/panel_screen.dart';
import 'package:apexo/ui/workspace/panel_width.dart';
import 'package:apexo/ui/workspace/panels_manager.dart';
import 'package:apexo/ui/workspace/close_all_button.dart';
import 'package:apexo/ui/workspace/windows_layout.dart';
import 'package:apexo/ui/workspace/window_defaults.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/booking/booking_session.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/app/routing/routes.dart';
import 'package:apexo/common_widgets/back_button.dart';
import 'package:apexo/common_widgets/dialogs/changelog_dialog.dart';
import 'package:apexo/common_widgets/dialogs/first_launch_dialog.dart';
import 'package:apexo/common_widgets/dialogs/new_version_dialog.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/ui/workspace/window_origin.dart';
import 'package:apexo/ui/workspace/windows_layer.dart';
import 'package:apexo/ui/workspace/windows_manager.dart';
import 'package:apexo/ui/design/app_theme.dart';
import 'package:apexo/ui/design/fluent_materials.dart';
import 'package:apexo/ui/design/mica_backdrop.dart';
import 'package:apexo/features/network_actions/network_actions_widget.dart';
import 'package:apexo/features/patient_side/patient_side_screen.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/launch.dart';
import 'package:apexo/services/localization/flutter_delegates.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/features/login/login_screen.dart';
import 'package:apexo/common_widgets/current_account.dart';
import 'package:apexo/common_widgets/logo.dart';
import 'package:apexo/services/patient_side.dart';
import 'package:apexo/services/version.dart';
import 'package:apexo/services/changelog.dart';
import 'package:apexo/utils/app_flyout_controller.dart';
import 'package:apexo/utils/flyout_focus_fix.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

/// One cached key per route, so a screen keeps its state when the shell
/// rebuilds. The key is a `const` enum value, so identity holds across them.
final _bodyKeys = <AppRoute, GlobalKey>{};
GlobalKey _bodyKeyFor(AppRoute route) =>
    _bodyKeys.putIfAbsent(route, () => GlobalObjectKey(route));

/// App themes.
///
/// Both brightnesses come from one builder; see `ui/design/app_theme.dart`.
FluentThemeData _fluentTheme({required bool dark}) =>
    appTheme(brightness: dark ? Brightness.dark : Brightness.light);

class ApexoApp extends StatelessWidget {
  const ApexoApp({super.key});

  @override
  StatelessElement createElement() {
    unawaited(PatientSide.fromHref());
    Future.delayed(const Duration(milliseconds: 1000), () {
      unawaited(showDialogsIfNeeded());
    });
    return super.createElement();
  }

  @override
  Widget build(BuildContext context) {
    // Global recorder: a menu's tap lands in the navigator overlay, so a local
    // listener would never see it.
    WindowOrigin.install();
    return StreamBuilder(
        stream: localSettings.stream,
        builder: (context, snapshot) {
          return FluentApp(
            title: "Apexo",
            key: WK.fluentApp,
            // The window itself is the backdrop; a root fill would cover it.
            color: Colors.transparent,
            locale: Locale(locale.s.$code),
            localizationsDelegates: appLocalizationsDelegates,
            theme: _fluentTheme(
                dark: localSettings.selectedTheme == ThemeMode.dark),
            home: CupertinoTheme(
              data: localSettings.selectedTheme == ThemeMode.dark
                  ? const CupertinoThemeData(brightness: Brightness.dark)
                  : const CupertinoThemeData(brightness: Brightness.light),
              child: FluentTheme(
                data: _fluentTheme(
                    dark: localSettings.selectedTheme == ThemeMode.dark),
                child: MStreamBuilder(
                  streams: [
                    version.isOutdated.stream,
                    version.current.stream,
                    launch.isFirstLaunch.stream,
                    launch.open.stream,
                    routes.showBottomNav.stream,
                    PanelsManager.active.stream,
                    PanelsManager.minimize.stream
                  ],
                  builder: (BuildContext context, _) {
                    bContext = context;
                    return MicaBackdrop(
                      child: SafeArea(
                        top: false,
                        left: false,
                        right: false,
                        bottom: !kIsWeb && Platform.isAndroid,
                        child: ScaffoldPage(
                          padding: EdgeInsets.zero,
                          backgroundColor: Colors.transparent,
                          resizeToAvoidBottomInset: true,
                          content: Stack(
                            fit: StackFit.expand,
                            children: [
                              buildAppLayout(),
                              if (routes.showBottomNav() &&
                                  PanelsManager.active().isEmpty &&
                                  launch.open() == Open.staff)
                                const BottomNavBar()
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        });
  }

  // Guards against a second raise: both startup and session start run the check.
  static bool _changelogShown = false;

  /// Shows the changelog and welcome dialogs if this launch owes one. Static
  /// because startup's session callback in `main` also calls it.
  static Future<void> showDialogsIfNeeded() async {
    await version.loadCurrentVersion();

    // Show changelog dialog when the app version changes (post-update).
    if (!_changelogShown &&
        localSettings.lastSeenVersion != version.current() &&
        version.current() != "0.0.0" &&
        bContext.mounted) {
      _changelogShown = true;
      final entry = await changelog.forVersion(version.current());
      localSettings.lastSeenVersion = version.current();
      localSettings.notifyAndPersist();

      if (entry != null && entry.changes.isNotEmpty && bContext.mounted) {
        unawaited(showChangelogDialog(bContext, entry: entry));
      }
    }

    // Only macOS gets the update prompt; the stores update the other platforms.
    if (version.needsUpdateNotification &&
        version.isOutdated() &&
        !launch.dialogShown() &&
        bContext.mounted) {
      launch.dialogShown(true);

      unawaited(showDialog(
        barrierDismissible: true,
        dismissWithEsc: true,
        context: bContext,
        builder: (context) => NewVersionDialog(
          downloadLink: version.downloadLink,
        ),
      ));
    }

    // Show first launch dialog if this is the first time the app is launched
    if (launch.isFirstLaunch() && bContext.mounted && !launch.dialogShown()) {
      launch.dialogShown(true);
      unawaited(showDialog(
        barrierDismissible: true,
        dismissWithEsc: true,
        context: bContext,
        builder: (BuildContext context) => const FirstLaunchDialog(),
      ));
    }
  }

  Widget buildAppLayout() {
    return MStreamBuilder(
      streams: [
        launch.open.stream,
        routes.currentRoute.stream,
        PanelsManager.active.stream,
        booking.ready.stream,
        ...optionalFeatureStreams,
      ],
      key: WK.builder,
      builder: (context, _) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (_, __) {
          if (launch.layoutWidth < kWindowsBreakpoint) {
            // Back dismisses in order: sheet, then visit, then panel.
            if (WindowsManager.dismissSheet?.call() ?? false) return;
            final panel = PanelsManager.active().lastOrNull;
            if (panel != null &&
                panel.attached != null &&
                PanelsManager.minimize() == false) {
              // Detaching keeps the draft — nothing behind the visit is lost.
              panel.detach();
              return;
            }
            if (PanelsManager.active().isNotEmpty &&
                PanelsManager.minimize() == false) {
              PanelsManager.minimize(true);
              return;
            }
          }
          routes.goBack();
        },
        child: LayoutBuilder(builder: (context, constraints) {
          launch.layoutWidth = constraints.maxWidth;
          final hideSidePanel =
              PanelsManager.active().isEmpty || launch.open() != Open.staff;
          return Container(
            color: Colors.transparent,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildPositionedMainScreen(constraints, hideSidePanel, context),
                if (PanelsManager.active().isNotEmpty &&
                    PanelsManager.minimize() == false &&
                    constraints.maxWidth < kWindowsBreakpoint)
                  ModalBarrier(
                    color: FluentTheme.of(context)
                        .resources
                        .smokeFillColorDefault
                        .withValues(alpha: 0.4),
                    onDismiss: () => PanelsManager.minimize(true),
                  ),
                _buildPositionedPanel(context, constraints, hideSidePanel),
                WindowsLayer(
                  visible: launch.open() == Open.staff,
                  screenWidth: constraints.maxWidth,
                  refreshStreams: [
                    patients.observableMap.stream,
                    appointments.observableMap.stream,
                  ],
                  defaults: WindowDefaults(
                    read: () => localSettings.windowsPerKind,
                    write: (value) {
                      localSettings.windowsPerKind = value;
                      localSettings.notifyAndPersist();
                    },
                  ),
                ),
                // Must stay after the windows in the Stack to draw above them.
                if (launch.open() == Open.staff)
                  CloseAllButton(
                    screenWidth: constraints.maxWidth,
                    panelWidth:
                        hideSidePanel ? 0 : _activePanelWidth(constraints),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  double _activePanelWidth(BoxConstraints constraints) =>
      computePanelWidth(screenWidth: constraints.maxWidth);

  Widget _buildPositionedMainScreen(
      BoxConstraints constraints, bool hideSidePanel, BuildContext context) {
    final hasKeyboard = MediaQuery.of(context).viewInsets.bottom > 0;
    final panelWidth = _activePanelWidth(constraints);
    return AnimatedPositioned(
      duration: hasKeyboard ? Duration.zero : const Duration(milliseconds: 300),
      top: 0,
      left: locale.s.$direction == TextDirection.rtl ? null : 0,
      right: locale.s.$direction == TextDirection.rtl ? 0 : null,
      height: constraints.maxHeight,
      width: (!hideSidePanel) && constraints.maxWidth >= kWindowsBreakpoint
          ? constraints.maxWidth - (panelWidth + 5)
          : constraints.maxWidth,
      child: TitleBarSafeArea(
        child: NavigationView(
          titleBar: TitleBar(
            isBackButtonVisible:
                routes.canGoBack && launch.open() == Open.staff,
            backButton: const BackButton(),
            height: 40,
            // `TitleBar` keeps a 48 px drag region after `endHeader` for the
            // window's caption buttons, which the OS draws here, so the actions
            // go in the caption slot to stay flush with the edge.
            captionControls: const NetworkActions(key: WK.globalActions),
            // ignore: prefer_const_constructors
            title: NavScreenTitle(),
          ),
          onDisplayModeChanged: (mode) {
            if (mode == PaneDisplayMode.minimal &&
                constraints.maxWidth < kWindowsBreakpoint) {
              routes.showBottomNav(true);
            } else {
              routes.showBottomNav(false);
            }
          },
          content: launch.open() == Open.login
              // ignore: prefer_const_constructors
              ? LoginScreen()
              : launch.open() == Open.patient
                  ? const PatientSideScreen()
                  : null,
          pane: launch.open() == Open.staff
              ? NavigationPane(
                  header: const Column(
                    children: [
                      AppLogo(compact: true),
                      CurrentAccount(),
                    ],
                  ),
                  selected: routes.currentIndex,
                  displayMode: PaneDisplayMode.auto,
                  toggleable: false,
                  // The pane swaps bodies by index, so each is pre-built and
                  // keyed to keep its element and state across the swap.
                  items: List<NavigationPaneItem>.from(routes.visibleRoutes.map(
                    (route) => PaneItem(
                      key: Key("${route.id}_screen_button"),
                      icon: Icon(route.icon),
                      infoBadge: navBadgeFor(route),
                      body: KeyedSubtree(
                        key: _bodyKeyFor(route),
                        child: _ScreenLayer(
                          child: Padding(
                            padding: EdgeInsets.only(
                                bottom: (routes.showBottomNav() &&
                                        constraints.maxWidth <
                                            kWindowsBreakpoint)
                                    ? 66
                                    : 0),
                            child: route.buildScreen(),
                          ),
                        ),
                      ),
                      title: Txt(route.title),
                      onTap: () => routes.navigate(route),
                    ),
                  )),
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildPositionedPanel(
      BuildContext context, BoxConstraints constraints, bool hideSidePanel) {
    final minimized =
        PanelsManager.minimize() && constraints.maxWidth < kWindowsBreakpoint;
    final fillsWidth = !minimized && constraints.maxWidth < 490;
    final hasKeyboard = MediaQuery.of(context).viewInsets.bottom > 0;
    final panelWidth = _activePanelWidth(constraints);
    return AnimatedPositioned(
      duration: hasKeyboard ? Duration.zero : const Duration(milliseconds: 300),
      width: panelWidth,
      height: minimized ? 100 : constraints.maxHeight,
      top: minimized ? null : 0,
      bottom: minimized ? -20 : null,
      left: locale.s.$direction == TextDirection.ltr
          ? null
          : (hideSidePanel ? -(panelWidth + 50) : 0),
      right: locale.s.$direction == TextDirection.ltr
          ? (hideSidePanel ? -(panelWidth + 50) : 0)
          : null,
      child: hideSidePanel
          ? const SizedBox()
          : SafeArea(
              top: minimized ? false : !fillsWidth,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                switchInCurve: Curves.easeInCubic,
                switchOutCurve: Curves.easeOutCubic,
                transitionBuilder: (Widget child, Animation<double> animation) {
                  final slideAnimation = Tween<Offset>(
                    begin: const Offset(0.25, 0),
                    end: Offset.zero,
                  ).animate(animation);
                  return SlideTransition(
                    position: slideAnimation,
                    child: child,
                  );
                },
                child: PanelScreen(
                  key: Key(PanelsManager.active().last.identifier),
                  layoutWidth: constraints.maxWidth,
                  panel: PanelsManager.active().last,
                ),
              ),
            ),
    );
  }
}

/// The screen area of the shell: the translucent layer WinUI stacks on Mica,
/// with the hairline that separates it from the pane.
class _ScreenLayer extends StatelessWidget {
  const _ScreenLayer({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final materials = FluentMaterials.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: materials.layer,
        border: BorderDirectional(
          start: BorderSide(
            color: materials.divider,
            width: FluentMaterials.hairlineWidth,
          ),
        ),
      ),
      child: child,
    );
  }
}

class NavScreenTitle extends StatefulWidget {
  const NavScreenTitle({super.key});

  @override
  State<NavScreenTitle> createState() => _NavScreenTitleState();
}

class _NavScreenTitleState extends State<NavScreenTitle> {
  final controller = AppFlyoutController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FlyoutTarget(
      controller: controller,
      child: GestureDetector(
        onTap: () async {
          if (launch.open() != Open.staff) return;
          await flyoutFocusFix(context);
          unawaited(controller.showFlyout(builder: (ctx) {
            return AppMenuFlyout(
              items: routes.visibleRoutes.map((route) {
                return MenuFlyoutItem(
                  leading: Icon(route.icon),
                  selected: route == routes.currentRoute(),
                  text: Text(route.title),
                  onPressed: () {
                    controller.close<void>();
                    routes.navigate(route);
                  },
                );
              }).toList(),
            );
          }));
        },
        child: _TitleButton(
          icon: launch.open() == Open.staff
              ? routes.currentRoute().icon
              : WindowsIcons.lock,
          label: launch.open() == Open.staff
              ? routes.currentRoute().title
              : launch.open() == Open.patient
                  ? txt("patientSide")
                  : txt("login"),
          expandable: launch.open() == Open.staff,
        ),
      ),
    );
  }
}

/// The app's name in the title bar, the way WinUI draws a title: plain text,
/// no pill, and a chevron where a menu is behind it.
class _TitleButton extends StatefulWidget {
  const _TitleButton({
    required this.icon,
    required this.label,
    required this.expandable,
  });

  final IconData icon;

  /// A localization key; translated here, at draw time.
  final String label;

  final bool expandable;

  @override
  State<_TitleButton> createState() => _TitleButtonState();
}

class _TitleButtonState extends State<_TitleButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final materials = FluentMaterials.of(context);
    return MouseRegion(
      cursor: widget.expandable ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: theme.fastAnimationDuration,
        curve: theme.animationCurve,
        padding: const EdgeInsetsDirectional.fromSTEB(8, 3, 10, 3),
        decoration: BoxDecoration(
          color: _hovered && widget.expandable
              ? materials.hover
              : Colors.transparent,
          borderRadius: FluentMaterials.controlRadius,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            Icon(
              widget.icon,
              size: 14,
              color: materials.textSecondary,
            ),
            Txt(
              widget.label,
              style: theme.typography.bodyStrong?.copyWith(fontSize: 13),
            ),
            if (widget.expandable)
              Icon(
                FluentIcons.chevron_down,
                size: 10,
                color: materials.textTertiary,
              ),
          ],
        ),
      ),
    );
  }
}

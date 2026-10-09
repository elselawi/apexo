import 'dart:async';
import 'dart:io';

import 'package:apexo/app/routing/app_route.dart';
import 'package:apexo/app/navbar_widget.dart';
import 'package:apexo/app/panels/panel_screen.dart';
import 'package:apexo/app/panels/panels_manager.dart';
import 'package:apexo/app/routing/routes.dart';
import 'package:apexo/common_widgets/back_button.dart';
import 'package:apexo/common_widgets/dialogs/changelog_dialog.dart';
import 'package:apexo/common_widgets/dialogs/first_launch_dialog.dart';
import 'package:apexo/common_widgets/dialogs/new_version_dialog.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/features/network_actions/network_actions_widget.dart';
import 'package:apexo/features/patient_side/patient_side_screen.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/launch.dart';
import 'package:apexo/services/localization/en.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/features/login/login_screen.dart';
import 'package:apexo/common_widgets/current_account.dart';
import 'package:apexo/common_widgets/logo.dart';
import 'package:apexo/services/patient_side.dart';
import 'package:apexo/services/version.dart';
import 'package:apexo/services/changelog.dart';
import 'package:apexo/utils/flyout_focus_fix.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

late BuildContext bContext;

/// One cached [GlobalObjectKey] per route, so a screen keeps its element and
/// state (scroll offset, text controllers) when the shell rebuilds.
///
/// The key is the [AppRoute] itself — a `const` enum value, so [identical]
/// holds across rebuilds.
final _bodyKeys = <AppRoute, GlobalKey>{};
GlobalKey _bodyKeyFor(AppRoute route) =>
    _bodyKeys.putIfAbsent(route, () => GlobalObjectKey(route));

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
    return StreamBuilder(
        stream: localSettings.stream,
        builder: (context, snapshot) {
          return FluentApp(
            title: "Apexo",
            key: WK.fluentApp,
            locale: Locale(locale.s.$code),
            theme: localSettings.selectedTheme == ThemeMode.dark
                ? FluentThemeData.dark()
                : FluentThemeData.light(),
            home: CupertinoTheme(
              data: localSettings.selectedTheme == ThemeMode.dark
                  ? const CupertinoThemeData(brightness: Brightness.dark)
                  : const CupertinoThemeData(brightness: Brightness.light),
              child: FluentTheme(
                data: localSettings.selectedTheme == ThemeMode.dark
                    ? FluentThemeData.dark()
                    : FluentThemeData(),
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
                    return SafeArea(
                      top: false,
                      left: false,
                      right: false,
                      bottom: !kIsWeb && Platform.isAndroid,
                      child: ScaffoldPage(
                        padding: EdgeInsets.zero,
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
                    );
                  },
                ),
              ),
            ),
          );
        });
  }

  /// Set once the changelog dialog has been raised in this process.
  ///
  /// The check runs from **two** places now (startup's one-second timer and
  /// `login.activate`, which is what makes the welcome dialog reachable), and a
  /// second raise leaves two dialogs stacked — `upgrade 01` sets a stale
  /// `lastSeenVersion` itself, and the timer then raised a second changelog over
  /// the one the test was closing, so it waited 60s for `ContentDialog` to
  /// disappear. The device value alone is not enough of a guard: the *test* is
  /// allowed to make it stale.
  static bool _changelogShown = false;

  /// Shows the changelog / welcome dialogs if this launch owes one.
  ///
  /// **Static, because `login.activate` calls it too.** `createElement`'s
  /// one-second timer runs *before* the login that creates a clinic can set
  /// `launch.isFirstLaunch`, so the welcome dialog was unreachable: nothing
  /// re-checked the flag (`login 12`, a 180s wait for a dialog that could never
  /// come). Nothing here reads instance state — every value is a global — so a
  /// class-level function is enough, and the check is idempotent.
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

    // Show new version dialog only on macOS — all other platforms
    // (MS Store, Play Store, App Store) handle updates automatically.
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
        PanelsManager.active.stream
      ],
      key: WK.builder,
      builder: (context, _) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (_, __) {
          if (launch.layoutWidth < 710 &&
              PanelsManager.active().isNotEmpty &&
              PanelsManager.minimize() == false) {
            PanelsManager.minimize(true);
            return;
          }
          routes.goBack();
        },
        child: LayoutBuilder(builder: (context, constraints) {
          launch.layoutWidth = constraints.maxWidth;
          final hideSidePanel =
              PanelsManager.active().isEmpty || launch.open() != Open.staff;
          return Container(
            color: FluentTheme.of(context).menuColor,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildPositionedMainScreen(constraints, hideSidePanel, context),
                if (PanelsManager.active().isNotEmpty &&
                    PanelsManager.minimize() == false &&
                    constraints.maxWidth < 710)
                  ModalBarrier(
                    color: FluentTheme.of(context)
                        .menuColor
                        .withValues(alpha: 0.4),
                    onDismiss: () => PanelsManager.minimize(true),
                  ),
                _buildPositionedPanel(context, constraints, hideSidePanel),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildPositionedMainScreen(
      BoxConstraints constraints, bool hideSidePanel, BuildContext context) {
    final hasKeyboard = MediaQuery.of(context).viewInsets.bottom > 0;
    return AnimatedPositioned(
      duration: hasKeyboard ? Duration.zero : const Duration(milliseconds: 300),
      top: 0,
      left: locale.s.$direction == Direction.rtl ? null : 0,
      right: locale.s.$direction == Direction.rtl ? 0 : null,
      height: constraints.maxHeight,
      width: (!hideSidePanel) && constraints.maxWidth >= 710
          ? constraints.maxWidth - 355
          : constraints.maxWidth,
      child: Container(
        decoration: BoxDecoration(boxShadow: kElevationToShadow[6]),
        child: NavigationView(
          appBar: NavigationAppBar(
            leading: (routes.canGoBack && launch.open() == Open.staff)
                ? const BackButton()
                : null,
            automaticallyImplyLeading: false,
            height: 40,
            actions: const NetworkActions(key: WK.globalActions),
            // ignore: prefer_const_constructors
            title: NavScreenTitle(),
          ),
          onDisplayModeChanged: (mode) {
            if (mode == PaneDisplayMode.minimal && constraints.maxWidth < 710) {
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
                      AppLogo(),
                      CurrentAccount(),
                    ],
                  ),
                  selected: routes.currentIndex,
                  displayMode: PaneDisplayMode.auto,
                  toggleable: false,
                  // Every offered route's body is handed over up front (the pane
                  // swaps between them by index), and each is keyed so its
                  // element and state survive that swap.
                  items: List<NavigationPaneItem>.from(routes.visibleRoutes.map(
                    (route) => PaneItem(
                      key: Key("${route.id}_screen_button"),
                      icon: Icon(route.icon),
                      body: KeyedSubtree(
                        key: _bodyKeyFor(route),
                        child: Padding(
                          padding: EdgeInsets.only(
                              bottom: (routes.showBottomNav() &&
                                      constraints.maxWidth < 710)
                                  ? 66
                                  : 0),
                          child: route.buildScreen(),
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
    final minimized = PanelsManager.minimize() && constraints.maxWidth < 710;
    final hasKeyboard = MediaQuery.of(context).viewInsets.bottom > 0;
    return AnimatedPositioned(
      duration: hasKeyboard ? Duration.zero : const Duration(milliseconds: 300),
      width: (constraints.maxWidth < 490 && minimized)
          ? constraints.maxWidth
          : 350,
      height: minimized ? 100 : constraints.maxHeight,
      top: minimized ? null : 0,
      bottom: minimized ? -20 : null,
      left: locale.s.$direction == Direction.ltr
          ? null
          : (hideSidePanel ? -400 : 0),
      right: locale.s.$direction == Direction.ltr
          ? (hideSidePanel ? -400 : 0)
          : null,
      child: hideSidePanel
          ? const SizedBox()
          : SafeArea(
              top: minimized ? false : true,
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
                  layoutHeight: constraints.maxHeight,
                  layoutWidth: constraints.maxWidth,
                  panel: PanelsManager.active().last,
                ),
              ),
            ),
    );
  }
}

class NavScreenTitle extends StatefulWidget {
  const NavScreenTitle({super.key});

  @override
  State<NavScreenTitle> createState() => _NavScreenTitleState();
}

class _NavScreenTitleState extends State<NavScreenTitle> {
  final controller = FlyoutController();

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
            return MenuFlyout(
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
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(50),
            color: launch.open() == Open.staff
                ? Colors.white
                : Colors.grey.withValues(alpha: 0.6),
            border: Border.all(
                color: FluentTheme.of(context).inactiveColor.withAlpha(40)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 5,
            children: [
              Icon(
                launch.open() == Open.staff
                    ? routes.currentRoute().icon
                    : WindowsIcons.lock,
                color: Colors.grey,
              ),
              launch.open() == Open.staff
                  ? Txt(
                      routes.currentRoute().title,
                      style: const TextStyle(color: Colors.grey),
                    )
                  : launch.open() == Open.patient
                      ? Txt(
                          txt("patientSide"),
                          style: const TextStyle(color: Colors.grey),
                        )
                      : Txt(
                          txt("login"),
                          style: const TextStyle(color: Colors.grey),
                        )
            ],
          ),
        ),
      ),
    );
  }
}

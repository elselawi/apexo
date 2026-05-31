import 'dart:io';

import 'package:apexo/app/navbar_widget.dart';
import 'package:apexo/app/panel_widget.dart';
import 'package:apexo/app/routes.dart';
import 'package:apexo/common_widgets/back_button.dart';
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
import 'package:apexo/utils/flyout_focus_fix.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

late BuildContext bContext;

class ApexoApp extends StatelessWidget {
  const ApexoApp({super.key});

  @override
  StatelessElement createElement() {
    PatientSide.fromHref();
    Future.delayed(const Duration(milliseconds: 1000), () {
      showDialogsIfNeeded();
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
                    routes.panels.stream,
                    routes.minimizePanels.stream
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
                                routes.panels().isEmpty &&
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

  void showDialogsIfNeeded() async {
    await version.init();

    // Show new version dialog only on macOS — all other platforms
    // (MS Store, Play Store, App Store) handle updates automatically.
    if (version.needsUpdateNotification &&
        version.isOutdated() &&
        !launch.dialogShown() &&
        bContext.mounted) {
      launch.dialogShown(true);

      showDialog(
        barrierDismissible: true,
        dismissWithEsc: true,
        context: bContext,
        builder: (context) => NewVersionDialog(
          downloadLink: version.downloadLink,
        ),
      );
    }

    // Show first launch dialog if this is the first time the app is launched
    if (launch.isFirstLaunch() && bContext.mounted && !launch.dialogShown()) {
      launch.dialogShown(true);
      showDialog(
        barrierDismissible: true,
        dismissWithEsc: true,
        context: bContext,
        builder: (BuildContext context) => const FirstLaunchDialog(),
      );
    }
  }

  Widget buildAppLayout() {
    return MStreamBuilder(
      streams: [
        launch.open.stream,
        routes.currentRouteIndex.stream,
        routes.panels.stream
      ],
      key: WK.builder,
      builder: (context, _) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (_, __) {
          if (launch.layoutWidth < 710 &&
              routes.panels().isNotEmpty &&
              routes.minimizePanels() == false) {
            routes.minimizePanels(true);
            return;
          }
          routes.goBack();
        },
        child: LayoutBuilder(builder: (context, constraints) {
          launch.layoutWidth = constraints.maxWidth;
          final hideSidePanel =
              routes.panels().isEmpty || launch.open() != Open.staff;
          return Container(
            color: FluentTheme.of(context).menuColor,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildPositionedMainScreen(constraints, hideSidePanel, context),
                if (routes.panels().isNotEmpty &&
                    routes.minimizePanels() == false &&
                    constraints.maxWidth < 710)
                  ModalBarrier(
                    color: FluentTheme.of(context)
                        .menuColor
                        .withValues(alpha: 0.4),
                    onDismiss: () => routes.minimizePanels(true),
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
            leading: (routes.history.isNotEmpty && launch.open() == Open.staff)
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
                  selected: routes.currentRouteIndex(),
                  displayMode: PaneDisplayMode.auto,
                  toggleable: false,
                  items: List<NavigationPaneItem>.from(
                      routes.allRoutes.where((p) => p.onFooter != true).map(
                            (route) => PaneItem(
                              key: Key("${route.identifier}_screen_button"),
                              icon: route.accessible
                                  ? Icon(route.icon)
                                  : const Icon(WindowsIcons.lock),
                              body: route.accessible
                                  ? Padding(
                                      padding: EdgeInsets.only(
                                          bottom: (routes.showBottomNav() &&
                                                  constraints.maxWidth < 710)
                                              ? 66
                                              : 0),
                                      child: (route.screen)(),
                                    )
                                  : const SizedBox(),
                              title: Txt(route.title),
                              onTap: () => route.accessible
                                  ? routes.navigate(route.identifier)
                                  : null,
                              enabled: route.accessible,
                            ),
                          )),
                  footerItems: [
                    ...routes.allRoutes.where((p) => p.onFooter == true).map(
                          (route) => PaneItem(
                            icon: Icon(route.icon),
                            body: (route.screen)(),
                            title: Txt(route.title),
                            onTap: () => route.accessible
                                ? routes.navigate(route.identifier)
                                : null,
                          ),
                        ),
                  ],
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildPositionedPanel(
      BuildContext context, BoxConstraints constraints, bool hideSidePanel) {
    final minimized = routes.minimizePanels() && constraints.maxWidth < 710;
    final hasKeyboard = MediaQuery.of(context).viewInsets.bottom > 0;
    return AnimatedPositioned(
      duration: hasKeyboard ? Duration.zero : const Duration(milliseconds: 300),
      width: (constraints.maxWidth < 490 && minimized)
          ? constraints.maxWidth
          : 350,
      height: minimized ? 56 : constraints.maxHeight,
      top: minimized ? null : 0,
      bottom: minimized ? 0 : null,
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
                  key: Key(routes.panels().last.identifier),
                  layoutHeight: constraints.maxHeight,
                  layoutWidth: constraints.maxWidth,
                  panel: routes.panels().last,
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
  Widget build(BuildContext context) {
    return FlyoutTarget(
      controller: controller,
      child: GestureDetector(
        onTap: () async {
          if (launch.open() != Open.staff) return;
          await flyoutFocusFix(context);
          controller.showFlyout(builder: (ctx) {
            return MenuFlyout(
              items: routes.allRoutes
                  .where((p) => p.onFooter != true)
                  .map((route) {
                return MenuFlyoutItem(
                  leading: Icon(route.icon),
                  selected: route.identifier == routes.currentRoute.identifier,
                  text: Text(route.title),
                  onPressed: () {
                    controller.close();
                    routes.navigate(route.identifier);
                  },
                );
              }).toList(),
            );
          });
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
                    ? routes.currentRoute.icon
                    : WindowsIcons.lock,
                color: Colors.grey,
              ),
              launch.open() == Open.staff
                  ? Txt(
                      routes.currentRoute.title,
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

import 'dart:io';

import 'package:apexo/app/navbar_widget.dart';
import 'package:apexo/app/panel_widget.dart';
import 'package:apexo/app/routes.dart';
import 'package:apexo/common_widgets/back_button.dart';
import 'package:apexo/common_widgets/dialogs/first_launch_dialog.dart';
import 'package:apexo/common_widgets/dialogs/new_version_dialog.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/features/network_actions/network_actions_widget.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/launch.dart';
import 'package:apexo/services/localization/en.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/features/login/login_screen.dart';
import 'package:apexo/common_widgets/current_account.dart';
import 'package:apexo/common_widgets/logo.dart';
import 'package:apexo/services/version.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

late BuildContext bContext;

class ApexoApp extends StatelessWidget {
  const ApexoApp({super.key});

  @override
  StatelessElement createElement() {
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
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        buildAppLayout(),
                        if (routes.showBottomNav() &&
                            routes.panels().isEmpty &&
                            launch.open())
                          const BottomNavBar()
                      ],
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

    // Show new version dialog if app is outdated
    if ((!kIsWeb) &&
        version.isOutdated() &&
        !launch.dialogShown() &&
        bContext.mounted) {
      launch.dialogShown(true);
      showDialog(
        context: bContext,
        builder: (context) => NewVersionDialog(
            downloadLink: Platform.isWindows
                ? version.latestAPKLink
                : version.latestZipLink),
      );
    }

    // Show first launch dialog if this is the first time the app is launched
    if (launch.isFirstLaunch() && bContext.mounted && !launch.dialogShown()) {
      launch.dialogShown(true);
      showDialog(
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
          final hideSidePanel = routes.panels().isEmpty || !launch.open();
          return Container(
            color: FluentTheme.of(context).menuColor,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildPositionedMainScreen(constraints, hideSidePanel),
                if (routes.panels().isNotEmpty &&
                    routes.minimizePanels() == false &&
                    constraints.maxWidth < 710)
                  ModalBarrier(
                    color: FluentTheme.of(context)
                        .menuColor
                        .withValues(alpha: 0.4),
                    onDismiss: () => routes.minimizePanels(true),
                  ),
                _buildPositionedPanel(constraints, hideSidePanel),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildPositionedMainScreen(
      BoxConstraints constraints, bool hideSidePanel) {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
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
            automaticallyImplyLeading: false,
            title: launch.open()
                ? Txt(routes.currentRoute.title)
                : Txt(txt("login")),
            leading: routes.history.isEmpty
                ? null
                : const BackButton(key: WK.backButton),
            actions: const NetworkActions(key: WK.globalActions),
          ),
          onDisplayModeChanged: (mode) {
            if (mode == PaneDisplayMode.minimal) {
              routes.showBottomNav(true);
            } else {
              routes.showBottomNav(false);
            }
          },
          content: launch.open() ? null : Login(key: WK.loginScreen),
          pane: !launch.open()
              ? null
              : NavigationPane(
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
                                  : const Icon(FluentIcons.lock),
                              body: route.accessible
                                  ? Padding(
                                      padding: EdgeInsets.only(
                                          bottom:
                                              routes.showBottomNav() ? 60 : 0),
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
                            onTap: () => routes.navigate(route.identifier),
                          ),
                        ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildPositionedPanel(BoxConstraints constraints, bool hideSidePanel) {
    final minimized = routes.minimizePanels() && constraints.maxWidth < 710;
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
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
              child: PanelScreen(
                key: Key(routes.panels().last.identifier),
                layoutHeight: constraints.maxHeight,
                layoutWidth: constraints.maxWidth,
                panel: routes.panels().last,
              ),
            ),
    );
  }
}

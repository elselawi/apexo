@Tags(['serial'])
library;

import 'package:apexo/features/login/login_controller.dart';
import 'package:apexo/features/login/login_screen.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/pump_app.dart';

/// The login screen as the shell mounts it: a page that gives the keyboard its
/// height back, which rebuilds the screen on the way.
Future<void> _pumpLogin(WidgetTester tester) async {
  // The login services outlive a test; start from an empty server and email on
  // the login tab, and put the singleton's state back afterwards.
  final storedUrl = login.url;
  final storedEmail = login.email;
  login.url = "";
  login.email = "";
  addTearDown(() {
    login.url = storedUrl;
    login.email = storedEmail;
  });

  final tab = loginCtrl.selectedTab();
  final error = loginCtrl.loginError();
  final loading = loginCtrl.loadingIndicator();
  final sent = loginCtrl.resetInstructionsSent();
  final obscure = loginCtrl.obscureText();
  loginCtrl.selectedTab(0);
  loginCtrl.loginError("");
  loginCtrl.loadingIndicator("");
  loginCtrl.resetInstructionsSent(false);
  loginCtrl.obscureText(true);
  addTearDown(() {
    loginCtrl.selectedTab(tab);
    loginCtrl.loginError(error);
    loginCtrl.loadingIndicator(loading);
    loginCtrl.resetInstructionsSent(sent);
    loginCtrl.obscureText(obscure);
  });

  tester.view.physicalSize = const Size(768, 1024);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);
  addTearDown(tester.view.resetViewInsets);

  await pumpApexoApp(
    tester,
    ScaffoldPage(
      padding: EdgeInsets.zero,
      // Not `const`: the shell rebuilds the screen whenever the page's height
      // changes, which is exactly what the keyboard triggers.
      content: LayoutBuilder(
        builder: (context, constraints) => SizedBox(
          height: constraints.maxHeight,
          // ignore: prefer_const_constructors
          child: LoginScreen(),
        ),
      ),
    ),
  );
}

/// The `EditableText` inside the field with [key].
EditableText _editable(WidgetTester tester, Key key) =>
    tester.widget<EditableText>(
      find.descendant(of: find.byKey(key), matching: find.byType(EditableText)),
    );

void main() {
  testWidgets('the keyboard opening keeps the field being typed in focused',
      (tester) async {
    await _pumpLogin(tester);

    await tester.tap(find.byKey(WK.emailField));
    await tester.pumpAndSettle();
    expect(_editable(tester, WK.emailField).focusNode.hasFocus, isTrue,
        reason: 'tapping a field focuses it');

    // iOS reports the keyboard by growing the bottom inset and giving up the
    // bottom safe-area padding; the page shrinks by the keyboard's height.
    tester.view.padding = FakeViewPadding.zero;
    tester.view.viewInsets = const FakeViewPadding(bottom: 336);
    await tester.pumpAndSettle();

    expect(_editable(tester, WK.emailField).focusNode.hasFocus, isTrue,
        reason: 'the keyboard must not take the focus off the field');

    await tester.enterText(find.byKey(WK.emailField), 'dentist@apexo.app');
    await tester.pump();
    expect(
        _editable(tester, WK.emailField).controller.text, 'dentist@apexo.app',
        reason: 'what was typed stays in the field');
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching to the reset tab still swaps the panel',
      (tester) async {
    await _pumpLogin(tester);
    expect(find.byKey(WK.btnLogin), findsOneWidget);

    // The tab's own key also lands on the strip button it builds; the strip
    // entry is the first in the tree.
    await tester.tap(find.byKey(WK.forgotPasswordTab).first);
    await tester.pumpAndSettle();

    expect(find.byKey(WK.btnResetPassword), findsOneWidget,
        reason: 'the reset tab shows its own actions');
    expect(find.byKey(WK.btnLogin), findsNothing);
  });

  testWidgets('the tab labels follow the language', (tester) async {
    final original = localSettings.selectedLocale;
    addTearDown(() {
      localSettings.selectedLocale = original;
      localSettings.notifyAndPersist();
    });

    await _pumpLogin(tester);
    expect(find.text(txt("login")), findsWidgets);

    localSettings.selectedLocale = 1;
    localSettings.notifyAndPersist();
    await tester.pumpAndSettle();

    expect(find.text(locale.list[1].dictionary["login"]!), findsWidgets,
        reason: 'the cached tabs are rebuilt when the language changes');
  });
}

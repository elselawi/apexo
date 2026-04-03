import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/language_picker.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/features/login/login_controller.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/patient_side.dart';
import 'package:apexo/utils/flyout_focus_fix.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import "package:flutter/cupertino.dart" show CupertinoTextField;
import 'package:image_picker/image_picker.dart';
import '../../common_widgets/logo.dart';

class Login extends StatelessWidget {
  Login({super.key});

  final FlyoutController _qrFlyoutController = FlyoutController();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
        stream: loginCtrl.loginError.stream,
        builder: (context, _) {
          return ScaffoldPage(
            resizeToAvoidBottomInset: true,
            padding: EdgeInsets.zero,
            bottomBar: loginCtrl.loginError().isNotEmpty
                ? _buildErrorContainer()
                : null,
            header: _buildLoginPageHeader(context),
            content: Center(
                child: SizedBox(
              width: 350,
              height: 350,
              child: MStreamBuilder(
                  streams: [
                    loginCtrl.selectedTab.stream,
                    loginCtrl.loginError.stream,
                    loginCtrl.resetInstructionsSent.stream,
                    localSettings.stream,
                    loginCtrl.obscureText.stream,
                    loginCtrl.loadingPatientSide.stream,
                  ],
                  builder: (context, _) {
                    if (loginCtrl.loadingPatientSide()) {
                      return const Center(child: ProgressRing());
                    }
                    return _buildLoginTabs(context);
                  }),
            )),
          );
        });
  }

  Row _buildLoginPageHeader(BuildContext context) {
    return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 5,
        children: [
          const AppLogo(),
          StreamBuilder<Object>(
              stream: localSettings.stream,
              builder: (context, snapshot) {
                return const LanguagePicker();
              }),
          if (loginCtrl.loadingIndicator().isEmpty &&
              !loginCtrl.loadingPatientSide())
            _buildPatientSideButton(context)
        ]);
  }

  Padding _buildErrorContainer() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18.0),
      child: InfoBar(
          key: WK.loginErr,
          title: Txt(txt("error")),
          content: Txt(loginCtrl.loginError()),
          severity: InfoBarSeverity.error),
    );
  }

  TabView _buildLoginTabs(BuildContext context) {
    return TabView(
        currentIndex: loginCtrl.selectedTab(),
        onChanged: (input) {
          if (loginCtrl.loadingIndicator().isEmpty) {
            loginCtrl.selectedTab(input);
          }
        },
        closeButtonVisibility: CloseButtonVisibilityMode.never,
        tabs: [
          Tab(
            key: WK.loginTab,
            text: Txt(txt("login")),
            icon: const Icon(FluentIcons.authenticator_app),
            body: _buildLoginTab(context, [
              serverField(),
              emailField(),
              passwordField(),
            ], [
              _buildLoginBtn(),
              if (loginCtrl.loginError().isNotEmpty) _buildOfflineBtn(),
            ]),
          ),
          Tab(
            key: WK.forgotPasswordTab,
            text: Txt(txt("resetPassword")),
            icon: const Icon(FluentIcons.password_field),
            body: _buildLoginTab(context, [
              const SizedBox(height: 1),
              InfoBar(
                title: loginCtrl.resetInstructionsSent()
                    ? Txt(key: WK.msgSentReset, txt("beenSent"))
                    : Txt(key: WK.msgWillSendReset, txt("youLLGet")),
                severity: loginCtrl.resetInstructionsSent()
                    ? InfoBarSeverity.success
                    : InfoBarSeverity.info,
              ),
              const SizedBox(height: 1),
              serverField(),
              emailField(),
            ], [
              if (loginCtrl.resetInstructionsSent() == false) _buildResetBtn(),
            ]),
          ),
        ]);
  }

  FilledButton _buildResetBtn() {
    return FilledButton(
      key: WK.btnResetPassword,
      onPressed: loginCtrl.resetButton,
      child: Row(children: [
        const Icon(FluentIcons.password_field),
        const SizedBox(width: 10),
        Txt(txt("resetPassword"))
      ]),
    );
  }

  FilledButton _buildOfflineBtn() {
    return FilledButton(
      key: WK.btnProceedOffline,
      onPressed: () => loginCtrl.loginButton(false),
      style: greyButtonStyle,
      child: ButtonContent(
        FluentIcons.virtual_network,
        txt("proceedOffline"),
      ),
    );
  }

  FilledButton _buildLoginBtn() {
    return FilledButton(
      key: WK.btnLogin,
      onPressed: loginCtrl.loginButton,
      child: Row(children: [
        const Icon(FluentIcons.forward),
        const SizedBox(width: 10),
        Txt(txt("login"))
      ]),
    );
  }

  FlyoutTarget _buildPatientSideButton(BuildContext context) {
    return FlyoutTarget(
      controller: _qrFlyoutController,
      child: FilledButton(
          onPressed: () => _pickToUpload(context),
          child: ButtonContent(
            FluentIcons.q_r_code,
            txt("patientSide"),
          )),
    );
  }

  Future<void> _pickToUpload(BuildContext context) async {
    await flyoutFocusFix(context);

    final bool suppGallery =
        ImagePicker().supportsImageSource(ImageSource.gallery);
    final bool suppCamera =
        ImagePicker().supportsImageSource(ImageSource.camera);

    // if it supports only one methood
    // there's no need to show a menu
    if (suppCamera && !suppGallery) {
      PatientSide.fromQR(ImagePicker().pickImage(source: ImageSource.camera));
    } else if (suppGallery && !suppCamera) {
      PatientSide.fromQR(ImagePicker().pickImage(source: ImageSource.gallery));
    } else {
      _qrFlyoutController.showFlyout(builder: (ctx) {
        return MenuFlyout(
          items: [
            if (suppGallery)
              MenuFlyoutItem(
                text: Txt(txt("upload")),
                leading: const Icon(FluentIcons.upload),
                onPressed: () => PatientSide.fromQR(
                    ImagePicker().pickImage(source: ImageSource.gallery)),
              ),
            if (suppCamera)
              MenuFlyoutItem(
                text: Txt(txt("camera")),
                leading: const Icon(FluentIcons.camera),
                onPressed: () => PatientSide.fromQR(
                    ImagePicker().pickImage(source: ImageSource.camera)),
              ),
          ],
        );
      });
    }
  }

  Container _buildLoginTab(
      BuildContext context, List<Widget> fields, List<Widget> actions) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        color: FluentTheme.of(context).menuColor,
      ),
      child: StreamBuilder(
          stream: loginCtrl.loadingIndicator.stream,
          builder: (context, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ...fields
                    .map((field) => [field, const SizedBox(height: 5)])
                    .expand((e) => e),
                if (loginCtrl.loadingIndicator().isNotEmpty)
                  _buildLoadingIndicator()
                else
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: actions
                          .map((e) => [e, const SizedBox(width: 5)])
                          .expand((e) => e)
                          .toList(),
                    ),
                  ),
              ],
            );
          }),
    );
  }

  Center _buildLoadingIndicator() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const ProgressBar(),
          const SizedBox(height: 5),
          Txt(loginCtrl.loadingIndicator()),
        ],
      ),
    );
  }

  Widget serverField() {
    return InfoLabel(
      label: txt("serverUrl"),
      child: CupertinoTextField(
        key: WK.serverField,
        controller: loginCtrl.urlField,
        textDirection: TextDirection.ltr,
        enabled: loginCtrl.loadingIndicator().isEmpty,
        placeholder: "https://[pocketbase server]",
        onSubmitted: (_) => fieldSubmit(),
      ),
    );
  }

  Widget emailField() {
    return InfoLabel(
      label: txt("email"),
      child: CupertinoTextField(
        key: WK.emailField,
        controller: loginCtrl.emailField,
        textDirection: TextDirection.ltr,
        enabled: loginCtrl.loadingIndicator().isEmpty,
        placeholder: "email@domain.com",
        onSubmitted: (_) => fieldSubmit(),
      ),
    );
  }

  Widget passwordField() {
    return InfoLabel(
      label: txt("password"),
      child: CupertinoTextField(
        key: WK.passwordField,
        textDirection: TextDirection.ltr,
        controller: loginCtrl.passwordField,
        enabled: loginCtrl.loadingIndicator().isEmpty,
        obscureText: loginCtrl.obscureText(),
        placeholder: txt("password"),
        suffix: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: IconButton(
            onPressed: () => loginCtrl.obscureText(!loginCtrl.obscureText()),
            icon: Icon(
                loginCtrl.obscureText()
                    ? FluentIcons.red_eye
                    : FluentIcons.hide,
                size: 18),
          ),
        ),
        onSubmitted: (_) => fieldSubmit(),
      ),
    );
  }

  void fieldSubmit() {
    if (loginCtrl.loadingIndicator().isNotEmpty) return;
    if (loginCtrl.selectedTab() == 0) {
      loginCtrl.loginButton();
    } else if (loginCtrl.selectedTab() == 1) {
      loginCtrl.resetButton();
    }
  }
}

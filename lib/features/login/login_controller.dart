import 'package:apexo/app/routes.dart';
import 'package:apexo/core/observable.dart';
import 'package:apexo/services/launch.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/utils/logger.dart';
import 'package:pocketbase/pocketbase.dart';

class _LoginScreenState {
  final loginError = ObservableState("");
  final loadingIndicator = ObservableState("");
  final selectedTab = ObservableState(0);
  final resetInstructionsSent = ObservableState(false);
  final obscureText = ObservableState(true);
  final proceededOffline = ObservableState(true);
  final loadingPatientSide = ObservableState(false);

  void finishedLoginProcess([String error = ""]) {
    loadingIndicator("");
    loginError(error);
  }

  void resetButton(String server, String email) async {
    final pb = PocketBase(server);
    loginError("");
    loadingIndicator("Sending password reset email");
    try {
      await pb.collection("_superusers").requestPasswordReset(email);
      await pb.collection("users").requestPasswordReset(email);
    } catch (e, s) {
      logger("Error during resetting password: $e", s);
      loginError("Error while resetting password: $e.");
      loadingIndicator("");
      return;
    }
    loadingIndicator("");
    resetInstructionsSent(true);
  }

  void loginButton(String server, String email, String password,
      [bool online = true]) {
    server = server.replaceFirst(RegExp(r'/+$'), "");
    email = email.trim().toLowerCase();
    login.activate(server, [email, password], online);
    routes.reset();
  }

  _LoginScreenState() {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (launch.isDemo) {
        loginButton("", "", ""); // TODO: test demo with this
      }
    });
  }
}

final loginCtrl = _LoginScreenState();

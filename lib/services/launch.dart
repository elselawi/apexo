import 'package:apexo/core/observable.dart';

enum Open { login, staff, patient }

class _Launch {
  final dialogShown = ObservableState(false);
  final isFirstLaunch = ObservableState(false);
  final isDemo = Uri.base.host == "demo.apexo.app";
  final open = ObservableState(Open.login);
  double layoutWidth = 0;
}

final launch = _Launch();

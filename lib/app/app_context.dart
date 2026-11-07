import 'package:fluent_ui/fluent_ui.dart';

/// The app content's context, for showing dialogs where no context exists.
/// Kept out of `app/app.dart` so callers do not import the app (import cycle).
late BuildContext bContext;

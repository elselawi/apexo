import 'package:fluent_ui/fluent_ui.dart';

/// The context of the app's own content, for the few places that have no
/// context of their own and must open a dialog over the app.
///
/// It lives here rather than in `app/app.dart` so that a widget which only
/// needs it does not have to import the whole app — which would close a cycle
/// the app's own content already draws (the app draws the gallery, the gallery
/// draws the photo viewer, and the photo viewer's tools report errors).
late BuildContext bContext;

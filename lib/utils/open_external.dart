/// Opening a URI in whatever the platform uses to handle it — with a failure
/// report, which `launchUrl` alone does not give you.
///
/// `launchUrl` returns a `bool` that says whether the launch succeeded, and
/// every call site in this app used to discard it (wrapped in `unawaited` only
/// to satisfy the linter). The user-visible effect was that tapping a phone
/// number on a machine with no dialer, or an email link with no mail client,
/// did **nothing at all** — no error, no message — so a dead link was
/// indistinguishable from a dead tap.
library;

import 'dart:async';

import 'package:apexo/app/app_context.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/utils/logger.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens [uri] with the platform handler, reporting failure to the user.
///
/// Returns whether the launch succeeded, for callers that want to react.
Future<bool> openExternal(Uri uri) async {
  var opened = false;
  try {
    opened = await launchUrl(uri);
  } catch (e, s) {
    logger('Could not open "$uri": $e', s, 3);
  }
  if (!opened) {
    logger('No handler accepted "$uri"', null, 3);
    if (bContext.mounted) {
      unawaited(displayInfoBar(
        bContext,
        builder: (context, close) => InfoBar(
          title: Txt(txt("couldNotOpenLink")),
          content: SelectableText(uri.toString()),
          severity: InfoBarSeverity.error,
          onClose: close,
        ),
      ));
    }
  }
  return opened;
}

/// Opens [uri] with the platform handler and tells the user when nothing can
/// open it — `launchUrl`'s false return is otherwise silent.
library;

import 'dart:async';

import 'package:apexo/app/app_context.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/utils/logger.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:url_launcher/url_launcher.dart';

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

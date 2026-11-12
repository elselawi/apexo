import 'dart:async';
import 'dart:convert';

import 'package:apexo/app/app_context.dart';
import 'package:apexo/common_widgets/dialogs/server_status_dialog.dart';
import 'package:apexo/utils/constants.dart';
import 'package:apexo/utils/logger.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:http/http.dart' as http;

/// A message the server publishes about itself for the clinics it hosts.
class ServerStatusMessage {
  const ServerStatusMessage({
    required this.message,
    required this.dismissable,
  });

  final String message;
  final bool dismissable;

  /// Reads `{active, dismissable, message}` from a response body. An empty,
  /// unrelated or non-JSON body carries no message, which is not an error.
  static ServerStatusMessage? fromBody(String body) {
    final Object? json;
    try {
      json = jsonDecode(body);
    } catch (_) {
      return null;
    }
    if (json is! Map) return null;
    if (json['active'] != true) return null;
    final message = json['message'];
    if (message is! String || message.trim().isEmpty) return null;
    return ServerStatusMessage(
      message: message,
      dismissable: json['dismissable'] == true,
    );
  }
}

class ServerStatusService {
  /// Overridable for tests: the unit suite never reaches the network.
  Future<http.Response> Function(Uri url) get = http.get;

  /// A lookup slower than this is dropped; a login never waits for it.
  Duration requestTimeout = const Duration(seconds: 15);

  /// Lets the app settle after login before a message covers it.
  Duration displayDelay = const Duration(seconds: 5);

  bool _dialogOpen = false;

  /// Fetches the message [serverURL] registered and shows it after
  /// [displayDelay]. It never throws and never delays its caller; [isCurrent]
  /// lets the caller abandon the dialog when the session it belongs to ended.
  Future<void> show(String serverURL, {bool Function()? isCurrent}) async {
    final host = hostOf(serverURL);
    if (host.isEmpty) return;

    final ServerStatusMessage? status;
    try {
      final response = await get(Uri.parse(
              '$serverStatusOrigin/hosted/${Uri.encodeComponent(host)}'))
          .timeout(requestTimeout);
      status = ServerStatusMessage.fromBody(response.body);
    } catch (e, s) {
      // A status endpoint that is down says nothing; the login already succeeded.
      logger("Could not read the server status message: $e", s, 2);
      return;
    }
    if (status == null) return;
    final message = status.message;
    final dismissable = status.dismissable;

    await Future<void>.delayed(displayDelay);
    if (isCurrent?.call() == false) return;
    if (_dialogOpen) return;

    try {
      if (!bContext.mounted) return;
    } catch (_) {
      // The app's content has not been built yet, so there is nothing to cover.
      return;
    }

    _dialogOpen = true;
    try {
      await _present(message, dismissable);
    } finally {
      _dialogOpen = false;
    }
  }

  /// Reads the context where nothing is pending, after [show] checked it is
  /// still mounted.
  Future<void> _present(String message, bool dismissable) => showDialog<void>(
        context: bContext,
        barrierDismissible: dismissable,
        dismissWithEsc: dismissable,
        builder: (context) => ServerStatusDialog(
          message: message,
          dismissable: dismissable,
        ),
      );

  /// The host the user logged in with; a URL typed without a scheme parses as
  /// a path, so it is read again as one.
  String hostOf(String serverURL) {
    final parsed = Uri.tryParse(serverURL);
    final host = parsed != null && parsed.host.isNotEmpty
        ? parsed.host
        : (Uri.tryParse('https://$serverURL')?.host ?? "");
    return host.toLowerCase();
  }
}

final serverStatus = ServerStatusService();

// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';

/// Re-runs the end-to-end suite when a file under `integration_test/` changes.
///
/// ```bash
/// dart integration_test/watch.dart              # the whole suite
/// dart integration_test/watch.dart login        # only tests whose full name contains "login"
/// ```
///
/// It runs `tools/run_e2e.ps1`, so the device, the credentials (from
/// `test/secret.dart`) and — for web runs — chromedriver come from the one
/// place that already knows about them.
void main(List<String> args) async {
  final filter = args.where((a) => !a.startsWith('-')).join(' ');
  final manager = _RunManager();

  var running = false;
  final watcher = Directory("${Directory.current.path}/integration_test").watch(
      events: FileSystemEvent.create |
          FileSystemEvent.modify |
          FileSystemEvent.delete);

  watcher.listen((event) async {
    if (!event.path.endsWith(".dart")) return;
    if (running) {
      print('A run is already in progress; ignoring ${event.path}');
      return;
    }
    running = true;
    try {
      print('Change detected: ${event.type} on ${event.path}');
      await manager.restart(filter);
    } catch (e) {
      print('Could not run the suite: $e');
    } finally {
      running = false;
    }
  });

  print('Watching ${Directory.current.path}/integration_test — '
      'running the suite once to start.');
  await manager.restart(filter);
  await Completer<void>().future; // keep the process alive
}

class _RunManager {
  Process? _process;

  /// Stops the previous run (and its children) and starts a new one.
  Future<void> restart(String filter) async {
    await _stop();
    final args = [
      '-File',
      'tools/run_e2e.ps1',
      if (filter.isNotEmpty) ...['-Group', filter],
    ];
    print('==> pwsh ${args.join(' ')}');
    _process = await Process.start(
      'pwsh',
      args,
      mode: ProcessStartMode.detachedWithStdio,
    );
  }

  Future<void> _stop() async {
    final process = _process;
    _process = null;
    if (process == null) return;
    print('Stopping the previous run (pid ${process.pid})');
    // /T kills the whole tree: the run owns a flutter test/ drive child.
    await Process.run('taskkill', ['/F', '/T', '/PID', '${process.pid}']);
  }
}

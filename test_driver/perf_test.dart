// Temporary host-side profiling driver (writes build/perf/report.json).
//
//   flutter drive --profile --driver=test_driver/perf_test.dart \
//     --target=lib/main_driver.dart -d windows \
//     --dart-define=PB_SERVER=... --dart-define=PB_EMAIL=... --dart-define=PB_PASSWORD=...
//
// Drives the real app the way a staff user does: sign in, open the patients
// screen, search it, open the appointment calendar, the insights board and the
// notes board, and come back. Frame timings come from `traceAction`, CPU
// samples from the VM service between steps, memory from the VM's usage RPCs.
// Host credentials fall back to test/secret.dart; dart-defines target the app.
// APEXO_PERF_FOCUS: all (default), screens, interactions, or login-probe.
// APEXO_PROFILE_SWITCH_BACKEND=1 explicitly permits switching the restored
// session through the normal logout/login UI. Clinic boxes are never removed.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

// ignore: depend_on_referenced_packages
import 'package:flutter_driver/flutter_driver.dart';
// ignore: depend_on_referenced_packages
import 'package:vm_service/vm_service.dart' as vm;

String _credential(String environment, String secretName, String compiled) {
  final override = Platform.environment[environment];
  if (override != null && override.isNotEmpty) return override;
  if (compiled.isNotEmpty) return compiled;
  final file = File('test/secret.dart');
  if (file.existsSync()) {
    final match = RegExp(
            r'^\s*const\s+' + RegExp.escape(secretName) + r"\s*=\s*'([^']*)'",
            multiLine: true)
        .firstMatch(file.readAsStringSync());
    if (match != null) return match.group(1)!;
  }
  throw StateError(
      'Missing $environment in the environment or test/secret.dart');
}

final _server = _credential(
    'PB_SERVER', 'testPBServer', const String.fromEnvironment('PB_SERVER'));
final _email = _credential(
    'PB_EMAIL', 'testPBEmail', const String.fromEnvironment('PB_EMAIL'));
final _password = _credential('PB_PASSWORD', 'testPBPassword',
    const String.fromEnvironment('PB_PASSWORD'));

final _outDir = Directory('build/perf');
final _steps = <String, int>{};
final _cpu = <String, Map<String, List<int>>>{};
final _memory = <String, Object?>{};
final _allocation = <String, Object?>{};
final _failures = <String>[];
final _windows = <String, Map<String, Object?>>{};
final _cpuMetadata = <String, Object?>{};
final _windowFrames = <String, Object?>{};
final _context = <String, Object?>{};
final _classes = <String, vm.ClassRef>{};
final _focused = Platform.environment['APEXO_PERF_FOCUS'] != 'screens';
final _screens = Platform.environment['APEXO_PERF_FOCUS'] != 'interactions';
final _probe = Platform.environment['APEXO_PERF_FOCUS'] == 'login-probe';
bool _reported = false;
_ProcessCpu? _processCpu;

class _ProcessCpu {
  _ProcessCpu(int pid) {
    final kernel = DynamicLibrary.open('kernel32.dll');
    final open = kernel.lookupFunction<IntPtr Function(Uint32, Int32, Uint32),
        int Function(int, int, int)>('OpenProcess');
    _handle = open(0x1000, 0, pid);
    final allocate = kernel.lookupFunction<
        Pointer<Void> Function(Uint32, IntPtr),
        Pointer<Void> Function(int, int)>('LocalAlloc');
    _buffer = allocate(0, 32).cast<Uint64>();
    _times = kernel.lookupFunction<
        Int32 Function(IntPtr, Pointer<Uint64>, Pointer<Uint64>,
            Pointer<Uint64>, Pointer<Uint64>),
        int Function(int, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>,
            Pointer<Uint64>)>('GetProcessTimes');
    _close = kernel.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        'CloseHandle');
    _free = kernel.lookupFunction<Pointer<Void> Function(Pointer<Void>),
        Pointer<Void> Function(Pointer<Void>)>('LocalFree');
    if (_handle == 0 || _buffer.address == 0)
      throw StateError('Cannot read target process CPU');
  }
  late final int _handle;
  late final Pointer<Uint64> _buffer;
  late final int Function(int, Pointer<Uint64>, Pointer<Uint64>,
      Pointer<Uint64>, Pointer<Uint64>) _times;
  late final int Function(int) _close;
  late final Pointer<Void> Function(Pointer<Void>) _free;
  double readMs() {
    if (_times(_handle, _buffer, _buffer + 1, _buffer + 2, _buffer + 3) == 0) {
      throw StateError('GetProcessTimes failed');
    }
    return (_buffer[2] + _buffer[3]) / 10000;
  }

  void close() {
    _close(_handle);
    _free(_buffer.cast<Void>());
  }
}

void _log(String line) => stdout.writeln(line);

/// Every driver/VM call is bounded: a hung command must fail a step, never the
/// whole run (a profile run has no timeout of its own).
Future<T> _bounded<T>(Future<T> future,
    [Duration limit = const Duration(seconds: 15)]) {
  return future.timeout(limit);
}

Map<String, Object?> _report({Map<String, Object?>? frames}) => {
      'stepsMs': _steps,
      'memory': _memory,
      'allocation': _allocation,
      'cpu': _cpu,
      'failures': _failures,
      'context': _context,
      'windows': _windows,
      'cpuMetadata': _cpuMetadata,
      'windowFrames': _windowFrames,
      'measuredAt': DateTime.now().toUtc().toIso8601String(),
      if (frames != null) 'frames': frames,
    };

void _write(Map<String, Object?> value) {
  _reported = true;
  File('${_outDir.path}/report.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(value));
  _log('wrote ${_outDir.path}/report.json (${_failures.length} failures)');
}

Future<void> main() async {
  _outDir.createSync(recursive: true);
  final driver = await FlutterDriver.connect();
  final client = driver.serviceClient;
  final isolate = driver.appIsolate.id!;
  _log('isolate: $isolate');
  _processCpu = _ProcessCpu((await client.getVM()).pid!);

  try {
    await _runFlow(driver, client, isolate);
  } catch (error, stack) {
    _failures.add('fatal: $error');
    _log('FATAL: $error\n$stack');
  } finally {
    _processCpu?.close();
    try {
      await _bounded(driver.close(), const Duration(seconds: 10));
    } catch (_) {}
    if (!_reported) {
      _write(_report());
    }
    if (_failures.isNotEmpty) exitCode = 1;
  }
}

Future<void> _runFlow(
    FlutterDriver driver, vm.VmService client, String isolate) async {
  Future<int> now() async {
    try {
      return (await _bounded(client.getVMTimelineMicros())).timestamp ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> snapshot(String label) async {
    try {
      final usage = await _bounded(client.getMemoryUsage(isolate));
      final profile = await _bounded(
          client.getAllocationProfile(isolate), const Duration(seconds: 30));
      for (final member in profile.members ?? <vm.ClassHeapStats>[]) {
        final ref = member.classRef;
        if (ref?.name != null) _classes[ref!.name!] = ref;
      }
      final state = await _bounded(client.getIsolate(isolate));
      _memory[label] = {
        'heapUsed': usage.heapUsage,
        'heapCapacity': usage.heapCapacity,
        'external': usage.externalUsage,
        'syncResultInstances': profile.members
            ?.where((m) => m.classRef?.name == 'SyncResult')
            .firstOrNull
            ?.instancesCurrent,
        'gc': state.json?['_heaps'] ?? state.json?['heaps'],
      };
      final classes = [
        for (final member in profile.members ?? <vm.ClassHeapStats>[])
          {
            'class': member.classRef?.name ?? '?',
            'bytesCurrent': member.bytesCurrent ?? 0,
            'instances': member.instancesCurrent ?? 0,
          }
      ]..sort((a, b) =>
          (b['bytesCurrent'] as int).compareTo(a['bytesCurrent'] as int));
      _allocation[label] = classes.take(15).toList();
    } catch (error) {
      _log('memory $label failed: $error');
    }
  }

  Future<void> cpuWindow(String label, int origin, int extent) async {
    if (origin == 0 || extent <= 0) return;
    try {
      final samples = await _bounded(
          client.getCpuSamples(isolate, origin, extent),
          const Duration(seconds: 30));
      _cpuMetadata[label] = {
        'originMicros': origin,
        'extentMicros': extent,
        'sampleCount': samples.sampleCount,
        'samplePeriodMicros': samples.samplePeriod,
        'maxStackDepth': samples.maxStackDepth,
        'sampleTimestampsMicros': [
          for (final s in samples.samples ?? <vm.CpuSample>[]) s.timestamp
        ],
      };
      final agg = _cpu.putIfAbsent(label, () => <String, List<int>>{});
      for (final frame in samples.functions ?? const <vm.ProfileFunction>[]) {
        final exclusive = frame.exclusiveTicks ?? 0;
        final inclusive = frame.inclusiveTicks ?? 0;
        if (exclusive == 0 && inclusive == 0) continue;
        final raw = frame.function;
        var name = '?';
        if (raw is Map) {
          final owner = raw['owner'];
          final ownerName = owner is Map ? owner['name'] : null;
          name = (raw['_qualifiedName'] as String?) ??
              '${ownerName == null ? '' : '$ownerName.'}${raw['name'] ?? '?'}';
        } else if (raw is vm.FuncRef) {
          name = (raw.json?['_qualifiedName'] as String?) ?? raw.name ?? '?';
        }
        final key = '$name|${frame.resolvedUrl ?? ''}';
        final entry = agg.putIfAbsent(key, () => [0, 0]);
        entry[0] += exclusive;
        entry[1] += inclusive;
      }
      _log('cpu $label: ${samples.sampleCount} samples / ${extent ~/ 1000} ms');
    } catch (error) {
      _log('cpu $label failed: $error');
    }
  }

  Future<void> step(String name, Future<void> Function() body) async {
    final origin = await now();
    final cpuStart = _processCpu!.readMs();
    final watch = Stopwatch()..start();
    var succeeded = true;
    try {
      await body();
    } catch (error) {
      succeeded = false;
      _failures.add('$name: $error');
      _log('STEP-FAILED $name: $error');
    }
    watch.stop();
    final cpuEnd = _processCpu!.readMs();
    final end = await now();
    _windows[name] = {
      'processCpuMs': cpuEnd - cpuStart,
      'originMicros': origin,
      'endMicros': end,
      'succeeded': succeeded,
    };
    _steps[name] = watch.elapsedMilliseconds;
    _log('STEP $name: ${watch.elapsedMilliseconds} ms');
    await cpuWindow(name, origin, end - origin);
  }

  /// A window with no driver traffic at all: the CPU samples in it belong to
  /// the app, not to the finder polling a `waitFor` does.
  Future<void> quiet(int ms) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  Future<vm.Instance?> instanceOf(String name) async {
    final ref = _classes[name];
    if (ref?.id == null) return null;
    final found = await _bounded(client.getInstances(isolate, ref!.id!, 1));
    if (found.instances?.isEmpty ?? true) return null;
    final object =
        await _bounded(client.getObject(isolate, found.instances!.first.id!));
    return object is vm.Instance ? object : null;
  }

  Object? field(vm.Instance object, String name) =>
      object.fields?.where((f) => f.decl?.name == name).firstOrNull?.value;

  String? selectedPatientTitle;
  Future<String?> firstPatientId() async {
    final page = await instanceOf('_PatientsPageState');
    if (page == null) return null;
    final total = field(page, '_totalFilteredCount');
    if (total is vm.InstanceRef)
      _context['patientsPresent'] = total.valueAsString;
    final items = field(page, '_displayedItems');
    if (items is! vm.InstanceRef || items.id == null) return null;
    final list = await _bounded(client.getObject(isolate, items.id!));
    if (list is! vm.Instance || (list.elements?.isEmpty ?? true)) return null;
    String? fallback;
    for (final element in list.elements!) {
      final patient = await _bounded(
          client.getObject(isolate, (element as vm.InstanceRef).id!));
      if (patient is! vm.Instance) continue;
      final id = field(patient, 'id');
      if (id is! vm.InstanceRef) continue;
      final title = field(patient, 'title');
      if (fallback == null && title is vm.InstanceRef)
        selectedPatientTitle = title.valueAsString;
      fallback ??= id.valueAsString;
      final labelsRef = field(patient, '_labels');
      if (labelsRef is! vm.InstanceRef || labelsRef.id == null) continue;
      final labels = await _bounded(client.getObject(isolate, labelsRef.id!));
      if (labels is! vm.Instance || (labels.elements?.length ?? 0) < 5)
        continue;
      final label = await _bounded(client.getObject(
          isolate, (labels.elements![4] as vm.InstanceRef).id!));
      if (label is! vm.Instance) continue;
      final content = field(label, 'content');
      if (content is vm.InstanceRef &&
          (int.tryParse(content.valueAsString ?? '') ?? 0) > 0) {
        _context['selectedPatientVisitCount'] = content.valueAsString;
        if (title is vm.InstanceRef) selectedPatientTitle = title.valueAsString;
        return id.valueAsString;
      }
    }
    return fallback;
  }

  Future<vm.Instance?> objectOf(Object? ref, {int? count}) async {
    if (ref is! vm.InstanceRef || ref.id == null) return null;
    final result =
        await _bounded(client.getObject(isolate, ref.id!, count: count));
    return result is vm.Instance ? result : null;
  }

  Future<void> settingsCursor() async {
    final store = await instanceOf('GlobalSettings');
    if (store == null) return;
    final local = await objectOf(field(store, 'local'));
    if (local == null) return;
    final future = await objectOf(field(local, 'metaHiveBox'));
    if (future == null) return;
    final box = await objectOf(field(future, '_resultOrListeners'));
    if (box == null) return;
    final keys = await objectOf(field(box, 'keystore'));
    if (keys == null) return;
    final list = await objectOf(field(keys, '_store'));
    if (list == null) return;
    var node = await objectOf(field(list, '_head'));
    for (var n = 0; n < 20 && node != null; n++) {
      final next = await objectOf(field(node, 'next'));
      if (next == null || (next.elements?.isEmpty ?? true)) break;
      node = await objectOf(next.elements!.first);
      if (node == null) break;
      final key = field(node, 'key');
      if (key is! vm.InstanceRef) continue;
      if (key.valueAsString != 'meta:version' &&
          key.valueAsString != 'meta:deferred') continue;
      final frame = await objectOf(field(node, 'value'));
      if (frame == null) continue;
      final value = field(frame, 'value');
      if (value is vm.InstanceRef && value.valueAsString != null) {
        if (key.valueAsString == 'meta:version')
          _context['settingsLocalCursor'] = value.valueAsString;
        if (key.valueAsString == 'meta:deferred')
          _context['settingsDeferredCount'] =
              (jsonDecode(value.valueAsString!) as Map).length;
      }
    }
  }

  Future<void> contextSnapshot() async {
    final login = await instanceOf('_LoginService');
    if (login != null) {
      final url = field(login, 'url');
      _context['restoredBackendMatchesConfigured'] = url is vm.InstanceRef &&
          url.valueAsString?.replaceAll(RegExp(r'/+$'), '') ==
              _server.replaceAll(RegExp(r'/+$'), '');
      if (url is vm.InstanceRef)
        _context['activeBackendHost'] =
            Uri.tryParse(url.valueAsString ?? '')?.host;
    }
    for (final name in ['Patients', 'Appointments', 'Notes']) {
      final store = await instanceOf(name);
      if (store == null) continue;
      final observable = await objectOf(field(store, 'observableMap'));
      if (observable == null) continue;
      final dictionary =
          await objectOf(field(observable, '_dictionary'), count: 0);
      _context['${name}StoredIncludingArchived'] = dictionary?.length;
    }
  }

  await snapshot('start');

  await quiet(8000);
  final restoredLogin = await instanceOf('_LoginService');
  final restoredToken =
      restoredLogin == null ? null : field(restoredLogin, 'token');
  var needsLogin = restoredToken is! vm.InstanceRef ||
      (restoredToken.valueAsString?.isEmpty ?? true);
  final restoredUrl =
      restoredLogin == null ? null : field(restoredLogin, 'url');
  final backendMismatch = !needsLogin &&
      restoredUrl is vm.InstanceRef &&
      restoredUrl.valueAsString?.replaceAll(RegExp(r'/+$'), '') !=
          _server.replaceAll(RegExp(r'/+$'), '');
  if (backendMismatch) {
    if (Platform.environment['APEXO_PROFILE_SWITCH_BACKEND'] != '1') {
      throw StateError(
          'Restored backend differs from PB_SERVER; explicit permission to switch sessions is required');
    }
    await step('session:switch-backend', () async {
      await _bounded(driver.tap(find.byValueKey('calendar_screen_button')));
      await _bounded(driver.tap(find.byValueKey('btnLogout')));
      await _bounded(driver.waitFor(find.byValueKey('serverField')));
    });
    needsLogin = true;
  }
  _log(needsLogin
      ? 'login required'
      : 'session restored (VM state; no finder polling)');

  if (_probe) {
    await _bounded(client.setVMTimelineFlags(['Dart', 'Embedder', 'GC']));
    await _bounded(client.clearVMTimeline());
  }
  if (needsLogin) {
    await step('login:fill', () async {
      await _bounded(driver.tap(find.byValueKey('serverField')));
      await _bounded(driver.enterText(_server));
      await _bounded(driver.tap(find.byValueKey('emailField')));
      await _bounded(driver.enterText(_email));
      await _bounded(driver.tap(find.byValueKey('passwordField')));
      await _bounded(driver.enterText(_password));
    });
    await step(_probe ? 'login:submit-quiet-30s' : 'login:submit', () async {
      await _bounded(driver.tap(find.byValueKey('btnLogin')));
      if (_probe) {
        await quiet(30000);
        return;
      }
      await _bounded(
          driver.waitFor(find.byValueKey('dashboard_screen_button'),
              timeout: const Duration(minutes: 4)),
          const Duration(minutes: 4, seconds: 10));
    });
  }

  if (_probe) {
    if (!needsLogin) await step('restore:quiet-30s', () => quiet(30000));
    await snapshot('settings-stall:1');
    await contextSnapshot();
    try {
      await settingsCursor();
    } catch (error) {
      _context['cursorInspectionError'] = '$error';
    }
    for (var run = 1; run <= 2; run++) {
      await step('settings:quiet-idle:$run', () => quiet(10000));
      await snapshot('settings-stall:${run + 1}');
    }
    _context['mode'] = 'login-probe';
    final controller = await instanceOf('_LoginScreenState');
    if (controller != null) {
      final loading = await objectOf(field(controller, 'loadingIndicator'));
      final value = loading == null ? null : field(loading, '_value');
      if (value is vm.InstanceRef)
        _context['loadingIndicator'] = value.valueAsString;
    }
    final result = await instanceOf('SyncResult');
    if (result != null) {
      _context['syncResultSample'] = {
        for (final key in ['pushed', 'pulled', 'conflicts'])
          key: (field(result, key) as vm.InstanceRef?)?.valueAsString,
        'exceptionIsNull':
            (field(result, 'exception') as vm.InstanceRef?)?.kind == 'Null',
      };
    }
    final raw =
        await _bounded(client.getVMTimeline(), const Duration(seconds: 30));
    final timeline = Timeline.fromJson(raw.json!);
    final events = timeline.json['traceEvents'] as List;
    for (final event in events) {
      if (event['name'] == 'Frame' && event['args']?['isolateId'] == isolate) {
        _context['timelineIsolateGroupId'] = event['args']['isolateGroupId'];
        break;
      }
    }
    await TimelineSummary.summarize(timeline)
        .writeTimelineToFile('perf/timeline');
    for (final entry in _windows.entries) {
      _windowFrames[entry.key] = _framesOf(Timeline.fromJson({
        'traceEvents': [
          for (final event in events)
            if (event['ts'] is num &&
                (event['ts'] as num) >= (entry.value['originMicros'] as int) &&
                (event['ts'] as num) <= (entry.value['endMicros'] as int))
              event,
        ]
      }));
    }
    await _bounded(client.setVMTimelineFlags([]));
    _write(_report(frames: _framesOf(timeline)));
    return;
  }
  if (_windows['login:submit']?['succeeded'] == false) {
    throw StateError(
        'Login did not reach the dashboard; screen measurements were not attempted');
  }
  await snapshot('after-login');
  await contextSnapshot();
  _context['configuredBackendPresent'] = _server.isNotEmpty;
  _log('context: ${jsonEncode(_context)}');

  final timeline = await driver.traceAction(
    () async {
      try {
        await step('dashboard:initial-idle', () => quiet(10000));
        if (_screens) {
          for (var run = 1; run <= 5; run++) {
            for (final screen in [
              'patients',
              'calendar',
              'insights',
              'notes',
              'dashboard'
            ]) {
              final ready = {
                'patients': 'btnNewPatient',
                'calendar': 'btnNewAppointment',
                'notes': 'btnNewNote',
                'dashboard': 'dashboardScreen',
              };
              await step('$screen:open:$run', () async {
                if (screen == 'insights') {
                  await _bounded(
                      driver.tap(find.byValueKey('insights_screen_button')));
                  await _bounded(
                      driver.waitFor(find.byType('StyledBarChart'),
                          timeout: const Duration(seconds: 30)),
                      const Duration(seconds: 35));
                } else {
                  await _tapUntil(
                      driver, '${screen}_screen_button', ready[screen]!);
                }
              });
              await step(
                  '$screen:idle:$run', () => quiet(run == 1 ? 10000 : 1000));
              await snapshot('$screen:$run');

              if (screen == 'patients') {
                await _bounded(driver.tap(find.byValueKey('listSearch')));
                for (final text in ['a', 'ab', '']) {
                  final label = text.isEmpty ? 'clear' : text;
                  await step('patients:search-$label:$run', () async {
                    await driver.runUnsynchronized(
                        () => _bounded(driver.enterText(text)));
                    await quiet(2000);
                  });
                }
              }
              if (screen == 'insights' && !_focused) {
                for (final interval in ['Weeks', 'Months', 'days']) {
                  await step('insights:range-$interval:$run', () async {
                    await driver.runUnsynchronized(() => _bounded(driver.tap(
                        find.ancestor(
                            of: find.text(interval),
                            matching: find.byType('ToggleButton'),
                            firstMatchOnly: true))));
                    await quiet(2000);
                  });
                }
              }
            }
          }
        }
        if (_focused) {
          await _bounded(driver.tap(find.byValueKey('insights_screen_button')));
          await _bounded(driver.waitFor(find.byType('StyledBarChart')));
          await quiet(2000);
          for (var run = 1; run <= 5; run++) {
            for (final interval in ['Weeks', 'Months', 'days']) {
              await step('insights:range-$interval:$run', () async {
                await driver.runUnsynchronized(() => _bounded(driver.tap(
                    find.ancestor(
                        of: find.text(interval),
                        matching: find.byType('ToggleButton'),
                        firstMatchOnly: true))));
                await quiet(2000);
              });
            }
          }
          await _tapUntil(driver, 'patients_screen_button', 'btnNewPatient');
          await quiet(2000);
          await snapshot('patients-focused');
          await contextSnapshot();
          final patientId = await firstPatientId();
          if (patientId == null) {
            _failures.add(
                'patient panel: could not resolve visible row from VM state');
          } else {
            _log('context: ${jsonEncode(_context)}');
            await _bounded(driver.tap(find.byValueKey('listSearch')));
            if (!_screens) {
              for (var run = 1; run <= 5; run++) {
                for (final text in ['a', 'ab', '']) {
                  await step(
                      'patients:search-${text.isEmpty ? 'clear' : text}:$run',
                      () async {
                    await driver.runUnsynchronized(
                        () => _bounded(driver.enterText(text)));
                    await quiet(2000);
                  });
                }
              }
            }
            await _bounded(driver.enterText(selectedPatientTitle ?? ''));
            await quiet(2000);
            for (var run = 1; run <= 5; run++) {
              await step('patient:panel-open:$run', () async {
                await driver.runUnsynchronized(() => _bounded(driver.tap(
                    find.ancestor(
                        of: find.text(selectedPatientTitle!),
                        matching: find.byType('ItemTitle'),
                        firstMatchOnly: true))));
                await quiet(2000);
              });
              if (_windows['patient:panel-open:$run']?['succeeded'] == false)
                break;
              await _bounded(
                  driver.waitFor(find.byValueKey('fieldPatientName')));
              await step('patient:chart-open:$run', () async {
                await driver.runUnsynchronized(() => _bounded(driver.tap(
                    find.byValueKey('workspaceWindowToggle-dentalChart'))));
                await quiet(2000);
              });
              await step('patient:chart-close:$run', () async {
                await driver.runUnsynchronized(() => _bounded(
                    driver.tap(find.byValueKey('windowMinimize-dentalChart'))));
                await quiet(1000);
              });
              await step('patient:panel-close:$run', () async {
                await driver.runUnsynchronized(
                    () => _bounded(driver.tap(find.byValueKey('panelClose'))));
                await quiet(2000);
              });
            }
            try {
              await _bounded(driver.tap(find.ancestor(
                  of: find.text(selectedPatientTitle!),
                  matching: find.byType('ItemTitle'),
                  firstMatchOnly: true)));
              await _bounded(
                  driver.waitFor(find.byValueKey('fieldPatientName')));
              await _bounded(driver
                  .tap(find.byValueKey('workspaceWindowToggle-appointments')));
              await quiet(2000);
              await snapshot('patient-visits');
              final card = await instanceOf('AppointmentCard');
              final appointment = card == null
                  ? null
                  : await objectOf(field(card, 'appointment'));
              final id = appointment == null ? null : field(appointment, 'id');
              if (id is! vm.InstanceRef || id.valueAsString == null) {
                throw StateError('no visible visit card resolved');
              }
              final opener = find.descendant(
                  of: find.byValueKey(id.valueAsString!),
                  matching: find.byType('IconButton'));
              for (var run = 1; run <= 5; run++) {
                await step('visit:chart-open:$run', () async {
                  await driver
                      .runUnsynchronized(() => _bounded(driver.tap(opener)));
                  await quiet(2000);
                });
                await _bounded(
                    driver.waitFor(find.byValueKey('chartAllAppointments')));
                await step('visit:chart-close:$run', () async {
                  await driver.runUnsynchronized(() =>
                      _bounded(driver.tap(find.byValueKey('visitDetach'))));
                  await quiet(2000);
                });
              }
              await _bounded(driver.tap(find.byValueKey('panelClose')));
            } catch (error) {
              _failures.add('visit chart UI: $error');
              await step('workspace:cleanup', () async {
                await _bounded(driver.tap(find.byValueKey('closeAllWindows')));
                await quiet(1000);
              });
            }
          }
          await step('calendar:quiet-open', () async {
            await driver.runUnsynchronized(() => _bounded(
                driver.tap(find.byValueKey('calendar_screen_button'))));
            await quiet(2000);
          });
        }
        await step('sync:action', () async {
          await driver.runUnsynchronized(
              () => _bounded(driver.tap(find.byValueKey('globalAction-sync'))));
          await quiet(10000);
        });
        await snapshot('after-sync');
      } catch (error) {
        _failures.add('flow stopped: $error');
      }
    },
    streams: const [
      TimelineStream.dart,
      TimelineStream.embedder,
      TimelineStream.gc,
    ],
  );

  await snapshot('after-flow');

  try {
    final profile = await _bounded(
        client.getAllocationProfile(isolate), const Duration(seconds: 30));
    final classes = <Map<String, Object?>>[];
    for (final member in profile.members ?? const <vm.ClassHeapStats>[]) {
      final name = member.classRef?.name ?? '?';
      if ((member.bytesCurrent ?? 0) < 64 * 1024) continue;
      classes.add({
        'class': name,
        'bytesCurrent': member.bytesCurrent,
        'instances': member.instancesCurrent,
        'bytesAccumulated': member.accumulatedSize,
      });
    }
    classes.sort((a, b) =>
        (b['bytesCurrent']! as int).compareTo(a['bytesCurrent']! as int));
    _allocation['topClasses'] = classes.take(25).toList();
  } catch (error) {
    _log('allocation profile failed: $error');
  }

  try {
    final summary = TimelineSummary.summarize(timeline);
    await summary.writeTimelineToFile('perf/timeline');
    final events = timeline.json['traceEvents'] as List;
    for (final event in events) {
      if (event['name'] == 'Frame' && event['args']?['isolateId'] == isolate) {
        _context['timelineIsolateGroupId'] = event['args']['isolateGroupId'];
        break;
      }
    }
    final frames = _framesOf(timeline);
    for (final entry in _windows.entries) {
      final start = entry.value['originMicros'] as int;
      final end = entry.value['endMicros'] as int;
      final window = Timeline.fromJson({
        'traceEvents': [
          for (final event in events)
            if (event['ts'] is num &&
                (event['ts'] as num) >= start &&
                (event['ts'] as num) <= end)
              event,
        ]
      });
      try {
        _windowFrames[entry.key] = _framesOf(window);
      } catch (error) {
        _windowFrames[entry.key] = {'unavailable': '$error'};
      }
    }
    _write(_report(frames: frames));
    _log('frames: $frames');
  } catch (error) {
    _failures.add('timeline summary: $error');
    _log('timeline summary failed: $error');
  }
}

Map<String, Object?> _framesOf(Timeline timeline) {
  int gcCount(String name) => (timeline.events ?? <TimelineEvent>[])
      .where((e) =>
          e.category == 'GC' &&
          e.name == name &&
          e.phase == 'B' &&
          e.arguments?['isolateGroupId'] == _context['timelineIsolateGroupId'])
      .length;
  if (!(timeline.events ?? <TimelineEvent>[]).any((e) => e.name == 'Frame')) {
    return {
      'count': 0,
      'rasterizations': 0,
      'oldGenGcs': gcCount('CollectOldGeneration'),
      'newGenGcs': gcCount('CollectNewGeneration')
    };
  }
  final summary = TimelineSummary.summarize(timeline);
  return {
    'count': summary.countFrames(),
    'rasterizations': summary.countRasterizations(),
    'buildAvgMs': summary.computeAverageFrameBuildTimeMillis(),
    'buildP90Ms': summary.computePercentileFrameBuildTimeMillis(90),
    'buildP99Ms': summary.computePercentileFrameBuildTimeMillis(99),
    'buildWorstMs': summary.computeWorstFrameBuildTimeMillis(),
    'buildMissedBudget': summary.computeMissedFrameBuildBudgetCount(),
    'rasterAvgMs': summary.computeAverageFrameRasterizerTimeMillis(),
    'rasterP90Ms': summary.computePercentileFrameRasterizerTimeMillis(90),
    'rasterP99Ms': summary.computePercentileFrameRasterizerTimeMillis(99),
    'rasterWorstMs': summary.computeWorstFrameRasterizerTimeMillis(),
    'rasterMissedBudget': summary.computeMissedFrameRasterizerBudgetCount(),
    'oldGenGcs': gcCount('CollectOldGeneration'),
    'newGenGcs': gcCount('CollectNewGeneration'),
  };
}

Future<void> _tapUntil(
    FlutterDriver driver, String buttonKey, String readyKey) async {
  for (var attempt = 0; attempt < 2; attempt++) {
    try {
      await _bounded(
          driver.tap(find.byValueKey(buttonKey)), const Duration(seconds: 20));
    } catch (error) {
      _log('tap $buttonKey failed: $error');
    }
    try {
      await _bounded(
          driver.waitFor(find.byValueKey(readyKey),
              timeout: const Duration(seconds: 20)),
          const Duration(seconds: 25));
      return;
    } catch (_) {
      _log('$readyKey did not appear after tapping $buttonKey '
          '(attempt ${attempt + 1})');
      await _dismissDialogs(driver);
    }
  }
  throw StateError('$readyKey never appeared');
}

Future<void> _dismissDialogs(FlutterDriver driver) async {
  for (var attempt = 0; attempt < 3; attempt++) {
    var present = false;
    try {
      await _bounded(
          driver.waitFor(find.byType('ContentDialog'),
              timeout: const Duration(seconds: 2)),
          const Duration(seconds: 3));
      present = true;
    } catch (_) {
      present = false;
    }
    if (!present) return;
    _log('dismissing a ContentDialog (attempt ${attempt + 1})');
    try {
      await _bounded(driver.tap(find.descendant(
        of: find.byType('ContentDialog'),
        matching: find.byType('Icon'),
      )));
    } catch (error) {
      _log('could not tap the dialog close icon: $error');
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
}

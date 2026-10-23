// Adds the Windows push activation contract to a generated AppxManifest.xml.
//
// The msix tool generates the manifest (`dart run msix:build`), but it can only
// express the local-toast activator. Push needs two more things it cannot emit:
//
//   * a PackageDependency on the Windows App Runtime 1.7 framework package;
//   * a push COM server whose class id is the Azure application (client) id and
//     whose activation arguments are "----WindowsAppRuntimePushServer:".
//
// The toast activator is a different contract — different class id, different
// arguments — and this tool never rewrites it.
//
// Usage (normally run through tools/patch_msix_manifest.ps1):
//   dart run msix:build --sign-msix false
//   dart run tools/patch_push_manifest.dart build/windows/x64/runner/Release/AppxManifest.xml
//   dart run msix:pack --sign-msix false
//   dart run tools/patch_push_manifest.dart --verify <extracted>/AppxManifest.xml
//
// The App ID defaults to APEXO_WNS_APP_ID in windows/runner/push_config.h, so
// the header stays the single source of truth. The expected package identity,
// publisher and toast CLSID are read from pubspec.yaml and
// lib/services/notifications/windows_notification_identity.dart, so the three
// copies of those values cannot drift apart unnoticed.
//
// `--sign-msix false` matters: without it the msix tool replaces the configured
// publisher with the subject of its bundled test certificate and the package
// family name changes.
//
// The patcher never edits the manifest in place — it writes a temporary file
// beside the target, re-verifies it, and only then replaces the original — so a
// failure cannot leave a half-patched manifest behind.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';
import 'package:yaml/yaml.dart';

/// Argument Windows passes when it activates the push COM server.
const String pushActivationArguments = '----WindowsAppRuntimePushServer:';

/// Argument Windows passes when it activates the local-toast COM server.
const String toastActivationArguments = '----AppNotificationActivationServer';

const String runtimeDependencyName = 'Microsoft.WindowsAppRuntime.1.7';

/// The publisher of the Windows App Runtime framework package.
const String runtimeDependencyPublisher =
    'CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, '
    'S=Washington, C=US';

/// The framework package version shipped in the pinned Windows App SDK, read
/// from `tools/MSIX/win10-x64/Microsoft.WindowsAppRuntime.1.7.msix` inside the
/// `Microsoft.WindowsAppSDK` package (and matching `WindowsAppSDK-VersionInfo.json`).
/// This is the version the app is compiled against, so it is the floor.
const String runtimeDependencyMinVersion = '7000.498.2246.0';

const String defaultConfigPath = 'windows/runner/push_config.h';

const String defaultPubspecPath = 'pubspec.yaml';

const String defaultIdentityPath =
    'lib/services/notifications/windows_notification_identity.dart';

const String zeroGuid = '00000000-0000-0000-0000-000000000000';

const String comNamespace =
    'http://schemas.microsoft.com/appx/manifest/com/windows10';

/// Windows path semantics, even when the verifier runs on a non-Windows host.
final p.Context _windowsPaths = p.Context(style: p.Style.windows);

/// A manifest that cannot be made correct without a human deciding what to do.
class PatchError implements Exception {
  PatchError(this.message);
  final String message;
  @override
  String toString() => 'PatchError: $message';
}

/// The identifiers from `push_config.h`.
class PushConfig {
  const PushConfig({required this.objectId, required this.appId});
  final String objectId;
  final String appId;
}

/// Reads the two identifiers from the C header.
PushConfig readPushConfig(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    throw PatchError('push_config.h not found at $path');
  }
  final source = file.readAsStringSync();
  return PushConfig(
    objectId: _define(source, 'APEXO_WNS_OBJECT_ID', path),
    appId: _define(source, 'APEXO_WNS_APP_ID', path),
  );
}

String _define(String source, String name, String path) {
  final match = RegExp('#define\\s+$name\\s+"([^"]+)"').firstMatch(source);
  if (match == null) {
    throw PatchError('$path has no $name definition');
  }
  return match.group(1)!.trim();
}

/// The identity `msix` will put in the manifest, from `pubspec.yaml`.
class MsixConfig {
  const MsixConfig({
    required this.identityName,
    required this.publisher,
    required this.toastClsid,
  });

  final String identityName;
  final String publisher;
  final String toastClsid;
}

/// The identity the Dart side presents, from `windows_notification_identity.dart`.
class WindowsNotificationIdentity {
  const WindowsNotificationIdentity({
    required this.appUserModelId,
    required this.activationGuid,
  });

  final String appUserModelId;

  /// The local-toast COM class id.
  final String activationGuid;

  /// `<PackageFamilyName>!<Application Id>` — the application id half.
  String get applicationId => appUserModelId.split('!').last;

  /// `<Identity Name>_<publisher hash>` — the package family name half.
  String get packageFamilyName => appUserModelId.split('!').first;

  /// The publisher hash segment, if the family name looks well formed.
  String? get publisherHash {
    final family = packageFamilyName;
    final separator = family.lastIndexOf('_');
    if (separator <= 0 || separator == family.length - 1) {
      return null;
    }
    return family.substring(separator + 1);
  }
}

/// Reads the packaging identity from `pubspec.yaml`.
MsixConfig readMsixConfig(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    throw PatchError('pubspec.yaml not found at $path');
  }
  Object? yaml;
  try {
    yaml = loadYaml(file.readAsStringSync());
  } on YamlException catch (error) {
    throw PatchError('$path is not valid YAML: ${error.message}');
  }
  if (yaml is! YamlMap) {
    throw PatchError('$path is not a YAML map.');
  }
  final config = yaml['msix_config'];
  if (config is! YamlMap) {
    throw PatchError('$path has no msix_config section.');
  }
  final activator = config['toast_activator'];
  if (activator is! YamlMap) {
    throw PatchError(
      '$path has no msix_config.toast_activator section, so the packaged app '
      'cannot route local toast clicks.',
    );
  }
  return MsixConfig(
    identityName: _mapString(config, 'identity_name', '$path msix_config'),
    publisher: _mapString(config, 'publisher', '$path msix_config'),
    toastClsid:
        _mapString(activator, 'clsid', '$path msix_config.toast_activator'),
  );
}

String _mapString(YamlMap map, String key, String where) {
  final value = map[key];
  if (value is! String || value.trim().isEmpty) {
    throw PatchError('$where has no "$key" value.');
  }
  return value.trim();
}

/// Reads the AUMID and toast CLSID from the shared Dart constants.
WindowsNotificationIdentity readWindowsNotificationIdentity(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    throw PatchError('windows_notification_identity.dart not found at $path');
  }
  final source = file.readAsStringSync();
  return WindowsNotificationIdentity(
    appUserModelId: _dartString(source, 'appUserModelId', path),
    activationGuid: _dartString(source, 'activationGuid', path),
  );
}

String _dartString(String source, String name, String path) {
  final match = RegExp('static\\s+const\\s+String\\s+$name\\s*=\\s*"([^"]+)"')
      .firstMatch(source);
  if (match == null || match.group(1)!.trim().isEmpty) {
    throw PatchError('$path has no `static const String $name`.');
  }
  return match.group(1)!.trim();
}

/// Applies every rule and returns the manifest as text.
String patchManifest(String manifestXml, {required String appId}) {
  _requireConfiguredIds(appId: appId, objectId: null);

  final document = XmlDocument.parse(manifestXml);
  final package = document.rootElement;
  if (package.name.local != 'Package') {
    throw PatchError(
        'expected a <Package> root, found <${package.name.local}>');
  }

  _ensureComNamespace(package);
  _ensureRuntimeDependency(package);
  final application = _singleApplication(package);
  final extensions = _ensureExtensions(application);
  _patchPushActivator(
    application: application,
    extensions: extensions,
    appId: appId,
  );

  return document.toXmlString(pretty: true, indent: '  ');
}

/// Fails when the manifest is not ready to receive WNS pushes.
void verifyManifest(
  String manifestXml, {
  required String appId,
  required MsixConfig msix,
  required WindowsNotificationIdentity identity,
  String? objectId,
}) {
  _requireConfiguredIds(appId: appId, objectId: objectId);

  final document = XmlDocument.parse(manifestXml);
  final package = document.rootElement;
  if (package.name.local != 'Package') {
    throw PatchError(
        'expected a <Package> root, found <${package.name.local}>');
  }

  _verifyRuntimeDependency(package);
  final application = _singleApplication(package);
  _verifyIdentity(package, application, msix, identity);

  final servers = _comServers(application);
  final pushServers = servers
      .where((server) =>
          _attribute(server, 'Arguments') == pushActivationArguments)
      .toList();
  if (pushServers.isEmpty) {
    throw PatchError(
      'the push activation server is missing '
      '(Arguments="$pushActivationArguments"). Run the patcher on the '
      'generated manifest.',
    );
  }
  if (pushServers.length > 1) {
    throw PatchError(
      '${pushServers.length} push activation servers found; exactly one is '
      'allowed.',
    );
  }
  final pushServer = pushServers.single;
  _requireMatchingExecutable(application, pushServer, 'push');
  final pushClasses = _classes(pushServer).toList();
  if (pushClasses.length != 1) {
    throw PatchError(
      'the push activation server must declare exactly one class, found '
      '${pushClasses.length}.',
    );
  }
  if (_normalizeGuid(_attribute(pushClasses.single, 'Id')) !=
      _normalizeGuid(appId)) {
    throw PatchError(
      'the push activation class id is '
      '"${_attribute(pushClasses.single, 'Id')}", expected "$appId".',
    );
  }

  // The local-toast contract is generated by the msix tool. It must be there and
  // must not collide with the push class id.
  final toastClsid = _toastActivatorClsid(application);
  if (toastClsid == null) {
    throw PatchError(
      'the local toast activation contract is missing. Set '
      'msix_config.toast_activator.clsid in pubspec.yaml and rebuild the '
      'package files.',
    );
  }
  if (_normalizeGuid(toastClsid) == _normalizeGuid(appId)) {
    throw PatchError(
      'the toast activation CLSID and the push application id are the same '
      '("$appId"). They are different contracts and must not share a value.',
    );
  }
  if (_normalizeGuid(toastClsid) != _normalizeGuid(identity.activationGuid)) {
    throw PatchError(
      'the local toast activation CLSID is "$toastClsid", but '
      'WindowsNotificationIdentity.activationGuid is '
      '"${identity.activationGuid}". Clicking a toast would not reach the app.',
    );
  }
  if (_normalizeGuid(msix.toastClsid) !=
      _normalizeGuid(identity.activationGuid)) {
    throw PatchError(
      'msix_config.toast_activator.clsid is "${msix.toastClsid}", but '
      'WindowsNotificationIdentity.activationGuid is '
      '"${identity.activationGuid}". Both copies must hold the same value.',
    );
  }

  final toastServers = servers
      .where((server) =>
          _attribute(server, 'Arguments') == toastActivationArguments)
      .toList();
  if (toastServers.isEmpty) {
    throw PatchError(
      'the local toast activation server is missing '
      '(Arguments="$toastActivationArguments").',
    );
  }
  for (final server in toastServers) {
    _requireMatchingExecutable(application, server, 'toast');
    final classes = _classes(server).toList();
    if (classes.isEmpty) {
      throw PatchError('a toast activation server declares no class id.');
    }
    for (final element in classes) {
      final id = _attribute(element, 'Id');
      if (_normalizeGuid(id) == _normalizeGuid(appId)) {
        throw PatchError(
          'the push application id is used as a toast activation class id.',
        );
      }
      if (_normalizeGuid(id) != _normalizeGuid(toastClsid)) {
        throw PatchError(
          'a toast activation server declares the class id "$id", expected '
          '"$toastClsid".',
        );
      }
    }
  }
  for (final server in pushServers) {
    for (final element in _classes(server)) {
      if (_normalizeGuid(_attribute(element, 'Id')) ==
          _normalizeGuid(toastClsid)) {
        throw PatchError(
          'the toast activation CLSID is used as the push class id.',
        );
      }
    }
  }
}

/// Checks the package identity the notification AUMID depends on.
///
/// This is a consistency check between three files — the manifest, pubspec.yaml
/// and windows_notification_identity.dart. It does **not** recompute the package
/// family name; only Windows' own publisher hash would prove that, which is why
/// the packaging script compares against an installed package separately.
void _verifyIdentity(
  XmlElement package,
  XmlElement application,
  MsixConfig msix,
  WindowsNotificationIdentity identity,
) {
  final element = package.childElements
      .where((child) => child.name.local == 'Identity')
      .firstOrNull;
  if (element == null) {
    throw PatchError('the manifest has no <Identity> element.');
  }

  final name = _attribute(element, 'Name') ?? '';
  if (name != msix.identityName) {
    throw PatchError(
      'the package identity name is "$name", expected "${msix.identityName}" '
      '(msix_config.identity_name in pubspec.yaml).',
    );
  }

  final publisher =
      _normalizeDistinguishedName(_attribute(element, 'Publisher'));
  final expectedPublisher = _normalizeDistinguishedName(msix.publisher);
  if (publisher != expectedPublisher) {
    final hint = publisher.startsWith('CN=Msix Testing')
        ? ' The msix tool substituted the subject of its bundled test '
            'certificate: run it with --sign-msix false so that '
            'msix_config.publisher is used.'
        : '';
    throw PatchError(
      'the package publisher is "$publisher", expected "$expectedPublisher" '
      '(msix_config.publisher in pubspec.yaml). The publisher decides the '
      'package family name, which the notification AUMID depends on.$hint',
    );
  }

  final applicationId = _attribute(application, 'Id') ?? '';
  if (applicationId != identity.applicationId) {
    throw PatchError(
      'the application id is "$applicationId", but '
      'WindowsNotificationIdentity.appUserModelId ends with '
      '"!${identity.applicationId}".',
    );
  }

  final family = identity.packageFamilyName;
  final hash = identity.publisherHash;
  if (!family.startsWith('${msix.identityName}_') ||
      hash == null ||
      hash.length != 13) {
    throw PatchError(
      'WindowsNotificationIdentity.appUserModelId '
      '("${identity.appUserModelId}") is not '
      '"<identity>_<13-character publisher hash>!<application id>" for the '
      'identity "${msix.identityName}".',
    );
  }

  _requireCapability(package, 'internetClient', restricted: false);
  _requireCapability(package, 'runFullTrust', restricted: true);
}

String _normalizeDistinguishedName(String? value) =>
    (value ?? '').trim().replaceAll(' = ', '=');

void _requireCapability(
  XmlElement package,
  String name, {
  required bool restricted,
}) {
  for (final group in package.childElements
      .where((element) => element.name.local == 'Capabilities')) {
    for (final capability in group.childElements) {
      if (capability.name.local != 'Capability' ||
          _attribute(capability, 'Name') != name) {
        continue;
      }
      if ((capability.name.prefix == 'rescap') == restricted) {
        return;
      }
    }
  }
  throw PatchError(
    'the manifest does not declare the '
    '"${restricted ? 'rescap:' : ''}$name" capability.',
  );
}

void _requireConfiguredIds({required String appId, String? objectId}) {
  if (_normalizeGuid(appId) == zeroGuid) {
    throw PatchError(
      'the push application id is still the all-zero placeholder. Set '
      'APEXO_WNS_APP_ID in windows/runner/push_config.h (or pass --app-id).',
    );
  }
  if (objectId != null) {
    if (_normalizeGuid(objectId) == zeroGuid) {
      throw PatchError(
        'the Entra Object ID is still the all-zero placeholder. Set '
        'APEXO_WNS_OBJECT_ID in windows/runner/push_config.h.',
      );
    }
    if (_normalizeGuid(objectId) == _normalizeGuid(appId)) {
      throw PatchError(
        'the Entra Object ID and the Azure application id are the same '
        '("$appId"). CreateChannelAsync takes the Object ID; the manifest '
        'takes the application id — they must not be substituted.',
      );
    }
  }
}

String _normalizeGuid(String? value) =>
    (value ?? '').trim().replaceAll('{', '').replaceAll('}', '').toLowerCase();

void _ensureComNamespace(XmlElement package) {
  final hasCom = package.attributes.any((attribute) =>
      attribute.name.prefix == 'xmlns' && attribute.name.local == 'com');
  if (!hasCom) {
    package.attributes.add(XmlAttribute(XmlName('xmlns:com'), comNamespace));
  }

  final ignorable = package.attributes
      .where((attribute) => attribute.name.local == 'IgnorableNamespaces')
      .firstOrNull;
  final names = (ignorable?.value ?? '')
      .split(RegExp(r'\s+'))
      .where((name) => name.isNotEmpty)
      .toList();
  if (!names.contains('com')) {
    names.add('com');
    if (ignorable != null) {
      ignorable.value = names.join(' ');
    } else {
      package.attributes
          .add(XmlAttribute(XmlName('IgnorableNamespaces'), names.join(' ')));
    }
  }
}

void _ensureRuntimeDependency(XmlElement package) {
  var dependencies = package.childElements
      .where((element) => element.name.local == 'Dependencies')
      .firstOrNull;
  if (dependencies == null) {
    dependencies = XmlElement(XmlName('Dependencies'));
    package.children.add(dependencies);
  }
  _ensureRuntimeDependencyIn(dependencies);
}

void _ensureRuntimeDependencyIn(XmlElement dependencies) {
  final existing = dependencies.childElements
      .where((element) =>
          element.name.local == 'PackageDependency' &&
          element.getAttribute('Name') == runtimeDependencyName)
      .toList();

  if (existing.length > 1) {
    // Deterministic: keep the first, drop the duplicates.
    for (final duplicate in existing.skip(1)) {
      dependencies.children.remove(duplicate);
    }
  }
  if (existing.isNotEmpty) {
    final dependency = existing.first;
    final publisher =
        _normalizeDistinguishedName(dependency.getAttribute('Publisher'));
    if (publisher.isNotEmpty &&
        publisher != _normalizeDistinguishedName(runtimeDependencyPublisher)) {
      throw PatchError(
        'the $runtimeDependencyName dependency has an unexpected publisher '
        '"${dependency.getAttribute('Publisher')}".',
      );
    }
    final version = dependency.getAttribute('MinVersion') ?? '';
    final comparison = _compareVersions(version, runtimeDependencyMinVersion);
    if (comparison == null) {
      throw PatchError(
        'the $runtimeDependencyName dependency has an unreadable MinVersion '
        '"$version".',
      );
    }
    if (comparison > 0) {
      throw PatchError(
        'the $runtimeDependencyName dependency already requires MinVersion '
        '"$version", which is newer than the version this build targets '
        '("$runtimeDependencyMinVersion"). Refusing to lower it.',
      );
    }
    if (comparison < 0) {
      dependency.setAttribute('MinVersion', runtimeDependencyMinVersion);
    }
    if (publisher.isEmpty) {
      dependency.setAttribute('Publisher', runtimeDependencyPublisher);
    }
    return;
  }

  dependencies.children.add(XmlElement(XmlName('PackageDependency'), [
    XmlAttribute(XmlName('Name'), runtimeDependencyName),
    XmlAttribute(XmlName('MinVersion'), runtimeDependencyMinVersion),
    XmlAttribute(XmlName('Publisher'), runtimeDependencyPublisher),
  ]));
}

void _verifyRuntimeDependency(XmlElement package) {
  final dependencies = package.childElements
      .where((element) => element.name.local == 'Dependencies')
      .toList();
  if (dependencies.isEmpty) {
    throw PatchError('the manifest has no <Dependencies> section.');
  }
  final matches = dependencies.first.childElements
      .where((element) =>
          element.name.local == 'PackageDependency' &&
          element.getAttribute('Name') == runtimeDependencyName)
      .toList();
  if (matches.isEmpty) {
    throw PatchError(
      'the $runtimeDependencyName package dependency is missing. Run the '
      'patcher on the generated manifest.',
    );
  }
  if (matches.length > 1) {
    throw PatchError(
      'the $runtimeDependencyName package dependency is declared '
      '${matches.length} times.',
    );
  }
  final version = matches.single.getAttribute('MinVersion');
  if (version == null || version.isEmpty) {
    throw PatchError(
        'the $runtimeDependencyName dependency has no MinVersion.');
  }
  if (version.trim() != runtimeDependencyMinVersion) {
    throw PatchError(
      'the $runtimeDependencyName dependency has MinVersion "$version", '
      'expected "$runtimeDependencyMinVersion" (the framework package version '
      'in the pinned Windows App SDK).',
    );
  }
  final publisher =
      _normalizeDistinguishedName(matches.single.getAttribute('Publisher'));
  if (publisher != _normalizeDistinguishedName(runtimeDependencyPublisher)) {
    throw PatchError(
      'the $runtimeDependencyName dependency has publisher '
      '"${matches.single.getAttribute('Publisher')}", expected '
      '"$runtimeDependencyPublisher".',
    );
  }
}

/// Compares dot-separated version strings; null when either is unreadable.
int? _compareVersions(String left, String right) {
  final a = _versionParts(left);
  final b = _versionParts(right);
  if (a == null || b == null) {
    return null;
  }
  final length = a.length > b.length ? a.length : b.length;
  for (var index = 0; index < length; index++) {
    final valueA = index < a.length ? a[index] : 0;
    final valueB = index < b.length ? b[index] : 0;
    if (valueA != valueB) {
      return valueA < valueB ? -1 : 1;
    }
  }
  return 0;
}

List<int>? _versionParts(String value) {
  final parts = value.trim().split('.');
  if (parts.isEmpty) {
    return null;
  }
  final numbers = <int>[];
  for (final part in parts) {
    final number = int.tryParse(part);
    if (number == null || number < 0) {
      return null;
    }
    numbers.add(number);
  }
  return numbers;
}

XmlElement _singleApplication(XmlElement package) {
  final applications = package.childElements
      .where((element) => element.name.local == 'Applications')
      .toList();
  if (applications.isEmpty) {
    throw PatchError('the manifest has no <Applications> section.');
  }
  final app = applications.first.childElements
      .where((element) => element.name.local == 'Application')
      .toList();
  if (app.length != 1) {
    throw PatchError(
        'expected exactly one <Application>, found ${app.length}.');
  }
  return app.single;
}

XmlElement _ensureExtensions(XmlElement application) {
  final existing = application.childElements
      .where((element) => element.name.local == 'Extensions')
      .firstOrNull;
  if (existing != null) {
    return existing;
  }
  final created = XmlElement(XmlName('Extensions'));
  application.children.add(created);
  return created;
}

void _patchPushActivator({
  required XmlElement application,
  required XmlElement extensions,
  required String appId,
}) {
  final servers = _comServers(application).toList();
  final pushServers = servers
      .where((server) =>
          _attribute(server, 'Arguments') == pushActivationArguments)
      .toList();

  final executable = _attribute(application, 'Executable');
  if (executable == null || executable.isEmpty) {
    throw PatchError('the application has no Executable attribute.');
  }
  final applicationExecutable = _manifestExecutable(executable, 'application');

  if (pushServers.length > 1) {
    // Deterministic: keep the first push server, drop the duplicates.
    for (final duplicate in pushServers.skip(1)) {
      duplicate.parent?.children.remove(duplicate);
    }
  }

  if (pushServers.isNotEmpty) {
    final server = pushServers.first;
    final serverExecutable = _attribute(server, 'Executable');
    if (serverExecutable == null || serverExecutable.trim().isEmpty) {
      throw PatchError(
        'an existing push activation server has no Executable attribute.',
      );
    }
    if (_manifestExecutable(serverExecutable, 'push') !=
        applicationExecutable) {
      throw PatchError(
        'an existing push activation server runs "$serverExecutable" instead '
        'of "$executable". Refusing to merge two different executables.',
      );
    }
    final classes = _classes(server).toList();
    if (classes.isEmpty) {
      server.children.add(_pushClass(appId));
      return;
    }
    for (final element in classes) {
      final id = _attribute(element, 'Id');
      if (_normalizeGuid(id) != _normalizeGuid(appId)) {
        throw PatchError(
          'a push activation server already exists with class id "$id"; '
          'expected "$appId". Refusing to change an existing activation '
          'contract.',
        );
      }
    }
    for (final duplicate in classes.skip(1)) {
      server.children.remove(duplicate);
    }
    return;
  }

  var comServer = servers.isEmpty ? null : servers.first.parent;
  if (comServer == null) {
    final extension = XmlElement(XmlName('com:Extension'), [
      XmlAttribute(XmlName('Category'), 'windows.comServer'),
    ]);
    comServer = XmlElement(XmlName('com:ComServer'));
    extension.children.add(comServer);
    extensions.children.add(extension);
  }

  final server = XmlElement(XmlName('com:ExeServer'), [
    XmlAttribute(XmlName('Executable'), executable),
    XmlAttribute(
      XmlName('DisplayName'),
      _attribute(application, 'DisplayName') ?? 'Apexo',
    ),
    XmlAttribute(XmlName('Arguments'), pushActivationArguments),
  ]);
  server.children.add(_pushClass(appId));
  comServer.children.add(server);
}

XmlElement _pushClass(String appId) => XmlElement(XmlName('com:Class'), [
      XmlAttribute(XmlName('Id'), appId),
      XmlAttribute(XmlName('DisplayName'), 'Windows App SDK Push'),
    ]);

Iterable<XmlElement> _comServers(XmlElement application) sync* {
  final extensions = application.childElements
      .where((element) => element.name.local == 'Extensions');
  for (final group in extensions) {
    for (final extension in group.childElements) {
      if (extension.name.local != 'Extension' ||
          extension.name.prefix != 'com' ||
          _attribute(extension, 'Category') != 'windows.comServer') {
        continue;
      }
      for (final comServer in extension.childElements
          .where((element) => element.name.local == 'ComServer')) {
        for (final server in comServer.childElements
            .where((element) => element.name.local == 'ExeServer')) {
          yield server;
        }
      }
    }
  }
}

Iterable<XmlElement> _classes(XmlElement server) =>
    server.childElements.where((element) => element.name.local == 'Class');

String? _toastActivatorClsid(XmlElement application) {
  final extensions = application.childElements
      .where((element) => element.name.local == 'Extensions');
  for (final group in extensions) {
    for (final extension in group.childElements) {
      if (extension.name.local != 'Extension' ||
          extension.name.prefix != 'desktop' ||
          _attribute(extension, 'Category') !=
              'windows.toastNotificationActivation') {
        continue;
      }
      final activation = extension.childElements
          .where(
              (element) => element.name.local == 'ToastNotificationActivation')
          .firstOrNull;
      if (activation != null) {
        return _attribute(activation, 'ToastActivatorCLSID');
      }
    }
  }
  return null;
}

String? _attribute(XmlElement element, String localName) {
  for (final attribute in element.attributes) {
    if (attribute.name.local == localName) {
      return attribute.value;
    }
  }
  return null;
}

/// Normalizes a package-relative executable path and rejects anything that could
/// escape the package (absolute, drive-relative, UNC, rooted or `..`).
String _manifestExecutable(String? raw, String label) {
  final value = raw?.trim();
  if (value == null || value.isEmpty) {
    throw PatchError('$label executable is missing.');
  }
  final normalized = _windowsPaths.normalize(value);
  if (value.contains(':') ||
      value.startsWith('\\') ||
      value.startsWith('/') ||
      _windowsPaths.isAbsolute(value) ||
      normalized == '.' ||
      normalized == '..' ||
      normalized.startsWith('..\\')) {
    throw PatchError('$label executable must be package-relative.');
  }
  return normalized.toLowerCase();
}

void _requireMatchingExecutable(
  XmlElement application,
  XmlElement server,
  String label,
) {
  final expected =
      _manifestExecutable(_attribute(application, 'Executable'), 'application');
  final actual = _manifestExecutable(_attribute(server, 'Executable'), label);
  if (actual != expected) {
    throw PatchError(
      '$label executable does not match application executable.',
    );
  }
}

/// Patches the manifest at |path| and returns the text that was written.
///
/// The write is atomic: the patched text is written to a sibling temporary file,
/// re-verified from disk, and only then renamed over the original. Any failure
/// leaves the original manifest untouched.
String patchManifestFile(
  String path, {
  required String appId,
  required MsixConfig msix,
  required WindowsNotificationIdentity identity,
  String? objectId,
}) {
  final file = File(path);
  if (!file.existsSync()) {
    throw PatchError('manifest not found at $path');
  }
  final patched = patchManifest(file.readAsStringSync(), appId: appId);
  final temporary = File('$path.patch-$pid');
  try {
    temporary.writeAsStringSync(patched, flush: true);
    verifyManifest(
      temporary.readAsStringSync(),
      appId: appId,
      objectId: objectId,
      msix: msix,
      identity: identity,
    );
    temporary.renameSync(path);
  } finally {
    if (temporary.existsSync()) {
      temporary.deleteSync();
    }
  }
  return patched;
}

Future<void> main(List<String> arguments) async {
  _Options options;
  try {
    options = _parseArguments(arguments);
  } on PatchError catch (error) {
    stderr.writeln(error.message);
    exitCode = 2;
    return;
  }

  try {
    final config = readPushConfig(options.configPath);
    final msix = readMsixConfig(options.pubspecPath);
    final identity = readWindowsNotificationIdentity(options.identityPath);
    final appId = options.appId ?? config.appId;
    final objectId = options.objectId ?? config.objectId;

    final file = File(options.manifestPath);
    if (!file.existsSync()) {
      throw PatchError('manifest not found at ${options.manifestPath}');
    }
    final source = file.readAsStringSync();

    if (options.verify) {
      verifyManifest(
        source,
        appId: appId,
        objectId: objectId,
        msix: msix,
        identity: identity,
      );
      stdout.writeln(
        'Verified ${options.manifestPath}: identity "${msix.identityName}", '
        'publisher "${msix.publisher}", the $runtimeDependencyName '
        'dependency and both activation contracts are correct.',
      );
      return;
    }

    final patched = patchManifestFile(
      options.manifestPath,
      appId: appId,
      objectId: objectId,
      msix: msix,
      identity: identity,
    );
    stdout.writeln(
      'Patched ${options.manifestPath} (${patched.length} characters): '
      '$runtimeDependencyName dependency and the push activation server '
      '(class id $appId) are in place.',
    );
  } on PatchError catch (error) {
    stderr.writeln(error.message);
    exitCode = 2;
  } on XmlException catch (error) {
    stderr.writeln('The manifest is not valid XML: ${error.message}');
    exitCode = 2;
  }
}

class _Options {
  const _Options({
    required this.manifestPath,
    required this.configPath,
    required this.pubspecPath,
    required this.identityPath,
    required this.verify,
    this.appId,
    this.objectId,
  });

  final String manifestPath;
  final String configPath;
  final String pubspecPath;
  final String identityPath;
  final bool verify;
  final String? appId;
  final String? objectId;
}

_Options _parseArguments(List<String> arguments) {
  String? manifestPath;
  var configPath = defaultConfigPath;
  var pubspecPath = defaultPubspecPath;
  var identityPath = defaultIdentityPath;
  var verify = false;
  String? appId;
  String? objectId;

  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    switch (argument) {
      case '--verify':
        verify = true;
      case '--config':
        configPath = arguments[++index];
      case '--pubspec':
        pubspecPath = arguments[++index];
      case '--identity':
        identityPath = arguments[++index];
      case '--app-id':
        appId = arguments[++index];
      case '--object-id':
        objectId = arguments[++index];
      default:
        if (argument.startsWith('--')) {
          throw PatchError('unknown option $argument');
        }
        manifestPath ??= argument;
    }
  }

  if (manifestPath == null) {
    throw PatchError(
      'usage: dart run tools/patch_push_manifest.dart <AppxManifest.xml> '
      '[--verify] [--config push_config.h] [--pubspec pubspec.yaml] '
      '[--identity windows_notification_identity.dart] [--app-id <guid>] '
      '[--object-id <guid>]',
    );
  }
  return _Options(
    manifestPath: manifestPath,
    configPath: configPath,
    pubspecPath: pubspecPath,
    identityPath: identityPath,
    verify: verify,
    appId: appId,
    objectId: objectId,
  );
}

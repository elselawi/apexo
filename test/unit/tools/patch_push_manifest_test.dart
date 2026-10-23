@Tags(['serial'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

import '../../../tools/patch_push_manifest.dart';

const String appId = '8f4d5ac1-5142-44fb-928a-6ce05c641dd0';
const String objectId = '431f890b-3a77-4d0b-b52a-aa684ffed80d';
const String toastClsid = '51fc2ec1-f21e-4b3c-9f2b-71c28c7b0f7e';

const String identityName = 'alisaleem.apexo.app';
const String publisher = 'CN=275027E7-AE47-4DEE-B3D6-0BE5AF8D773E';

/// The AUMID the Dart side ships. Its family name matches the installed package
/// `alisaleem.apexo.app_0.15.2.0_x64__e460fpmm323ja`.
const String aumid = 'alisaleem.apexo.app_e460fpmm323ja!apexo';

const MsixConfig testMsix = MsixConfig(
  identityName: identityName,
  publisher: publisher,
  toastClsid: toastClsid,
);

const WindowsNotificationIdentity testIdentity = WindowsNotificationIdentity(
  appUserModelId: aumid,
  activationGuid: toastClsid,
);

String manifest({
  bool toast = false,
  String? pushClassId,
  String? pushArguments,
  String? pushExecutable,
  bool runtimeDependency = false,
  String runtimeDependencyMinVersionValue = runtimeDependencyMinVersion,
  String runtimeDependencyPublisherValue = runtimeDependencyPublisher,
  bool capabilities = true,
  String identityNameValue = identityName,
  String publisherValue = publisher,
  String applicationIdValue = 'apexo',
  String toastClsidValue = toastClsid,
}) {
  final extensions = <String>[];
  if (toast) {
    extensions.add('''
        <desktop:Extension Category="windows.toastNotificationActivation">
          <desktop:ToastNotificationActivation ToastActivatorCLSID="$toastClsidValue"/>
        </desktop:Extension>
        <com:Extension Category="windows.comServer">
          <com:ComServer>
            <com:ExeServer Executable="apexo.exe" DisplayName="Apexo notifications" Arguments="$toastActivationArguments">
              <com:Class Id="$toastClsidValue"/>
            </com:ExeServer>
          </com:ComServer>
        </com:Extension>''');
  }
  if (pushClassId != null) {
    extensions.add('''
        <com:Extension Category="windows.comServer">
          <com:ComServer>
            <com:ExeServer Executable="${pushExecutable ?? 'apexo.exe'}" DisplayName="Apexo" Arguments="${pushArguments ?? pushActivationArguments}">
              <com:Class Id="$pushClassId" DisplayName="Windows App SDK Push"/>
            </com:ExeServer>
          </com:ComServer>
        </com:Extension>''');
  }

  return '''
<?xml version="1.0" encoding="utf-8"?>
<Package
  xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
  xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
  xmlns:desktop="http://schemas.microsoft.com/appx/manifest/desktop/windows10"
  xmlns:desktop4="http://schemas.microsoft.com/appx/manifest/desktop/windows10/4"
  xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities"
  xmlns:com="http://schemas.microsoft.com/appx/manifest/com/windows10"
  IgnorableNamespaces="uap desktop com">
  <Identity Name="$identityNameValue" Version="1.0.0.0" Publisher="$publisherValue" ProcessorArchitecture="x64" />
  <Properties>
    <DisplayName>Apexo.app</DisplayName>
    <PublisherDisplayName>alisaleem</PublisherDisplayName>
    <Logo>Images\\StoreLogo.png</Logo>
  </Properties>
  <Dependencies>
    <TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.17763.0" MaxVersionTested="10.0.22621.2506" />
    ${runtimeDependency ? '<PackageDependency Name="$runtimeDependencyName" MinVersion="$runtimeDependencyMinVersionValue" Publisher="$runtimeDependencyPublisherValue" />' : ''}
  </Dependencies>
  ${capabilities ? '''
  <Capabilities>
    <Capability Name="internetClient" />
    <rescap:Capability Name="runFullTrust" />
  </Capabilities>''' : ''}
  <Applications>
    <Application Id="$applicationIdValue" Executable="apexo.exe" EntryPoint="Windows.FullTrustApplication" DisplayName="Apexo.app">
      <uap:VisualElements DisplayName="Apexo.app" BackgroundColor="transparent" Square150x150Logo="Images\\Square150x150Logo.png" Square44x44Logo="Images\\Square44x44Logo.png" Description="Apexo" />
      ${extensions.isEmpty ? '' : '<Extensions>${extensions.join()}</Extensions>'}
    </Application>
  </Applications>
</Package>''';
}

XmlElement applicationOf(String xml) => XmlDocument.parse(xml)
    .rootElement
    .childElements
    .firstWhere((element) => element.name.local == 'Applications')
    .childElements
    .firstWhere((element) => element.name.local == 'Application');

List<XmlElement> serversOf(String xml, {required String arguments}) {
  final servers = <XmlElement>[];
  for (final group in applicationOf(xml)
      .childElements
      .where((element) => element.name.local == 'Extensions')) {
    for (final extension in group.childElements) {
      if (extension.name.prefix != 'com') continue;
      for (final comServer in extension.childElements) {
        for (final server in comServer.childElements) {
          if (server.name.local == 'ExeServer' &&
              server.getAttribute('Arguments') == arguments) {
            servers.add(server);
          }
        }
      }
    }
  }
  return servers;
}

List<XmlElement> classesOf(XmlElement server) => server.childElements
    .where((element) => element.name.local == 'Class')
    .toList();

List<XmlElement> dependenciesOf(String xml) {
  final dependencies = XmlDocument.parse(xml)
      .rootElement
      .childElements
      .firstWhere((element) => element.name.local == 'Dependencies');
  return dependencies.childElements
      .where((element) =>
          element.name.local == 'PackageDependency' &&
          element.getAttribute('Name') == runtimeDependencyName)
      .toList();
}

String? toastClsidOf(String xml) {
  for (final group in applicationOf(xml)
      .childElements
      .where((element) => element.name.local == 'Extensions')) {
    for (final extension in group.childElements) {
      if (extension.name.prefix != 'desktop') continue;
      final activation = extension.childElements.firstWhere(
          (element) => element.name.local == 'ToastNotificationActivation');
      return activation.getAttribute('ToastActivatorCLSID');
    }
  }
  return null;
}

/// Verifies with the fixtures, overriding only what a test varies.
void verifyOk(
  String xml, {
  String appIdValue = appId,
  String objectIdValue = objectId,
  MsixConfig msix = testMsix,
  WindowsNotificationIdentity identity = testIdentity,
}) {
  verifyManifest(
    xml,
    appId: appIdValue,
    objectId: objectIdValue,
    msix: msix,
    identity: identity,
  );
}

Matcher throwsPatchError() => throwsA(
      isA<PatchError>().having((error) => error.message, 'message', isNotEmpty),
    );

void main() {
  group('patch', () {
    test('a manifest with no extensions gains the dependency and push server',
        () {
      final patched = patchManifest(manifest(), appId: appId);

      expect(dependenciesOf(patched), hasLength(1));
      final servers = serversOf(patched, arguments: pushActivationArguments);
      expect(servers, hasLength(1));
      expect(servers.single.getAttribute('Executable'), 'apexo.exe');
      expect(classesOf(servers.single).single.getAttribute('Id'), appId);
      expect(toastClsidOf(patched), isNull);

      // The local toast contract is the msix tool's job; the patcher must not
      // invent one, and verification says so.
      expect(() => verifyOk(patched), throwsPatchError());
    });

    test('a toast-only manifest keeps its contract and gains the push one', () {
      final patched = patchManifest(manifest(toast: true), appId: appId);

      expect(toastClsidOf(patched), toastClsid,
          reason: 'the toast CLSID must not change');
      final toastServers =
          serversOf(patched, arguments: toastActivationArguments);
      expect(toastServers, hasLength(1));
      expect(toastServers.single.getAttribute('Executable'), 'apexo.exe');
      expect(
          classesOf(toastServers.single).single.getAttribute('Id'), toastClsid,
          reason: 'the toast class id must not change');

      final pushServers =
          serversOf(patched, arguments: pushActivationArguments);
      expect(pushServers, hasLength(1));
      expect(classesOf(pushServers.single).single.getAttribute('Id'), appId);

      verifyOk(patched);
    });

    test('patching twice changes nothing else and adds no duplicates', () {
      final once = patchManifest(manifest(toast: true), appId: appId);
      final twice = patchManifest(once, appId: appId);

      expect(dependenciesOf(twice), hasLength(1));
      expect(
          serversOf(twice, arguments: pushActivationArguments), hasLength(1));
      expect(
          serversOf(twice, arguments: toastActivationArguments), hasLength(1));
      expect(
        classesOf(serversOf(twice, arguments: pushActivationArguments).single),
        hasLength(1),
      );
      verifyOk(twice);
    });

    test('an already-patched manifest is left alone', () {
      final patched = patchManifest(manifest(toast: true), appId: appId);
      final again = patchManifest(patched, appId: appId);

      expect(again, patched);
      expect(
        utf8.encode(again),
        utf8.encode(patched),
        reason: 'a second pass must be byte-for-byte identical',
      );
    });

    test('a conflicting push class id is refused', () {
      final conflicting = manifest(
        toast: true,
        pushClassId: '00000000-1111-2222-3333-444444444444',
      );

      expect(
          () => patchManifest(conflicting, appId: appId), throwsPatchError());
      expect(() => verifyOk(conflicting), throwsPatchError());
    });

    test('a push server for another executable is refused', () {
      final conflicting = manifest(
        toast: true,
        pushClassId: appId,
        pushExecutable: 'other.exe',
      );

      expect(
          () => patchManifest(conflicting, appId: appId), throwsPatchError());
    });

    test('an all-zero application id is refused before anything is written',
        () {
      expect(
          () => patchManifest(manifest(), appId: zeroGuid), throwsPatchError());
    });

    test('a lower runtime dependency MinVersion is raised to the pinned one',
        () {
      final patched = patchManifest(
        manifest(
          toast: true,
          runtimeDependency: true,
          runtimeDependencyMinVersionValue: '7000.0.0.0',
        ),
        appId: appId,
      );

      expect(dependenciesOf(patched), hasLength(1));
      expect(
        dependenciesOf(patched).single.getAttribute('MinVersion'),
        runtimeDependencyMinVersion,
      );
      expect(
        dependenciesOf(patched).single.getAttribute('Publisher'),
        runtimeDependencyPublisher,
      );
    });

    test('a newer runtime dependency MinVersion is refused', () {
      final newer = manifest(
        toast: true,
        runtimeDependency: true,
        runtimeDependencyMinVersionValue: '7000.999.0.0',
      );

      expect(() => patchManifest(newer, appId: appId), throwsPatchError());
    });
  });

  group('patch file', () {
    late Directory folder;

    setUp(() => folder = Directory.systemTemp.createTempSync('apexo-patch-'));
    tearDown(() {
      if (folder.existsSync()) {
        folder.deleteSync(recursive: true);
      }
    });

    test('writes the patched manifest and leaves no temporary file', () {
      final file = File('${folder.path}/AppxManifest.xml')
        ..writeAsStringSync(manifest(toast: true));

      final patched = patchManifestFile(
        file.path,
        appId: appId,
        objectId: objectId,
        msix: testMsix,
        identity: testIdentity,
      );

      expect(file.readAsStringSync(), patched);
      expect(
        folder.listSync(),
        hasLength(1),
        reason: 'the temporary file must be gone',
      );
    });

    test('a failing patch leaves the original file untouched', () {
      final original = manifest(toast: true);
      final file = File('${folder.path}/AppxManifest.xml')
        ..writeAsStringSync(original);

      expect(
        () => patchManifestFile(
          file.path,
          appId: appId,
          objectId: objectId,
          // A toast CLSID that disagrees with the manifest fails verification of
          // the temporary file, after the patch itself succeeded.
          msix: const MsixConfig(
            identityName: identityName,
            publisher: publisher,
            toastClsid: '11111111-2222-3333-4444-555555555555',
          ),
          identity: testIdentity,
        ),
        throwsPatchError(),
      );

      expect(file.readAsStringSync(), original);
      expect(folder.listSync(), hasLength(1));
    });
  });

  group('verify', () {
    test('accepts the complete contract', () {
      final patched = patchManifest(manifest(toast: true), appId: appId);
      expect(() => verifyOk(patched), returnsNormally);
    });

    test('rejects a manifest with no runtime dependency', () {
      final patched = patchManifest(manifest(toast: true), appId: appId);
      final withoutDependency =
          patched.replaceAll(RegExp(r'<PackageDependency[^>]*/>'), '');

      expect(() => verifyOk(withoutDependency), throwsPatchError());
    });

    test('rejects a runtime dependency with the wrong MinVersion', () {
      final patched = patchManifest(
        manifest(
          toast: true,
          runtimeDependency: true,
          runtimeDependencyMinVersionValue: '7000.0.0.0',
        ),
        appId: appId,
      );
      // Undo the upgrade the patcher performed, as an older package would be.
      final stale = patched.replaceFirst(
        'MinVersion="$runtimeDependencyMinVersion"',
        'MinVersion="7000.0.0.0"',
      );

      expect(() => verifyOk(stale), throwsPatchError());
    });

    test('rejects a runtime dependency with the wrong publisher', () {
      final patched = patchManifest(
        manifest(toast: true, runtimeDependency: true),
        appId: appId,
      ).replaceFirst(runtimeDependencyPublisher, 'CN=Someone Else');

      expect(() => verifyOk(patched), throwsPatchError());
    });

    test('rejects a missing push server', () {
      final valid = patchManifest(manifest(toast: true), appId: appId);
      verifyOk(valid);
      final document = XmlDocument.parse(valid);
      final pushServers = document.descendants.whereType<XmlElement>().where(
            (element) =>
                element.name.local == 'ExeServer' &&
                element.getAttribute('Arguments') == pushActivationArguments,
          );
      for (final server in pushServers.toList()) {
        server.parent?.children.remove(server);
      }

      expect(
        () => verifyOk(document.toXmlString()),
        throwsA(isA<PatchError>().having(
          (error) => error.message,
          'message',
          contains('push activation server is missing'),
        )),
      );
    });

    test('rejects a wrong push class id even with the right arguments', () {
      final valid = patchManifest(manifest(toast: true), appId: appId);
      verifyOk(valid);
      final document = XmlDocument.parse(valid);
      final classElement =
          document.descendants.whereType<XmlElement>().singleWhere(
                (element) =>
                    element.name.local == 'Class' &&
                    element.parentElement?.getAttribute('Arguments') ==
                        pushActivationArguments,
              );
      classElement.setAttribute(
        'Id',
        '00000000-1111-2222-3333-444444444444',
      );

      expect(
        () => verifyOk(document.toXmlString()),
        throwsA(isA<PatchError>().having(
          (error) => error.message,
          'message',
          contains('push activation class id'),
        )),
      );
    });

    test('rejects a push class that reuses the toast CLSID', () {
      final valid = patchManifest(manifest(toast: true), appId: appId);
      verifyOk(valid);
      final document = XmlDocument.parse(valid);
      final classElement =
          document.descendants.whereType<XmlElement>().singleWhere(
                (element) =>
                    element.name.local == 'Class' &&
                    element.parentElement?.getAttribute('Arguments') ==
                        pushActivationArguments,
              );
      classElement.setAttribute('Id', toastClsid);

      expect(
        () => verifyOk(document.toXmlString()),
        throwsA(isA<PatchError>().having(
          (error) => error.message,
          'message',
          contains('class id'),
        )),
      );
    });

    test('rejects a toast contract that reuses the push application id', () {
      final collision = patchManifest(manifest(toast: true), appId: appId)
          .replaceAll(toastClsid, appId);

      expect(() => verifyOk(collision), throwsPatchError());
    });

    test('rejects an all-zero application id', () {
      expect(
        () => verifyOk(manifest(), appIdValue: zeroGuid),
        throwsPatchError(),
      );
    });

    test('rejects an all-zero Object ID', () {
      expect(
        () => verifyOk(manifest(), objectIdValue: zeroGuid),
        throwsPatchError(),
      );
    });

    test('rejects the Object ID being used as the application id', () {
      expect(
        () => verifyOk(manifest(), appIdValue: objectId),
        throwsPatchError(),
      );
    });

    test('rejects duplicate push servers', () {
      final patched = patchManifest(manifest(toast: true), appId: appId);
      final duplicated = patched.replaceFirst(
        '</com:ComServer>',
        '</com:ComServer><com:ComServer><com:ExeServer '
            'Executable="apexo.exe" Arguments="$pushActivationArguments">'
            '<com:Class Id="$appId"/></com:ExeServer></com:ComServer>',
      );

      expect(() => verifyOk(duplicated), throwsPatchError());
    });

    test('rejects a wrong package identity name', () {
      final patched = patchManifest(
        manifest(toast: true, identityNameValue: 'someone.else.app'),
        appId: appId,
      );

      expect(() => verifyOk(patched), throwsPatchError());
    });

    test('rejects a wrong publisher', () {
      final patched = patchManifest(
        manifest(toast: true, publisherValue: 'CN=Someone Else'),
        appId: appId,
      );

      expect(() => verifyOk(patched), throwsPatchError());
    });

    test('explains the msix test-certificate publisher', () {
      final patched = patchManifest(
        manifest(
          toast: true,
          publisherValue: 'CN=Msix Testing, O=Msix Testing Corporation, '
              'S=Some-State, C=US',
        ),
        appId: appId,
      );

      expect(
        () => verifyOk(patched),
        throwsA(isA<PatchError>().having(
          (error) => error.message,
          'message',
          contains('--sign-msix false'),
        )),
      );
    });

    test('rejects a wrong application id', () {
      final patched = patchManifest(
        manifest(toast: true, applicationIdValue: 'other'),
        appId: appId,
      );

      expect(() => verifyOk(patched), throwsPatchError());
    });

    test('rejects an AUMID that does not match the identity name', () {
      final patched = patchManifest(manifest(toast: true), appId: appId);

      expect(
        () => verifyOk(
          patched,
          identity: const WindowsNotificationIdentity(
            appUserModelId: 'someone.else.app_e460fpmm323ja!apexo',
            activationGuid: toastClsid,
          ),
        ),
        throwsPatchError(),
      );
    });

    test('rejects a malformed AUMID', () {
      final patched = patchManifest(manifest(toast: true), appId: appId);

      expect(
        () => verifyOk(
          patched,
          identity: const WindowsNotificationIdentity(
            appUserModelId: 'alisaleem.apexo.app!apexo',
            activationGuid: toastClsid,
          ),
        ),
        throwsPatchError(),
      );
    });

    test('rejects a toast CLSID that is not the shared activation GUID', () {
      final patched = patchManifest(manifest(toast: true), appId: appId);

      expect(
        () => verifyOk(
          patched,
          identity: const WindowsNotificationIdentity(
            appUserModelId: aumid,
            activationGuid: '11111111-2222-3333-4444-555555555555',
          ),
        ),
        throwsPatchError(),
      );
    });

    test('rejects a pubspec toast CLSID that disagrees with the Dart GUID', () {
      final patched = patchManifest(manifest(toast: true), appId: appId);

      expect(
        () => verifyOk(
          patched,
          msix: const MsixConfig(
            identityName: identityName,
            publisher: publisher,
            toastClsid: '11111111-2222-3333-4444-555555555555',
          ),
        ),
        throwsPatchError(),
      );
    });

    test('rejects a manifest without capabilities', () {
      final patched = patchManifest(
        manifest(toast: true, capabilities: false),
        appId: appId,
      );

      expect(() => verifyOk(patched), throwsPatchError());
    });

    test('rejects a manifest without runFullTrust', () {
      final patched = patchManifest(manifest(toast: true), appId: appId)
          .replaceAll(RegExp(r'<rescap:Capability[^>]*/>'), '');

      expect(() => verifyOk(patched), throwsPatchError());
    });

    test('rejects a runFullTrust that is not a restricted capability', () {
      final patched =
          patchManifest(manifest(toast: true), appId: appId).replaceAll(
        RegExp(r'<rescap:Capability[^>]*runFullTrust[^>]*/>'),
        '<Capability Name="runFullTrust"/>',
      );

      expect(() => verifyOk(patched), throwsPatchError());
    });

    test('rejects a different toast executable, not just a different basename',
        () {
      final valid = patchManifest(manifest(toast: true), appId: appId);
      verifyOk(valid);
      final document = XmlDocument.parse(valid);
      final server = document.descendants.whereType<XmlElement>().singleWhere(
            (element) =>
                element.name.local == 'ExeServer' &&
                element.getAttribute('Arguments') == toastActivationArguments,
          );
      server.setAttribute('Executable', 'bin\\apexo.exe');

      expect(
        () => verifyOk(document.toXmlString()),
        throwsA(isA<PatchError>().having(
          (error) => error.message,
          'message',
          contains('toast executable does not match'),
        )),
      );
    });

    test('rejects a different push executable, not just a different basename',
        () {
      final valid = patchManifest(manifest(toast: true), appId: appId);
      verifyOk(valid);
      final document = XmlDocument.parse(valid);
      final server = document.descendants.whereType<XmlElement>().singleWhere(
            (element) =>
                element.name.local == 'ExeServer' &&
                element.getAttribute('Arguments') == pushActivationArguments,
          );
      server.setAttribute('Executable', 'other.exe');

      expect(
        () => verifyOk(document.toXmlString()),
        throwsA(isA<PatchError>().having(
          (error) => error.message,
          'message',
          contains('push executable does not match'),
        )),
      );
    });

    test('rejects a missing toast executable', () {
      final valid = patchManifest(manifest(toast: true), appId: appId);
      verifyOk(valid);
      final document = XmlDocument.parse(valid);
      final server = document.descendants.whereType<XmlElement>().singleWhere(
            (element) =>
                element.name.local == 'ExeServer' &&
                element.getAttribute('Arguments') == toastActivationArguments,
          );
      server.attributes
          .removeWhere((attribute) => attribute.name.local == 'Executable');

      expect(
        () => verifyOk(document.toXmlString()),
        throwsA(isA<PatchError>().having(
          (error) => error.message,
          'message',
          contains('toast executable is missing'),
        )),
      );
    });

    test('rejects a missing push executable', () {
      final valid = patchManifest(manifest(toast: true), appId: appId);
      verifyOk(valid);
      final document = XmlDocument.parse(valid);
      final server = document.descendants.whereType<XmlElement>().singleWhere(
            (element) =>
                element.name.local == 'ExeServer' &&
                element.getAttribute('Arguments') == pushActivationArguments,
          );
      server.attributes
          .removeWhere((attribute) => attribute.name.local == 'Executable');

      expect(
        () => verifyOk(document.toXmlString()),
        throwsA(isA<PatchError>().having(
          (error) => error.message,
          'message',
          contains('push executable is missing'),
        )),
      );
    });

    test('rejects absolute, drive-relative and escaping executables', () {
      final valid = patchManifest(manifest(toast: true), appId: appId);
      verifyOk(valid);
      for (final value in [
        'C:\\tools\\apexo.exe',
        'C:apexo.exe',
        '\\\\server\\share\\apexo.exe',
        '..\\apexo.exe',
        'bin\\..\\..\\apexo.exe',
      ]) {
        final document = XmlDocument.parse(valid);
        final server = document.descendants.whereType<XmlElement>().singleWhere(
              (element) =>
                  element.name.local == 'ExeServer' &&
                  element.getAttribute('Arguments') == toastActivationArguments,
            );
        server.setAttribute('Executable', value);
        expect(
          () => verifyOk(document.toXmlString()),
          throwsA(isA<PatchError>().having(
            (error) => error.message,
            'message',
            contains('package-relative'),
          )),
          reason: '$value must not be accepted as package-relative',
        );
      }
    });

    test('accepts case and separator differences in executable paths', () {
      final valid = patchManifest(manifest(toast: true), appId: appId);
      verifyOk(valid);
      final document = XmlDocument.parse(valid);
      for (final server in document.descendants.whereType<XmlElement>().where(
            (element) =>
                element.name.local == 'ExeServer' &&
                (element.getAttribute('Arguments') ==
                        toastActivationArguments ||
                    element.getAttribute('Arguments') ==
                        pushActivationArguments),
          )) {
        server.setAttribute('Executable', '.\\APEXO.EXE');
      }

      expect(() => verifyOk(document.toXmlString()), returnsNormally);
    });

    test('rejects a changed application executable before either contract', () {
      final valid = patchManifest(manifest(toast: true), appId: appId);
      verifyOk(valid);
      final document = XmlDocument.parse(valid);
      final application = document.descendants
          .whereType<XmlElement>()
          .singleWhere((element) => element.name.local == 'Application');
      application.setAttribute('Executable', 'other.exe');

      expect(
        () => verifyOk(document.toXmlString()),
        throwsA(isA<PatchError>().having(
          (error) => error.message,
          'message',
          contains('does not match application executable'),
        )),
      );
    });
  });

  group('readers', () {
    late Directory folder;

    setUp(() => folder = Directory.systemTemp.createTempSync('apexo-readers-'));
    tearDown(() {
      if (folder.existsSync()) {
        folder.deleteSync(recursive: true);
      }
    });

    test('readMsixConfig reads identity, publisher and toast CLSID', () {
      final file = File('${folder.path}/pubspec.yaml')..writeAsStringSync('''
name: apexo
msix_config:
  identity_name: $identityName
  publisher: "$publisher"
  toast_activator:
    clsid: $toastClsid
    arguments: $toastActivationArguments
''');

      final config = readMsixConfig(file.path);

      expect(config.identityName, identityName);
      expect(config.publisher, publisher);
      expect(config.toastClsid, toastClsid);
    });

    test('readMsixConfig fails without a toast activator', () {
      final file = File('${folder.path}/pubspec.yaml')..writeAsStringSync('''
name: apexo
msix_config:
  identity_name: $identityName
  publisher: "$publisher"
''');

      expect(() => readMsixConfig(file.path), throwsPatchError());
    });

    test('readWindowsNotificationIdentity reads the AUMID and toast GUID', () {
      final file = File('${folder.path}/identity.dart')..writeAsStringSync('''
abstract final class WindowsNotificationIdentity {
  static const String appName = "Apexo";
  static const String appUserModelId = "$aumid";
  static const String activationGuid = "$toastClsid";
}
''');

      final identity = readWindowsNotificationIdentity(file.path);

      expect(identity.appUserModelId, aumid);
      expect(identity.activationGuid, toastClsid);
      expect(identity.applicationId, 'apexo');
      expect(identity.packageFamilyName, 'alisaleem.apexo.app_e460fpmm323ja');
      expect(identity.publisherHash, 'e460fpmm323ja');
    });

    test('readWindowsNotificationIdentity fails without the AUMID', () {
      final file = File('${folder.path}/identity.dart')..writeAsStringSync('''
abstract final class WindowsNotificationIdentity {
  static const String activationGuid = "$toastClsid";
}
''');

      expect(
        () => readWindowsNotificationIdentity(file.path),
        throwsPatchError(),
      );
    });
  });
}

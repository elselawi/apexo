@Tags(['serial'])
library;

import 'dart:convert';

import 'package:apexo/features/settings/services_settings/auth_settings.dart';
import 'package:apexo/features/settings/services_settings/backups_settings.dart';
import 'package:apexo/features/settings/services_settings/file_upload_settings.dart';
import 'package:apexo/features/settings/services_settings/meta_settings.dart';
import 'package:apexo/features/settings/services_settings/s3_settings.dart';
import 'package:apexo/features/settings/services_settings/smtp_settings.dart';
import 'package:apexo/features/settings/services_settings/backup_file_tile.dart';
import 'package:apexo/services/backups.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:apexo/features/settings/settings_screen.dart';
import 'package:apexo/features/settings/settings_card.dart';
import 'package:apexo/features/settings/settings_section.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/network.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/pump_app.dart';

void main() {
  late String savedToken;
  late String savedAdminId;
  late bool savedOnline;
  late int savedLocale;

  setUp(() {
    savedLocale = locale.selected();
    savedToken = login.token;
    savedAdminId = login.adminCollectionId;
    savedOnline = network.isOnline();
    login.token = '';
    network.isOnline(false);
  });

  tearDown(() {
    locale.select(savedLocale);
    login.token = savedToken;
    login.adminCollectionId = savedAdminId;
    network.isOnline(savedOnline);
  });

  Future<void> size(WidgetTester tester, Size value) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = value;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpAndSettle();
  }

  testWidgets('compact category picker exposes inline calendar controls',
      (tester) async {
    await size(tester, const Size(360, 800));
    await pumpApexoApp(tester, const SettingsScreen());
    expect(find.byType(Expander), findsNothing);
    expect(find.byKey(const Key('language_combo')), findsOneWidget);
    expect(find.byKey(WK.settingsItem('currency')), findsNothing);
    expect(find.byKey(WK.serviceSection('meta_settings')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('settings_category_picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(txt('calendar')).last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dateFormat_combo')), findsOneWidget);
    expect(find.byKey(const Key('language_combo')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('category changes and resizing preserve unsaved clinic edits',
      (tester) async {
    login.adminCollectionId = 'test-admin';
    login.token = 'x.${base64Encode(utf8.encode('test-admin'))}.x';
    await size(tester, const Size(1400, 900));
    await pumpApexoApp(tester, const SettingsScreen());
    final clinic = find.byKey(const ValueKey('settings_category_clinic'));
    await tester.tap(clinic);
    await tester.pumpAndSettle();
    final field = find.byKey(const Key('currency_text_field'));
    await tester.enterText(field, 'unsaved');
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('settings_category_preferences')));
    await tester.pumpAndSettle();
    await tester.tap(clinic);
    await tester.pumpAndSettle();
    expect(tester.widget<TextBox>(field).controller!.text, 'unsaved');

    tester.view.physicalSize = const Size(360, 800);
    await tester.pumpAndSettle();
    expect(tester.widget<TextBox>(field).controller!.text, 'unsaved');
    expect(
        tester
            .widget<ComboBox<SettingsSection>>(
                find.byKey(const ValueKey('settings_category_picker')))
            .value,
        SettingsSection.clinic);
    expect(tester.takeException(), isNull);
  });

  for (final rtl in [false, true]) {
    testWidgets(
        'settings adapt to large text in ${rtl ? 'RTL dark' : 'LTR light'} mode',
        (tester) async {
      await size(tester, const Size(320, 800));
      await pumpApexoApp(
        tester,
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: Directionality(
            textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
            child: const SettingsScreen(),
          ),
        ),
        theme: rtl ? ThemeMode.dark : ThemeMode.light,
      );
      expect(find.byKey(const Key('language_combo')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [360.0, 1400.0]) {
    testWidgets('backups has its own category at width $width', (tester) async {
      login.adminCollectionId = 'test-admin';
      login.token = 'x.${base64Encode(utf8.encode('test-admin'))}.x';
      network.isOnline(true);
      await size(tester, Size(width, 900));
      await pumpApexoApp(tester, const SettingsScreen());

      Future<void> select(SettingsSection section) async {
        if (width >= 900) {
          await tester
              .tap(find.byKey(ValueKey('settings_category_${section.name}')));
        } else {
          await tester
              .tap(find.byKey(const ValueKey('settings_category_picker')));
          await tester.pumpAndSettle();
          await tester.tap(find.text(txt(section.titleKey)).last);
        }
        await tester.pumpAndSettle();
      }

      await select(SettingsSection.backups);
      expect(find.byKey(WK.serviceSection('backups')), findsOneWidget);
      expect(find.byType(FileUploadSettings), findsNothing);
      expect(find.byType(S3Settings), findsNothing);
      expect(settingsSectionFor('backups'), SettingsSection.backups);

      await select(SettingsSection.storage);
      expect(find.byType(BackupsSettings), findsNothing);
      expect(find.byType(FileUploadSettings), findsOneWidget);
      expect(find.byType(S3Settings), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [320.0, 1200.0]) {
    for (final rtl in [false, true]) {
      testWidgets('storage controls align at the end at width $width, RTL $rtl',
          (tester) async {
        login.adminCollectionId = 'test-admin';
        login.token = 'x.${base64Encode(utf8.encode('test-admin'))}.x';
        network.isOnline(true);
        await size(tester, Size(width, 900));
        await pumpApexoApp(
            tester,
            Directionality(
              textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
              child: const SettingsScreen(),
            ));
        if (width >= 900) {
          await tester
              .tap(find.byKey(const ValueKey('settings_category_storage')));
        } else {
          await tester
              .tap(find.byKey(const ValueKey('settings_category_picker')));
          await tester.pumpAndSettle();
          await tester.tap(find.text(txt('settingsStorage')).last);
        }
        await tester.pumpAndSettle();

        final upload = find.byKey(WK.serviceSection('file_upload_settings'));
        final cache = find.byKey(WK.settingsItem('cacheReset'));
        for (final entry in [
          (
            upload,
            find.byKey(WK.serviceField('file_upload_maxSize')),
            txt('file_upload_info_title')
          ),
          (
            cache,
            find
                .descendant(of: cache, matching: find.byType(FilledButton))
                .first,
            txt('cacheReset')
          ),
        ]) {
          await tester.ensureVisible(entry.$1);
          await tester.pumpAndSettle();
          final title = tester.getRect(find
              .descendant(of: entry.$1, matching: find.text(entry.$3))
              .first);
          final control = tester.getRect(entry.$2);
          expect(control.width, lessThanOrEqualTo(260));
          if (width >= 900) {
            expect(control.top, closeTo(title.top, 1));
            expect(
                rtl ? control.right < title.left : control.left > title.right,
                isTrue);
          } else {
            expect(control.top, greaterThan(title.bottom));
          }
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final (width, rtl, scale) in [
    (320.0, false, 1.0),
    (320.0, true, 1.5),
    (1100.0, false, 1.0),
    (1100.0, true, 1.5),
  ]) {
    testWidgets(
        'backup file grid adapts at width $width, RTL $rtl, scale $scale',
        (tester) async {
      final original = backups.list();
      addTearDown(() => backups.list(original));
      final files = List.generate(
          5,
          (index) => BackupFile(BackupFileInfo(
                key: 'backup_20261102_very_long_clinic_archive_$index.zip',
                modified: '2026-11-02T00:00:00Z',
                size: 125 * 1024 * 1024,
              )));
      backups.list(files);
      locale.select(rtl ? 1 : 0);
      await size(tester, Size(width, 900));
      await pumpApexoApp(
          tester,
          MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Directionality(
              textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
              child: const SingleChildScrollView(child: BackupsSettings()),
            ),
          ));
      expect(find.byType(BackupFileTile), findsNWidgets(5));
      final first = find.byKey(WK.backupRow(files[0].key));
      final second = find.byKey(WK.backupRow(files[1].key));
      final firstRect = tester.getRect(first);
      final secondRect = tester.getRect(second);
      if (width >= 900) {
        expect(secondRect.top, closeTo(firstRect.top, 1));
        expect(
            rtl
                ? secondRect.left < firstRect.left
                : secondRect.left > firstRect.left,
            isTrue);
      } else {
        expect(secondRect.top, greaterThan(firstRect.bottom));
      }
      for (final icon in [
        FluentIcons.download,
        FluentIcons.update_restore,
        WindowsIcons.delete
      ]) {
        expect(find.descendant(of: first, matching: find.byIcon(icon)),
            findsOneWidget);
      }
      await tester.ensureVisible(first);
      await tester.tap(find.descendant(
          of: first, matching: find.byIcon(FluentIcons.update_restore)));
      await tester.pumpAndSettle();
      expect(find.byType(ContentDialog), findsOneWidget);
      Navigator.of(tester.element(find.byType(ContentDialog))).pop();
      await tester.pumpAndSettle();
      backups.list(files.skip(1).toList());
      await tester.pumpAndSettle();
      expect(find.byKey(WK.backupRow(files[0].key)), findsNothing);
      expect(find.byType(BackupFileTile), findsNWidgets(4));
    });
  }

  for (final theme in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('settings cards have subtle depth in $theme', (tester) async {
      await pumpApexoApp(
          tester,
          const SingleChildScrollView(
            child: SettingsCard(
              leading: Icon(FluentIcons.settings),
              header: Text('Settings'),
            ),
          ),
          theme: theme);
      final container = tester.widget<Container>(find
          .descendant(
            of: find.byType(SettingsCard),
            matching: find.byType(Container),
          )
          .first);
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.boxShadow, isNotEmpty);
      expect(decoration.boxShadow!.every((shadow) => shadow.blurRadius > 0),
          isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  final services = <String, Widget>{
    'meta': const MetaSettings(),
    'auth': const AuthSettings(),
    'uploads': const FileUploadSettings(),
    's3': const S3Settings(),
    'smtp': const SmtpSettings(),
    'backups': const BackupsSettings(),
  };
  for (final entry in services.entries) {
    for (final rtl in [false, true]) {
      testWidgets(
          '${entry.key} form fits a narrow ${rtl ? 'RTL large text' : 'LTR'} screen',
          (tester) async {
        await size(tester, const Size(320, 800));
        locale.select(rtl ? 1 : 0);
        await pumpApexoApp(
          tester,
          MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(rtl ? 1.5 : 1)),
            child: Directionality(
              textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
              child: SingleChildScrollView(
                  child: Padding(
                padding: const EdgeInsets.all(12),
                child: entry.value,
              )),
            ),
          ),
          theme: rtl ? ThemeMode.dark : ThemeMode.light,
        );
        expect(find.byType(Expander), findsNothing);
        expect(find.byType(TextBox), findsWidgets);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('backup file tiles fit details and actions on compact screens',
      (tester) async {
    await size(tester, const Size(320, 800));
    await pumpApexoApp(
        tester,
        SingleChildScrollView(
          child: BackupFileTile(
            modifiedLabel: 'November 2, 2026',
            fileName: 'backup_20261102_clinic_archive.zip',
            sizeLabel: '125 MB',
            actions: [
              for (final icon in [
                FluentIcons.download,
                FluentIcons.delete,
                FluentIcons.update_restore
              ])
                IconButton(icon: Icon(icon), onPressed: () {}),
            ],
          ),
        ));
    expect(find.byType(IconButton), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });
}

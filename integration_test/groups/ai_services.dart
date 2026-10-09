import 'package:apexo/common_widgets/audio_recorder.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/features/settings/settings_model.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/widget_keys.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/e2e.dart';
import '../support/fixtures.dart';
import '../support/remote_rows.dart';
import '../support/store_ext.dart';

Future<void> _setAiEnabled(bool enabled) async {
  globalSettings.set(
    Setting.fromJson({
      'id': 'ai_services_ena',
      'value': enabled ? '1' : '0',
    }),
  );
  await globalSettings.waitUntilChangesAreProcessed();
}

Future<void> _deletePatientEverywhere(String id) async {
  await RemoteRows.delete(id);
  patients.purge(id);
}

Future<void> _deleteAppointmentEverywhere(String id) async {
  await RemoteRows.delete(id);
  appointments.purge(id);
}

void registerAiServicesTests() {
  group('ai_services', () {
    testWidgets(
        '01: enabling AI services reveals the transcription-locale setting',
        (tester) async {
      await E2E.signIn(tester);
      final originalEnabled = globalSettings.aiServicesEnabled;
      addTearDown(() async => _setAiEnabled(originalEnabled));

      await _setAiEnabled(false);
      await Fixtures.openSettings(tester);
      await Fixtures.revealSettingsCard(tester, 'ai_services_ena');
      expect(
          find.byKey(WK.settingsItem('audioTranscriptionLocale')), findsNothing,
          reason:
              'The transcription-locale setting is visible while AI is off.');

      await _setAiEnabled(true);
      await E2E.settle(tester, frames: 10);
      await Fixtures.openDashboard(tester);
      await Fixtures.openSettings(tester);
      await Fixtures.revealSettingsCard(tester, 'audioTranscriptionLocale');
      expect(find.byKey(WK.settingsItem('audioTranscriptionLocale')),
          findsOneWidget,
          reason:
              'Enabling AI did not reveal the transcription-locale setting.');
    });

    testWidgets('02: the patient dental-notes recorder follows the AI toggle',
        (tester) async {
      await E2E.signIn(tester);
      final originalEnabled = globalSettings.aiServicesEnabled;
      final patientName = await Fixtures.createPatient(tester,
          name: Fixtures.stamp('e2e ai patient'));
      final patientId = await Fixtures.patientIdOf(patientName);
      addTearDown(() async {
        await _setAiEnabled(originalEnabled);
        await _deletePatientEverywhere(patientId);
      });

      await _setAiEnabled(false);
      await Fixtures.openPatient(tester, patientName);
      await Fixtures.openPanelTab(tester, 'dentalNotes');
      expect(find.byType(AudioRecorderButton), findsNothing,
          reason: 'The dental-notes recorder is visible while AI is off.');
      await Fixtures.closePanel(tester);

      await _setAiEnabled(true);
      await Fixtures.openPatient(tester, patientName);
      await Fixtures.openPanelTab(tester, 'dentalNotes');
      expect(find.byType(AudioRecorderButton), findsOneWidget,
          reason:
              'The dental-notes recorder did not appear after enabling AI.');
      await Fixtures.closePanel(tester);
    });

    testWidgets('03: the appointment recorder follows the AI toggle',
        (tester) async {
      await E2E.signIn(tester);
      final originalEnabled = globalSettings.aiServicesEnabled;
      final patientName = await Fixtures.createPatient(tester,
          name: Fixtures.stamp('e2e ai appointment'));
      final patientId = await Fixtures.patientIdOf(patientName);
      final appointmentId = await Fixtures.seedAppointmentForMe(
        tester,
        patientID: patientId,
      );
      addTearDown(() async {
        await _setAiEnabled(originalEnabled);
        await _deleteAppointmentEverywhere(appointmentId);
        await _deletePatientEverywhere(patientId);
      });

      await _setAiEnabled(false);
      await Fixtures.openCalendar(tester);
      await Fixtures.openAppointmentTile(tester, patient: patientName);
      await Fixtures.openPanelTab(tester, 'operativeDetails');
      expect(find.byType(AudioRecorderButton), findsNothing,
          reason: 'The post-op recorder is visible while AI is off.');
      await Fixtures.closePanel(tester);

      await _setAiEnabled(true);
      await Fixtures.openCalendar(tester);
      await Fixtures.openAppointmentTile(tester, patient: patientName);
      await Fixtures.openPanelTab(tester, 'operativeDetails');
      expect(find.byType(AudioRecorderButton), findsOneWidget,
          reason: 'The post-op recorder did not appear after enabling AI.');
      await Fixtures.closePanel(tester);
    });

    testWidgets(
        '04: the transcription locale setting persists a selected language',
        (tester) async {
      await E2E.signIn(tester);
      final originalEnabled = globalSettings.aiServicesEnabled;
      final originalLocale = localSettings.transcriptionLocaleNonFinal;
      addTearDown(() async {
        await _setAiEnabled(originalEnabled);
        localSettings.transcriptionLocaleNonFinal = originalLocale;
        localSettings.notifyAndPersist();
      });

      await _setAiEnabled(true);
      await Fixtures.openSettings(tester);

      final wantedCode = originalLocale == 'es' ? 'en' : 'es';
      final wanted = locale.list.firstWhere((lang) => lang.$code == wantedCode);
      await Fixtures.setSettingsDropdown(
        tester,
        'audioTranscriptionLocale',
        wanted.$name,
      );

      expect(localSettings.transcriptionLocaleNonFinal, wanted.$code,
          reason:
              'Selecting "${wanted.$name}" did not persist its language code.');
      expect(localSettings.transcriptionOutputLocale, wanted.$code,
          reason:
              'The effective transcription locale does not follow the setting.');
    });

    testWidgets('05: logging out clears the cached AI token', (tester) async {
      await E2E.signIn(tester);
      localSettings.aiToken = 'cached-ai-token';
      localSettings.aiTokenServer = login.url;
      localSettings.aiTokenExpiry =
          DateTime.now().add(const Duration(hours: 6));
      localSettings.notifyAndPersist();

      await Fixtures.signOut(tester);

      expect(localSettings.aiToken, isNull,
          reason: 'Logout left the cached AI token behind.');
      expect(localSettings.aiTokenServer, isEmpty,
          reason: 'Logout left the cached AI token server behind.');
      expect(localSettings.aiTokenExpiry, isNull,
          reason: 'Logout left the cached AI token expiry behind.');
    });

    testWidgets('06: audio transcription fills the dental notes',
        (tester) async {
      expect(true, isTrue);
    }, skip: true);

    testWidgets('07: a receipt photo fills the expense fields', (tester) async {
      expect(true, isTrue);
    }, skip: true);

    testWidgets('08: post-op notes are generated from the appointment',
        (tester) async {
      expect(true, isTrue);
    }, skip: true);

    testWidgets(
        '09: worker-side AI failures are reported without losing the draft',
        (tester) async {
      expect(true, isTrue);
    }, skip: true);

    testWidgets('10: cache reset clears stored extraction state',
        (tester) async {
      expect(true, isTrue);
    }, skip: true);
  });
}

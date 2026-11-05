import 'package:fluent_ui/fluent_ui.dart';

enum SettingsSection {
  preferences('settingsPreferences', WindowsIcons.locale_language),
  calendar('calendar', WindowsIcons.calendar),
  clinic('settingsClinic', FluentIcons.hospital),
  optional('optionalFeatures', FluentIcons.puzzle),
  storage('settingsStorage', FluentIcons.database),
  backups('backups', FluentIcons.folder),
  server('settingsServer', FluentIcons.server);

  const SettingsSection(this.titleKey, this.icon);

  final String titleKey;
  final IconData icon;
}

SettingsSection settingsSectionFor(String identifier) => switch (identifier) {
      'currency' ||
      'ISO_country____' ||
      'prescriptionFot' ||
      'phone' =>
        SettingsSection.clinic,
      'startingDayOfWeek' ||
      'dateFormat' ||
      'timeFormat' ||
      'calendarView' ||
      'calendarSystem' =>
        SettingsSection.calendar,
      'ai_services_ena' ||
      'audioTranscriptionLocale' ||
      'follow_ups_enab' =>
        SettingsSection.optional,
      'cacheReset' ||
      'file_upload_settings' ||
      's3_settings' =>
        SettingsSection.storage,
      'backups' => SettingsSection.backups,
      'meta_settings' ||
      'auth_settings' ||
      'smtp_settings' =>
        SettingsSection.server,
      _ => SettingsSection.preferences,
    };

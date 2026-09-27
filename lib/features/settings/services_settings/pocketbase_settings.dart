/// Typed readers for the PocketBase app-settings document.
///
/// `settings.getAll()` is declared `Map<String, dynamic>` and the server does
/// not describe its shape, so every read of it is `dynamic` and each settings
/// screen would otherwise re-invent the same narrowing — and, being a form
/// filling in `initState`, would throw on a value of an unexpected type rather
/// than leave the field empty.
///
/// These pin the type once. A missing *or* mistyped value is reported as "not
/// set", which is what the forms already do with their `?? ''` fallbacks.
library;

/// The `[key]` section of [settings], or an empty map when it is absent or is
/// not a map.
Map<String, dynamic> settingsSection(
  Map<String, dynamic> settings,
  String key,
) {
  final section = settings[key];
  return section is Map<String, dynamic> ? section : const {};
}

/// The [key] of [section] as text, or [fallback] when it is absent.
///
/// Numbers and booleans are rendered as text because the forms treat some of
/// these fields (a port, a cron expression) as free text.
String settingsString(
  Map<String, dynamic> section,
  String key, [
  String fallback = '',
]) {
  final value = section[key];
  if (value == null) return fallback;
  return value is String ? value : value.toString();
}

/// The [key] of [section] as a flag, or [fallback] when it is absent.
bool settingsBool(
  Map<String, dynamic> section,
  String key, [
  bool fallback = false,
]) {
  final value = section[key];
  return value is bool ? value : fallback;
}

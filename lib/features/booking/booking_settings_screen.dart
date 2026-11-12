import 'dart:async';

import 'package:apexo/common_widgets/app_combo_box.dart';
import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/features/booking/booking_api.dart';
import 'package:apexo/features/booking/booking_clinic_service.dart';
import 'package:apexo/features/booking/booking_defaults.dart';
import 'package:apexo/features/booking/booking_models.dart';
import 'package:apexo/features/booking/booking_session.dart';
import 'package:apexo/features/booking/booking_time.dart';
import 'package:apexo/features/booking/opening_hours_editor.dart';
import 'package:apexo/features/settings/settings_card.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/features/booking/booking_labels.dart';
import 'package:apexo/utils/constants.dart';
import 'package:apexo/utils/init_pocketbase.dart';
import 'package:apexo/utils/logger.dart';
import 'package:apexo/utils/open_external.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:pocketbase/pocketbase.dart';

/// Settings → Online booking: the claim flow for unregistered clinics, then URL,
/// intake toggle, hours, diagnostics and repairs. Failures stay in this card.
class BookingSettingsCard extends StatefulWidget {
  const BookingSettingsCard({super.key});

  @override
  State<BookingSettingsCard> createState() => _BookingSettingsCardState();
}

class _BookingSettingsCardState extends State<BookingSettingsCard> {
  final _handle = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _welcome = TextEditingController();
  final _dialCode = TextEditingController();
  final _contactEmail = TextEditingController();

  BookingClinicService? _service;
  BookingClinicRecord? _clinic;
  BookingClinicConfig? _config;
  BookingDiagnostics? _diagnostics;
  final Map<String, String> _fieldErrors = {};
  bool _prefilled = false;
  int _revision = 0;
  String _timeZone = "UTC";
  String _language = "en";
  bool _schemaReady = false;
  bool _batchReady = true;
  bool _busy = false;
  String _message = "";
  bool _messageIsError = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _handle.dispose();
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _welcome.dispose();
    _dialCode.dispose();
    _contactEmail.dispose();
    _service?.dispose();
    super.dispose();
  }

  BookingClinicService get _svc => _service ??= BookingClinicService();

  Future<void> _load() async {
    if (!bookingAvailable || !mounted) return;
    setState(() => _busy = true);
    try {
      _schemaReady = await _svc.collectionsReady();
      if (!mounted) return;
      final pb = login.pb;
      if (pb != null && login.isAdmin) {
        _batchReady = await pmsBatchApiEnabled(pb);
      }
      if (!mounted) return;
      final clinic = await _svc.loadClinic();
      if (!mounted) return;
      _clinic = clinic;
      if (clinic == null) await _prefillDefaults(pb);
      if (clinic != null) {
        if (login.isAdmin) {
          final admin = await _svc.loadAdmin();
          if (admin != null) {
            final snapshot = await _svc.api.readConfig(admin.adminKey);
            if (!mounted) return;
            _config = snapshot.config;
            _revision = snapshot.revision;
            _timeZone = snapshot.config.timeZone;
            _dialCode.text = snapshot.config.dialCode;
            _language = snapshot.config.profile.defaultLanguage;
            _contactEmail.text = snapshot.config.contactEmail ?? "";
            _name.text = snapshot.config.profile.name;
            _phone.text = snapshot.config.profile.phone;
            _address.text = snapshot.config.profile.address;
            _welcome.text = snapshot.config.profile.welcome;
          }
        }
        try {
          _diagnostics = await _svc.api.diagnostics(clinic.inboxKey);
        } catch (_) {
          _diagnostics = null;
        }
      }
    } catch (error, stackTrace) {
      logger('Could not load online booking settings: $error', stackTrace);
      _note(txt("bookingUnavailable"), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _note(String message, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _messageIsError = error;
    });
  }

  String _setting(String id) {
    try {
      return globalSettings.get(id).value.trim();
    } catch (_) {
      return "";
    }
  }

  /// Seeds the claim form from settings and the device so a superuser only confirms.
  Future<void> _prefillDefaults(PocketBase? pb) async {
    if (_prefilled) return;
    _prefilled = true;
    final country = _setting("ISO_country____");
    final dial = bookingDialCodeForCountry(country);
    if (dial != null && _dialCode.text.trim().isEmpty) _dialCode.text = dial;
    final phone = _setting("phone__________");
    if (phone.isNotEmpty && _phone.text.trim().isEmpty) {
      _phone.text = bookingInternationalPhone(phone, country) ?? phone;
    }
    final footer = _setting("prescriptionFot");
    if (footer.isNotEmpty && _address.text.trim().isEmpty) {
      _address.text = footer;
    }
    final systemZone = bookingSystemTimeZone();
    if (systemZone != null) _timeZone = systemZone;
    if (bookingLanguages.contains(locale.s.$code)) _language = locale.s.$code;
    if (pb != null && login.isAdmin) {
      try {
        final settings = await pb.settings.getAll();
        if (!mounted) return;
        final meta = settings["meta"];
        final appName =
            meta is Map ? (meta["appName"]?.toString() ?? "").trim() : "";
        if (appName.isNotEmpty && _name.text.trim().isEmpty) {
          _name.text = appName;
        }
      } catch (_) {
        // The application name is a convenience; the field stays editable.
      }
    }
    if (mounted) setState(() {});
  }

  /// The first invalid field key, or null when the form may be submitted.
  String? _claimError() {
    final handle = _handle.text.trim().toLowerCase();
    if (!bookingHandlePattern.hasMatch(handle) ||
        bookingReservedHandles.contains(handle) ||
        handle.length < 3) {
      return "handle";
    }
    return _claimConfig().validate();
  }

  BookingClinicConfig _claimConfig() {
    return BookingClinicConfig(
      profile: BookingProfile(
        name: _name.text,
        phone: _phone.text,
        address: _address.text,
        welcome: _welcome.text,
        defaultLanguage: _language,
      ),
      timeZone: _timeZone,
      dialCode: _dialCode.text,
      hours: BookingWeeklyHours.empty(),
      closedDates: const [],
      contactEmail:
          _contactEmail.text.trim().isEmpty ? null : _contactEmail.text,
      enabled: false,
    );
  }

  Future<void> _claim() async {
    final error = _claimError();
    if (error != null) {
      _markField(error);
      return;
    }
    setState(() {
      _fieldErrors.clear();
      _busy = true;
    });
    try {
      await _svc.register(handle: _handle.text, config: _claimConfig());
      await booking.reload();
      await _load();
      _note(txt("bookingClaimed"));
    } on BookingApiException catch (error) {
      _noteApiError(error);
    } on StateError catch (error) {
      _note(_stateMessage(error.message), error: true);
    } catch (_) {
      _note(txt("bookingSaveFailed"), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveConfig({bool enableAfterSave = false}) async {
    final config = _config;
    if (config == null) return;
    if (enableAfterSave && config.hours.isEmpty) {
      // "Start disabled until the administrator saves valid hours."
      _note(txt("bookingHoursInvalid"), error: true);
      return;
    }
    if (enableAfterSave) config.enabled = true;
    config.profile
      ..name = _name.text
      ..phone = _phone.text
      ..address = _address.text
      ..welcome = _welcome.text
      ..defaultLanguage = _language;
    config.timeZone = _timeZone;
    config.dialCode = _dialCode.text;
    config.contactEmail =
        _contactEmail.text.trim().isEmpty ? null : _contactEmail.text.trim();
    final error = config.validate();
    if (error != null) {
      _markField(error);
      return;
    }
    setState(() => _busy = true);
    try {
      _revision = await _svc.writeConfig(config, _revision);
      await booking.reload();
      await _load();
      _note(txt("bookingSaved"));
    } on BookingApiException catch (error) {
      _noteApiError(error);
    } catch (_) {
      _note(txt("bookingSaveFailed"), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Leaves the platform: the Worker erases the page and requests, then the local
  /// credentials go, returning the card and inbox route to the claim form.
  Future<void> _deleteClinic() async {
    final confirmed =
        await _confirm(txt("bookingDeleteAction"), txt("bookingDeleteBody"));
    if (!confirmed) return;
    setState(() => _busy = true);
    try {
      await _svc.deleteClinic();
      await booking.reload();
      _clinic = null;
      _config = null;
      _diagnostics = null;
      await _load();
      _note(txt("bookingDeleteDone"));
    } on BookingApiException catch (error) {
      _noteApiError(error);
    } on StateError catch (error) {
      _note(_stateMessage(error.message), error: true);
    } catch (_) {
      _note(txt("bookingSaveFailed"), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rotate() async {
    final confirmed =
        await _confirm(txt("bookingReplaceKey"), txt("bookingReplaceKeyBody"));
    if (!confirmed) return;
    setState(() => _busy = true);
    try {
      await _svc.rotate();
      await booking.reload();
      await _load();
      _note(txt("bookingSaved"));
    } on BookingApiException catch (error) {
      _noteApiError(error);
    } catch (_) {
      _note(txt("bookingSaveFailed"), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recover() async {
    final confirmed =
        await _confirm(txt("bookingRecoverAction"), txt("bookingRecoverBody"));
    if (!confirmed) return;
    setState(() => _busy = true);
    try {
      await _svc.recover();
      await booking.reload();
      await _load();
      _note(txt("bookingSaved"));
    } on BookingApiException catch (error) {
      _noteApiError(error);
    } catch (_) {
      _note(txt("bookingSaveFailed"), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String body) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => ContentDialog(
        constraints: const BoxConstraints(maxWidth: 420),
        title: Text(title),
        content: Text(body),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(txt("ok")),
          ),
          Button(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(txt("cancel")),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _repairSchema() async {
    setState(() => _busy = true);
    try {
      await _svc.repairSchema();
      _schemaReady = await _svc.collectionsReady();
      _note(
          _schemaReady
              ? txt("bookingSchemaRepaired")
              : txt("bookingSaveFailed"),
          error: !_schemaReady);
    } catch (_) {
      _note(txt("bookingSaveFailed"), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _repairBatch() async {
    final pb = login.pb;
    if (pb == null) return;
    setState(() => _busy = true);
    try {
      await ensurePmsBatchEnabled(pb);
      _batchReady = await pmsBatchApiEnabled(pb);
      setState(() {});
    } catch (_) {
      _note(txt("bookingSaveFailed"), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _fieldMessage(String field) => switch (field) {
        "handle" => txt("bookingInvalidHandle"),
        "profile.name" => txt("bookingFieldName"),
        "profile.phone" => txt("bookingFieldPhone"),
        "profile.address" => txt("bookingFieldAddress"),
        "profile.welcome" => txt("bookingFieldWelcome"),
        "profile.defaultLanguage" => txt("bookingFieldLanguage"),
        "contactEmail" => txt("bookingFieldEmail"),
        "timeZone" => txt("bookingFieldTimeZone"),
        "dialCode" => txt("bookingFieldDialCode"),
        _ when field.startsWith("hours") => txt("bookingHoursInvalid"),
        _ => txt("bookingInvalidFields"),
      };

  /// Marks the offending control and names the field instead of a generic message.
  void _markField(String field) {
    if (!mounted) return;
    setState(() {
      _fieldErrors
        ..clear()
        ..[field] = _fieldMessage(field);
    });
    _note(txt("bookingInvalidFields"), error: true);
  }

  /// Surfaces a server-side field rejection on the control that caused it.
  void _noteApiError(BookingApiException error) {
    if (error.code == "invalid_fields" && error.fields.isNotEmpty) {
      _markField(error.fields.keys.first);
      return;
    }
    _note(
      switch (error.code) {
        "rate_limited" => txt("bookingRateLimited"),
        "handle_taken" =>
          "${txt("bookingHandleTaken")}${error.suggestions.isEmpty ? "" : " ${error.suggestions.join(", ")}"}",
        "config_conflict" => txt("bookingConfigConflict"),
        "key_conflict" => txt("bookingKeyConflict"),
        "invalid_fields" => txt("bookingInvalidFields"),
        "enrollment_disabled" => txt("bookingEnrollmentDisabled"),
        "unauthorized" || "forbidden" => txt("bookingKeyRevoked"),
        _ => txt("bookingSaveFailed"),
      },
      error: true,
    );
  }

  String _stateMessage(String message) => switch (message) {
        "booking_setup_requires_admin" => txt("bookingSetupRequiresAdmin"),
        "booking_unsupported_server" => txt("bookingUnsupportedServer"),
        "booking_invalid_handle" => txt("bookingInvalidHandle"),
        "booking_not_registered" => txt("bookingNotConfigured"),
        _ => txt("bookingSaveFailed"),
      };

  @override
  Widget build(BuildContext context) {
    if (!bookingAvailable) {
      // A missing trusted origin hides the feature entirely.
      return const SizedBox.shrink();
    }
    final theme = FluentTheme.of(context);
    return SettingsCard(
      leading: const Icon(FluentIcons.globe),
      header: Txt(txt("booking")),
      description: Txt(txt("bookingSubtitle")),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          if (_busy) const ProgressBar(),
          if (!_schemaReady && login.isAdmin)
            _noticeRow(theme, txt("bookingSchemaMissing"),
                action: txt("bookingRepairSchema"), onPressed: _repairSchema),
          if (_schemaReady && !_batchReady && login.isAdmin)
            _noticeRow(theme, txt("bookingBatchDisabled"),
                action: txt("bookingRepairBatch"), onPressed: _repairBatch),
          if (_clinic == null) _claimForm(theme) else _registered(theme),
          if (_message.isNotEmpty)
            Text(
              _message,
              style: TextStyle(
                color: _messageIsError
                    ? Colors.errorPrimaryColor
                    : Colors.successPrimaryColor,
              ),
            ),
        ],
      ),
    );
  }

  Widget _noticeRow(FluentThemeData theme, String text,
          {String? action, Future<void> Function()? onPressed}) =>
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.warningPrimaryColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final button = action == null
                ? null
                : Button(
                    onPressed: _busy ? null : () => unawaited(onPressed!()),
                    child: Text(action),
                  );
            // A phone-width card cannot fit the repair label, so the action moves below.
            if (button == null || constraints.maxWidth < 380) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 8,
                children: [
                  Text(text),
                  if (button != null) button,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: Text(text)),
                button,
              ],
            );
          },
        ),
      );

  Widget _claimForm(FluentThemeData theme) {
    if (!login.isAdmin) {
      return Text(txt("bookingNotConfigured"));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 10,
      children: [
        Text(txt("bookingClaimExplainer")),
        _field("handle", txt("bookingHandle"), _handle,
            hint: "jimclinic",
            textDirection: TextDirection.ltr,
            keyboardType: TextInputType.url),
        _field("profile.name", txt("name"), _name),
        _field("profile.phone", txt("phone"), _phone,
            hint: "+966551234567",
            textDirection: TextDirection.ltr,
            keyboardType: TextInputType.phone),
        _field("profile.address", txt("address"), _address),
        _field("profile.welcome", txt("bookingWelcome"), _welcome),
        _field("contactEmail", txt("email"), _contactEmail,
            hint: "name@example.com",
            textDirection: TextDirection.ltr,
            keyboardType: TextInputType.emailAddress),
        _choice(
          "timeZone",
          txt("bookingTimeZone"),
          bookingTimeZoneNames(),
          _timeZone,
          (value) => setState(() => _timeZone = value),
        ),
        _field("dialCode", txt("bookingDialCode"), _dialCode,
            hint: "+966",
            textDirection: TextDirection.ltr,
            keyboardType: TextInputType.phone),
        _languageField(),
        FilledButton(
          onPressed: _busy ? null : () => unawaited(_claim()),
          child: ButtonContent(FluentIcons.accept, txt("bookingClaimAction")),
        ),
      ],
    );
  }

  Widget _registered(FluentThemeData theme) {
    final clinic = _clinic!;
    final config = _config;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                clinic.publicUrl,
                style: theme.typography.bodyStrong,
              ),
            ),
            Button(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: clinic.publicUrl));
                _note(txt("bookingCopied"));
              },
              child: ButtonContent(FluentIcons.copy, txt("bookingCopy")),
            ),
            const SizedBox(width: 6),
            Button(
              onPressed: () => unawaited(launchBookingUrl(clinic.publicUrl)),
              child: ButtonContent(FluentIcons.open_in_new_window, txt("open")),
            ),
          ],
        ),
        if (_diagnostics != null)
          Wrap(
            spacing: 18,
            runSpacing: 6,
            children: [
              Text("${txt("pending")}: ${_diagnostics!.pending}"),
              Text("${txt("bookingLastPull")}: "
                  "${_diagnostics!.lastPullAt == null ? txt("bookingNever") : bookingSubmittedLabel(_diagnostics!.lastPullAt!)}"),
              Text(
                  "${txt("bookingKeyRevision")}: ${_diagnostics!.keyRevision}"),
              Text(
                  "${txt("bookingConfigRevision")}: ${_diagnostics!.configRevision}"),
            ],
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Button(
            onPressed: _busy ? null : () => unawaited(_load()),
            child: ButtonContent(WindowsIcons.sync, txt("refresh")),
          ),
        ),
        if (config == null && login.isAdmin)
          Text(txt("bookingUnavailable"), style: theme.typography.caption),
        if (config != null && login.isAdmin) ...[
          Text(txt("bookingProfile"), style: theme.typography.bodyStrong),
          _field("profile.name", txt("name"), _name),
          _field("profile.phone", txt("phone"), _phone,
              textDirection: TextDirection.ltr,
              keyboardType: TextInputType.phone),
          _field("profile.address", txt("address"), _address),
          _field("profile.welcome", txt("bookingWelcome"), _welcome),
          _field("contactEmail", txt("email"), _contactEmail,
              hint: "name@example.com",
              textDirection: TextDirection.ltr,
              keyboardType: TextInputType.emailAddress),
          _choice(
            "timeZone",
            txt("bookingTimeZone"),
            bookingTimeZoneNames(),
            _timeZone,
            (value) => setState(() => _timeZone = value),
          ),
          _field("dialCode", txt("bookingDialCode"), _dialCode,
              hint: "+966",
              textDirection: TextDirection.ltr,
              keyboardType: TextInputType.phone),
          _languageField(),
          Row(
            children: [
              ToggleSwitch(
                checked: config.enabled,
                content: Txt(txt("bookingEnabledToggle")),
                onChanged: _busy
                    ? null
                    : (value) {
                        if (value && config.hours.isEmpty) {
                          // Intake stays disabled until the administrator saves valid hours
                          // and explicitly enables it.
                          _note(txt("bookingHoursInvalid"), error: true);
                          return;
                        }
                        config.enabled = value;
                        unawaited(_saveConfig());
                      },
              ),
            ],
          ),
          Text(txt("bookingOpeningHours"), style: theme.typography.bodyStrong),
          OpeningHoursEditor(
            hours: config.hours,
            closedDates: config.closedDates,
            enabled: !_busy,
            onChanged: (hours) => setState(() => config.hours = hours),
            onClosedDatesChanged: (dates) =>
                setState(() => config.closedDates = dates),
          ),
          Row(
            spacing: 8,
            children: [
              FilledButton(
                onPressed: _busy ? null : () => unawaited(_saveConfig()),
                child: ButtonContent(FluentIcons.save, txt("save")),
              ),
              Button(
                onPressed: _busy ? null : () => unawaited(_rotate()),
                child: ButtonContent(
                    FluentIcons.refresh, txt("bookingReplaceKey")),
              ),
              Button(
                onPressed: _busy ? null : () => unawaited(_recover()),
                child: ButtonContent(
                    FluentIcons.history, txt("bookingRecoverAction")),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Button(
                onPressed: _busy ? null : () => unawaited(_deleteClinic()),
                child: ButtonContent(
                  FluentIcons.delete,
                  txt("bookingDeleteAction"),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _field(
    String key,
    String label,
    TextEditingController controller, {
    String? hint,
    TextDirection? textDirection,
    TextInputType? keyboardType,
  }) {
    final error = _fieldErrors[key];
    return InfoLabel(
      label: label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CupertinoTextField(
            controller: controller,
            placeholder: hint,
            textDirection: textDirection,
            keyboardType: keyboardType,
            suffix: error == null
                ? null
                : const Padding(
                    padding: EdgeInsets.all(5),
                    child: Icon(
                      WindowsIcons.warning,
                      color: Colors.errorPrimaryColor,
                      size: 16,
                    ),
                  ),
            onChanged: (_) {
              if (error != null) setState(() => _fieldErrors.remove(key));
            },
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                error,
                style: const TextStyle(
                  color: Colors.errorPrimaryColor,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _choice(
    String key,
    String label,
    List<String> values,
    String selected,
    ValueChanged<String> onChanged, {
    String Function(String)? display,
  }) =>
      InfoLabel(
        label: label,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppComboBox<String>(
              isExpanded: true,
              value: selected,
              items: [
                for (final value in values)
                  ComboBoxItem(
                      value: value, child: Text(display?.call(value) ?? value)),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _fieldErrors.remove(key));
                onChanged(value);
              },
            ),
            if (_fieldErrors[key] != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _fieldErrors[key]!,
                  style: const TextStyle(
                    color: Colors.errorPrimaryColor,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      );

  Widget _languageField() => _choice(
        "profile.defaultLanguage",
        txt("language"),
        bookingLanguages,
        _language,
        (value) => setState(() => _language = value),
        display: bookingLanguageName,
      );
}

/// Opens the public page in the OS browser.
Future<void> launchBookingUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  await openExternal(uri);
}

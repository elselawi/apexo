import 'dart:async';
import 'package:apexo/features/settings/settings_card.dart';
import 'package:apexo/features/settings/settings_section.dart';
import 'package:apexo/common_widgets/dialogs/dialog_styling.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/core/reactive/observable.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/expenses/expenses_store.dart';
import 'package:apexo/features/network_actions/network_actions_controller.dart';
import 'package:apexo/features/notes/notes_store.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/features/settings/applies_to_indicator.dart';
import 'package:apexo/features/settings/services_settings/auth_settings.dart';
import 'package:apexo/features/settings/services_settings/backups_settings.dart';
import 'package:apexo/features/settings/services_settings/file_upload_settings.dart';
import 'package:apexo/features/settings/services_settings/meta_settings.dart';
import 'package:apexo/features/settings/services_settings/s3_settings.dart';
import 'package:apexo/features/settings/services_settings/smtp_settings.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/network.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:table_calendar/table_calendar.dart';
import 'settings_model.dart';
import 'settings_stores.dart';

enum InputType { text, multiline, dropDown, none }

final languagePickersOptions = locale.list
    .map((e) => ComboBoxItem(
        value: locale.list.indexOf(e).toString(), child: Txt(e.$name)))
    .toList();

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  SettingsSection _selected = SettingsSection.preferences;

  @override
  Widget build(BuildContext context) {
    return MStreamBuilder(
      streams: [
        globalSettings.observableMap.stream,
        localSettings.stream,
        locale.selected.stream,
        network.isOnline.stream,
      ],
      builder: (context, _) {
        final theme = FluentTheme.of(context);
        final grouped = <SettingsSection, List<Widget>>{};
        for (final item in _items(context)) {
          final section = item is SettingsItem
              ? settingsSectionFor(item.identifier)
              : item is BackupsSettings
                  ? SettingsSection.backups
                  : item is MetaSettings ||
                          item is AuthSettings ||
                          item is SmtpSettings
                      ? SettingsSection.server
                      : SettingsSection.storage;
          grouped.putIfAbsent(section, () => []).add(item);
        }
        final sections =
            SettingsSection.values.where(grouped.containsKey).toList();
        final selected =
            sections.contains(_selected) ? _selected : sections.first;
        return LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final padding = constraints.maxWidth < 500 ? 12.0 : 24.0;
          return Padding(
            padding: EdgeInsets.all(padding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Txt(txt('settings'), style: theme.typography.title),
                const SizedBox(height: 6),
                Txt(txt('settingsSubtitle'),
                    style: TextStyle(
                        color: theme.resources.textFillColorSecondary)),
                const SizedBox(height: 24),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: wide ? 220 : 0,
                        child: wide
                            ? ListView(
                                children: [
                                  for (final section in sections)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: ListTile.selectable(
                                        key: ValueKey(
                                            'settings_category_${section.name}'),
                                        selected: selected == section,
                                        leading: Icon(section.icon, size: 18),
                                        title: Txt(txt(section.titleKey)),
                                        onPressed: () =>
                                            setState(() => _selected = section),
                                      ),
                                    ),
                                ],
                              )
                            : null,
                      ),
                      SizedBox(width: wide ? 28 : 0),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (!wide) ...[
                              ComboBox<SettingsSection>(
                                key: const ValueKey('settings_category_picker'),
                                isExpanded: true,
                                value: selected,
                                items: [
                                  for (final section in sections)
                                    ComboBoxItem(
                                      value: section,
                                      child: Row(children: [
                                        Icon(section.icon, size: 16),
                                        const SizedBox(width: 10),
                                        Flexible(
                                            child: Txt(txt(section.titleKey))),
                                      ]),
                                    ),
                                ],
                                onChanged: (value) {
                                  if (value != null) {
                                    setState(() => _selected = value);
                                  }
                                },
                              ),
                              const SizedBox(height: 16),
                            ],
                            Expanded(
                              key: const ValueKey('settings_pages'),
                              child: IndexedStack(
                                key: WK.settingsList,
                                index: sections.indexOf(selected),
                                sizing: StackFit.expand,
                                children: [
                                  for (final section in sections)
                                    SingleChildScrollView(
                                      key: PageStorageKey(section),
                                      child: Align(
                                        alignment:
                                            AlignmentDirectional.topStart,
                                        child: ConstrainedBox(
                                          constraints: const BoxConstraints(
                                              maxWidth: 1100),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                    bottom: 16),
                                                child: Txt(
                                                    txt(section.titleKey),
                                                    style: theme
                                                        .typography.subtitle),
                                              ),
                                              for (final item
                                                  in grouped[section]!)
                                                Padding(
                                                  key: item is SettingsItem
                                                      ? ValueKey(
                                                          item.identifier)
                                                      : ValueKey(
                                                          item.runtimeType),
                                                  padding:
                                                      const EdgeInsets.only(
                                                          bottom: 8),
                                                  child: item,
                                                ),
                                              const SizedBox(height: 16),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  List<Widget> _items(BuildContext context) => [
        if (login.isAdmin)
          SettingsItem(
            title: txt("currency"),
            identifier: "currency",
            description: txt("currency_desc"),
            icon: FluentIcons.all_currency,
            inputType: InputType.text,
            scope: Scope.app,
            initValue: globalSettings.get("currency_______").value,
            apply: (newVal) => globalSettings.set(
                Setting.fromJson({"id": "currency_______", "value": newVal})),
          ),
        if (login.isAdmin)
          SettingsItem(
            title: txt("countryCode"),
            identifier: "ISO_country____",
            description: txt("countryCode_desc"),
            icon: FluentIcons.globe,
            inputType: InputType.text,
            scope: Scope.app,
            initValue: globalSettings.get("ISO_country____").value,
            apply: (newVal) => globalSettings.set(
                Setting.fromJson({"id": "ISO_country____", "value": newVal})),
          ),
        if (login.isAdmin)
          SettingsItem(
            title: txt("prescriptionFooter"),
            identifier: "prescriptionFot",
            description: txt("prescriptionFooter_desc"),
            icon: FluentIcons.footer,
            inputType: InputType.text,
            scope: Scope.app,
            initValue: globalSettings.get("prescriptionFot").value,
            apply: (newVal) => globalSettings.set(
                Setting.fromJson({"id": "prescriptionFot", "value": newVal})),
          ),
        if (login.isAdmin)
          SettingsItem(
            title: txt("phone"),
            identifier: "phone",
            description: txt("phone_desc"),
            icon: WindowsIcons.phone,
            inputType: InputType.multiline,
            scope: Scope.app,
            initValue: globalSettings.get("phone__________").value,
            apply: (newVal) => globalSettings.set(
                Setting.fromJson({"id": "phone__________", "value": newVal})),
          ),
        SettingsItem(
          title: txt("language"),
          identifier: "language",
          description: txt("language_desc"),
          icon: WindowsIcons.locale_language,
          inputType: InputType.dropDown,
          scope: Scope.device,
          options: languagePickersOptions,
          initValue: localSettings.selectedLocale.toString(),
          apply: (newVal) {
            localSettings.selectedLocale = int.parse(newVal);
            localSettings.notifyAndPersist();
          },
        ),
        if (login.isAdmin)
          SettingsItem(
            title: txt("startingDayOfWeek"),
            identifier: "startingDayOfWeek",
            description: txt("startingDayOfWeek_desc"),
            icon: FluentIcons.hazy_day,
            inputType: InputType.dropDown,
            scope: Scope.app,
            options: StartingDayOfWeek.values
                .map(
                    (e) => ComboBoxItem(value: e.name, child: Txt(txt(e.name))))
                .toList(),
            initValue: globalSettings.get("start_day_of_wk").value,
            apply: (newVal) => globalSettings.set(
                Setting.fromJson({"id": "start_day_of_wk", "value": newVal})),
          ),
        SettingsItem(
          title: txt("dateFormat"),
          identifier: "dateFormat",
          description: txt("dateFormat_desc"),
          icon: WindowsIcons.date_time,
          inputType: InputType.dropDown,
          scope: Scope.device,
          options: [
            ComboBoxItem(
              value: "MM/dd/yyyy",
              child: Txt(txt("month/day/year")),
            ),
            ComboBoxItem(
              value: "dd/MM/yyyy",
              child: Txt(txt("day/month/year")),
            ),
          ],
          initValue: localSettings.dateFormat,
          apply: (newVal) {
            localSettings.dateFormat = newVal;
            localSettings.notifyAndPersist();
          },
        ),
        SettingsItem(
          title: txt("timeFormat"),
          identifier: "timeFormat",
          description: txt("timeFormat_desc"),
          icon: FluentIcons.clock,
          inputType: InputType.dropDown,
          scope: Scope.device,
          options: [
            ComboBoxItem(
              value: DF.time12hPattern,
              child: Txt(txt("12-hour")),
            ),
            ComboBoxItem(
              value: DF.time24hPattern,
              child: Txt(txt("24-hour")),
            ),
          ],
          initValue: localSettings.timeFormat,
          apply: (newVal) {
            localSettings.timeFormat = newVal;
            localSettings.notifyAndPersist();
          },
        ),
        SettingsItem(
          title: txt("calendarView"),
          identifier: "calendarView",
          description: txt("calendarView_desc"),
          icon: WindowsIcons.calendar_day,
          inputType: InputType.dropDown,
          scope: Scope.device,
          options: EventsViewMode.values
              .map((e) => ComboBoxItem(
                  value: e.index.toString(), child: Txt(txt(e.name))))
              .toList(),
          initValue: localSettings.calendarEventsViewMode.index.toString(),
          apply: (newVal) {
            localSettings.calendarEventsViewMode =
                EventsViewMode.values[int.tryParse(newVal) ?? 0];
            localSettings.notifyAndPersist();
          },
        ),
        SettingsItem(
          title: txt("calendarSystem"),
          identifier: "calendarSystem",
          description: txt("calendarSystem_desc"),
          icon: WindowsIcons.calendar,
          inputType: InputType.dropDown,
          scope: Scope.device,
          options: [
            ComboBoxItem(
              value: "gregorian",
              child: Txt(txt("gregorian")),
            ),
            ComboBoxItem(
              value: "persian",
              child: Txt(txt("persian")),
            ),
            ComboBoxItem(
              value: "hijri",
              child: Txt(txt("hijri")),
            ),
          ],
          initValue: localSettings.calendarSystem,
          apply: (newVal) {
            localSettings.calendarSystem = newVal;
            localSettings.notifyAndPersist();
          },
        ),
        SettingsItem(
          title: txt("dentalNotation"),
          identifier: "dentalNotation",
          description: txt("dentalNotation_desc"),
          icon: FluentIcons.teeth,
          inputType: InputType.dropDown,
          scope: Scope.device,
          options: [
            ComboBoxItem(
              value: "p",
              child: Txt(txt("palmer")),
            ),
            ComboBoxItem(
              value: "u",
              child: Txt(txt("universal")),
            ),
            ComboBoxItem(
              value: "i",
              child: Txt(txt("iso")),
            ),
          ],
          initValue: localSettings.dentalNotation,
          apply: (newVal) {
            localSettings.dentalNotation = newVal;
            localSettings.notifyAndPersist();
          },
        ),
        if (login.isAdmin)
          SettingsItem(
            title: txt("ai_services"),
            identifier: "ai_services_ena",
            description: txt("ai_services_desc"),
            icon: FluentIcons.lightbulb,
            inputType: InputType.dropDown,
            scope: Scope.app,
            options: [
              ComboBoxItem(value: "1", child: Txt(txt("on"))),
              ComboBoxItem(value: "0", child: Txt(txt("off"))),
            ],
            footer: InfoBar(title: Txt(txt("no_training_privacy_info"))),
            initValue: globalSettings.get("ai_services_ena").value,
            apply: (newVal) => globalSettings.set(
                Setting.fromJson({"id": "ai_services_ena", "value": newVal})),
          ),
        if (globalSettings.get("ai_services_ena").value == "1")
          SettingsItem(
            title: txt("audioTranscriptionLocale"),
            identifier: "audioTranscriptionLocale",
            description: txt("audioTranscriptionLocale_desc"),
            icon: WindowsIcons.microphone,
            inputType: InputType.dropDown,
            scope: Scope.device,
            options: [
              ComboBoxItem(value: "", child: Txt(txt("sameAsAppLanguage"))),
              ...locale.list.map((language) => ComboBoxItem(
                  value: language.$code, child: Txt(language.$name)))
            ],
            initValue: localSettings.transcriptionLocaleNonFinal,
            apply: (newVal) {
              localSettings.transcriptionLocaleNonFinal = newVal;
              localSettings.notifyAndPersist();
            },
          ),
        if (network.isOnline())
          SettingsItem(
            title: txt("cacheReset"),
            identifier: "cacheReset",
            description: txt("cacheReset_desc"),
            icon: FluentIcons.offline_storage,
            inputType: InputType.none,
            scope: Scope.device,
            initValue: "",
            apply: (_) {},
            footer: FilledButton(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(FluentIcons.offline_storage, size: 16),
                    const SizedBox(width: 8),
                    Flexible(child: Txt(txt("cacheReset")))
                  ],
                ),
                onPressed: () async {
                  unawaited(showDialog(
                      context: context,
                      barrierDismissible: false,
                      dismissWithEsc: false,
                      builder: (context) {
                        return ContentDialog(
                          title: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [Txt(txt("cacheReset"))]),
                          content: StreamBuilder(
                              stream: cacheResetState.stream,
                              builder: (context, _) {
                                return Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  spacing: 10,
                                  children: [
                                    if (!cacheResetState().startsWith("Error"))
                                      const Center(child: ProgressRing()),
                                    Center(child: Txt(cacheResetState())),
                                    if (cacheResetState().startsWith("Error"))
                                      FilledButton(
                                          child: Txt(txt("close")),
                                          onPressed: () =>
                                              Navigator.pop(context)),
                                  ],
                                );
                              }),
                          style: dialogStyling(context, false, true),
                        );
                      }));

                  try {
                    cacheResetState(txt("initialSynchronization"));
                    await networkActions.resync();
                    cacheResetState(txt("clearingLocalData"));
                    await patients.local!.clear();
                    await appointments.local!.clear();
                    await expenses.local!.clear();
                    await notes.local!.clear();
                    await globalSettings.local!.clear();
                    cacheResetState(txt("synchronizing"));
                    await networkActions.resync();
                  } catch (e, s) {
                    cacheResetState("Error: $e\n$s");
                    return;
                  }
                  if (context.mounted) Navigator.of(context).pop();
                }),
          ),
        if (login.isAdmin && network.isOnline()) ...[
          const MetaSettings(),
          const AuthSettings(),
          const FileUploadSettings(),
          const S3Settings(),
          const SmtpSettings(),
          const BackupsSettings(),
        ],
      ];
}

class SettingsItem extends StatefulWidget {
  const SettingsItem({
    super.key,
    required this.identifier,
    required this.title,
    required this.description,
    required this.icon,
    required this.inputType,
    required this.scope,
    required this.initValue,
    required this.apply,
    this.options = const [],
    this.footer,
  });
  final String title;
  final String description;
  final IconData icon;
  final InputType inputType;
  final String identifier;
  final Scope scope;
  final List<ComboBoxItem<String>> options;
  final Widget? footer;
  final String initValue;
  final void Function(String newVal) apply;

  @override
  State<StatefulWidget> createState() => SettingsItemState();
}

class SettingsItemState extends State<SettingsItem> {
  final TextEditingController _controller = TextEditingController();
  String value = "";

  void _setControllerText(String text) {
    _controller.value = _controller.value.copyWith(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
      composing: TextRange.empty,
    );
  }

  @override
  void initState() {
    super.initState();
    value = widget.initValue;
    _setControllerText(widget.initValue);
  }

  @override
  void didUpdateWidget(covariant SettingsItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initValue == widget.initValue) return;
    final hasPendingEdit = _controller.text != value;
    value = widget.initValue;
    if (!hasPendingEdit) _setControllerText(widget.initValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      key: WK.settingsItem(widget.identifier),
      leading: Icon(widget.icon),
      header: Txt(widget.title),
      description: Txt(widget.description),
      trailing: AppliesToIndicator(scope: widget.scope),
      control: widget.inputType == InputType.none
          ? widget.footer == null
              ? null
              : Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: widget.footer,
                )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.inputType == InputType.text ||
                    widget.inputType == InputType.multiline)
                  TextBox(
                    key: Key("${widget.identifier}_text_field"),
                    controller: _controller,
                    onChanged: (_) => setState(() {}),
                    minLines: widget.inputType == InputType.multiline ? 3 : 1,
                    maxLines: widget.inputType == InputType.multiline ? 5 : 1,
                    placeholder: widget.title,
                  )
                else if (widget.inputType == InputType.dropDown)
                  ComboBox<String>(
                    key: Key("${widget.identifier}_combo"),
                    isExpanded: true,
                    items: widget.options,
                    onChanged: (next) {
                      if (next != null) {
                        setState(() => _setControllerText(next));
                      }
                    },
                    value: _controller.text,
                  ),
                if (_controller.text != value) ...[
                  const SizedBox(height: 10),
                  buildSaveCancelButtons(),
                ],
              ],
            ),
      content: widget.inputType == InputType.none ? null : widget.footer,
    );
  }

  Widget buildSaveCancelButtons() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton(
          onPressed: () {
            setState(() {
              widget.apply(_controller.text);
              value = _controller.text;
            });
          },
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(WindowsIcons.save, size: 16),
            const SizedBox(width: 8),
            Txt(txt("save")),
          ]),
        ),
        Button(
          onPressed: () {
            setState(() {
              _setControllerText(value);
            });
          },
          child: Txt(txt("cancel")),
        ),
      ],
    );
  }
}

final cacheResetState = ObservableState("");

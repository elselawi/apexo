import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/dialogs/dialog_styling.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/core/observable.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/expenses/expenses_store.dart';
import 'package:apexo/features/network_actions/network_actions_controller.dart';
import 'package:apexo/features/notes/notes_store.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/features/settings/applies_to_indicator.dart';
import 'package:apexo/features/settings/services_settings/auth_settings.dart';
import 'package:apexo/features/settings/services_settings/backups_settings.dart';
import 'package:apexo/features/settings/services_settings/meta_settings.dart';
import 'package:apexo/features/settings/services_settings/s3_settings.dart';
import 'package:apexo/features/settings/services_settings/smtp_settings.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/network.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:table_calendar/table_calendar.dart';
import 'settings_model.dart';
import 'settings_stores.dart';

enum InputType { text, multiline, dropDown, none }

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: ListView(
        children: [
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
              icon: FluentIcons.phone,
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
            icon: FluentIcons.locale_language,
            inputType: InputType.dropDown,
            scope: Scope.device,
            options: locale.list
                .map((e) => ComboBoxItem(
                    value: locale.list.indexOf(e).toString(),
                    child: Txt(e.$name)))
                .toList(),
            initValue: localSettings.selectedLocale.toString(),
            apply: (newVal) {
              localSettings.selectedLocale = int.parse(newVal);
              localSettings.notifyAndPersist();
              networkActions.resync();
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
                  .map((e) =>
                      ComboBoxItem(value: e.name, child: Txt(txt(e.name))))
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
                child: Txt(txt("ISO")),
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
                const ComboBoxItem(value: "en", child: Txt("English")),
                const ComboBoxItem(value: "ar", child: Txt("العربية")),
                const ComboBoxItem(value: "fa", child: Txt("فارسی")),
                const ComboBoxItem(value: "es", child: Txt("Español")),
                const ComboBoxItem(value: "fr", child: Txt("Français")),
                const ComboBoxItem(value: "de", child: Txt("Deutsch")),
                const ComboBoxItem(value: "pt", child: Txt("Português")),
                const ComboBoxItem(value: "tr", child: Txt("Türkçe")),
                const ComboBoxItem(value: "it", child: Txt("Italiano")),
                const ComboBoxItem(value: "ru", child: Txt("Русский")),
                const ComboBoxItem(value: "nl", child: Txt("Nederlands")),
                const ComboBoxItem(value: "pl", child: Txt("Polski")),
                const ComboBoxItem(value: "ro", child: Txt("Română")),
                const ComboBoxItem(value: "hu", child: Txt("Magyar")),
                const ComboBoxItem(value: "cs", child: Txt("Čeština")),
                const ComboBoxItem(value: "sk", child: Txt("Slovenčina")),
                const ComboBoxItem(value: "uk", child: Txt("Українська")),
                const ComboBoxItem(value: "bg", child: Txt("Български")),
                const ComboBoxItem(value: "hr", child: Txt("Hrvatski")),
                const ComboBoxItem(value: "sr", child: Txt("Српски")),
                const ComboBoxItem(value: "el", child: Txt("Ελληνικά")),
                const ComboBoxItem(value: "hi", child: Txt("हिन्दी")),
                const ComboBoxItem(value: "zh", child: Txt("中文")),
                const ComboBoxItem(value: "kr", child: Txt("한국어")),
                const ComboBoxItem(value: "ja", child: Txt("日本語")),
                const ComboBoxItem(value: "bn", child: Txt("বাংলা")),
                const ComboBoxItem(value: "ms", child: Txt("Bahasa Melayu")),
                const ComboBoxItem(value: "th", child: Txt("ไทย")),
                const ComboBoxItem(value: "vi", child: Txt("Tiếng Việt")),
                const ComboBoxItem(value: "sw", child: Txt("Kiswahili")),
              ],
              initValue: localSettings.transcriptionLocale,
              apply: (newVal) {
                localSettings.transcriptionLocale = newVal;
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
                      const Icon(FluentIcons.offline_storage),
                      const SizedBox(width: 10),
                      Txt(txt("cacheReset"))
                    ],
                  ),
                  onPressed: () async {
                    showDialog(
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    spacing: 10,
                                    children: [
                                      if (!cacheResetState()
                                          .startsWith("Error"))
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
                        });

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
            const S3Settings(),
            const SmtpSettings(),
            const BackupsSettings(),
          ],
        ],
      ),
    );
  }
}

class SettingsItem extends StatefulWidget {
  final String title;
  final String description;
  final IconData icon;
  final InputType inputType;
  final String identifier;
  final Scope scope;
  final List<ComboBoxItem<String>> options;
  final Widget? footer;
  final String initValue;
  final Function(String newVal) apply;

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

  @override
  State<StatefulWidget> createState() => SettingsItemState();
}

class SettingsItemState extends State<SettingsItem> {
  final TextEditingController _controller = TextEditingController();
  String value = "";

  @override
  void initState() {
    super.initState();
    _controller.text = widget.initValue;
    value = widget.initValue;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: Expander(
        leading: Icon(widget.icon),
        header: Txt(widget.title),
        content: SizedBox(
          width: 400,
          child: MStreamBuilder(
              streams: [
                globalSettings.observableMap.stream,
                localSettings.stream
              ],
              builder: (context, _) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.inputType == InputType.text ||
                        widget.inputType == InputType.multiline)
                      CupertinoTextField(
                        key: Key("${widget.identifier}_text_field"),
                        controller: _controller,
                        onChanged: (value) {
                          final currentPosition = _controller.selection;
                          setState(() => _controller.text = value);
                          _controller.selection = currentPosition;
                        },
                        maxLines:
                            widget.inputType == InputType.multiline ? 1 : null,
                        placeholder: txt(widget.title),
                      )
                    else if (widget.inputType == InputType.dropDown)
                      ComboBox<String>(
                        key: Key("${widget.identifier}_combo"),
                        items: widget.options,
                        onChanged: (value) => setState(() =>
                            value != null ? _controller.text = value : null),
                        value: _controller.text,
                      ),
                    const SizedBox(height: 5),
                    Txt(widget.description,
                        style: const TextStyle(
                            fontSize: 12, fontStyle: FontStyle.italic)),
                    const SizedBox(height: 10),
                    if (_controller.text != value) buildSaveCancelButtons(),
                    if (widget.footer != null) widget.footer!,
                  ],
                );
              }),
        ),
        initiallyExpanded: false,
        trailing: AppliesToIndicator(scope: widget.scope),
      ),
    );
  }

  Row buildSaveCancelButtons() {
    return Row(
      children: [
        FilledButton(
          onPressed: () {
            setState(() {
              widget.apply(_controller.text);
              value = _controller.text;
            });
          },
          child: Row(children: [
            const Icon(WindowsIcons.save),
            const SizedBox(width: 10),
            Txt(txt("save")),
          ]),
        ),
        const SizedBox(width: 10),
        FilledButton(
          style: greyButtonStyle,
          onPressed: () {
            setState(() {
              _controller.text = widget.initValue;
            });
          },
          child: Row(children: [
            const Icon(WindowsIcons.cancel),
            const SizedBox(width: 10),
            Txt(txt("cancel")),
          ]),
        ),
      ],
    );
  }
}

final cacheResetState = ObservableState("");

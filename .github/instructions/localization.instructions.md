---
description: Apexo localization — dictionary locales, txt()/Txt, adding strings and locales, auditing keys, RTL, and date/number formatting per locale.
applyTo: "{lib/services/localization/**,lib/common_widgets/**,lib/features/**,lib/ui/**,lib/app/**,lib/shared/**}"
---

# Apexo Localization

Custom dictionary localization — **not** `gen-l10n`/ARB. Ten locales: `en`, `ar`, `es`, `el`, `fa`, `ku` (Sorani), `fr`, `tr`, `it`, `ur`.

| File | Role |
|---|---|
| `en.dart` | Reference locale. `class En` with `$direction`, `$name`, `$code`, `dictionary`; also exports `TextDirection` |
| `<code>.dart` | One per locale, `implements En` |
| `locale.dart` | Runtime: `locale.s` (active `En`), `locale.isRtl`, `txt(key)`, the `Txt` widget, the `list` whose order defines `localSettings.selectedLocale` |
| `intl_data.dart` | `intl` number/date symbols for locales `intl` lacks (`ku`) |
| `flutter_delegates.dart` | `appLocalizationsDelegates` — Flutter framework delegates for locales Flutter lacks (`ku`) |
| `verify.dart` | CLI audit: key parity across locales, unused keys, dynamic `txt()` calls |

## Adding a string

1. Add the key to `en.dart` (`"myNewKey": "My New String",`) under the matching section comment.
2. Add the same key to **every** other locale file. A missing key renders the raw English key.
3. Use it: `Txt(txt("myNewKey"))`.
4. Run `dart run lib/services/localization/verify.dart`.

`txt(key)` resolves once; `Txt(text)` is `Text` plus a locale-stream rebuild — prefer it for anything on screen. **`Txt` renders its argument verbatim**: `Txt("myNewKey")` shows `myNewKey`.

### Naming a record in a sentence

Keep a `{name}` token in the dictionary and substitute at the call site — each language decides where the name belongs:

```dart
"openPatientRecord": "Open {name}'s record",
Txt(txt("openPatientRecord").replaceAll("{name}", patient.title))
```

## RTL

- RTL locales: `ar`, `fa`, `ku`, `ur` (`$direction = TextDirection.rtl`).
- The root `Directionality` comes from Flutter's `Localizations` via `FluentApp(locale:, localizationsDelegates: appLocalizationsDelegates)`; rows, alignment and text flip automatically. Do **not** flip a plain `Row` with `locale.isRtl`.
- Use `locale.isRtl` only for manual math: custom painting, `Alignment`/`Offset`, animations.
- `Txt` inherits the ambient direction; pass `textDirection` only for text that must stay LTR (emails, URLs, phone numbers, money).

## Dates, numbers, money

- UI dates and times go through `DF` (`lib/features/settings/settings_stores.dart`): `commonDate`, `full`, `fullCompact`, `allNumbers`, `dayOfWeek`, `time`, `timeOnly`, `hourLabel`. It honours the calendar system (`gregorian` / `persian` / `hijri`) and the locale.
- Never format a user-visible date with a raw `DateFormat` — it ignores the calendar setting.
- Money: `MoneyDisplay` / `formatMoneyInText`, `MoneyInputFormatter` for fields. `intl` patterns use `locale.s.$code`.

## Adding a locale

1. Create `<code>.dart` with `class Xx implements En` (`$direction`, `$name`, `$code`, full `dictionary`).
2. Register it in `locale.dart`'s `list` — appending keeps existing stored indices valid.
3. If `intl` lacks the locale, register symbols in `intl_data.dart` (`ensureCustomIntlLocalesInitialized()` in `main.dart`) and add `initializeDateFormatting(code)`.
4. If Flutter lacks the locale, add its delegates in `flutter_delegates.dart` (a `WidgetsLocalizations` with `textDirection` is what makes the app RTL; Material/Cupertino can point at the closest supported language).

## Common mistakes

| Mistake | Consequence |
|---|---|
| A key added to `en.dart` only | Raw English key for other locales |
| `Text(txt("key"))` | Text does not change on a language switch |
| `Txt("key")` | The key itself is displayed |
| Dropping `localizationsDelegates: appLocalizationsDelegates` | Kurdish gets LTR and no Material/Cupertino data; date pickers throw |
| Dynamic `txt(variable)` | Invisible to `verify.dart` |
| Raw `DateFormat` in UI | Ignores the Persian/Hijri calendar setting |

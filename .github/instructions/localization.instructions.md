---
description: Localization system for Apexo — how to add translations, create new locales, audit keys, and handle RTL. Applies when working with UI strings, user-facing text, locale files, or the txt()/Txt localization API.
applyTo: "lib/services/localization/**"
---

# Apexo Localization System

## Architecture

Apexo uses a **custom dictionary-based localization system** for app strings — not Flutter's `gen-l10n`/ARB workflow. Ten locales are supported: English (`en`), Arabic (`ar`), Spanish (`es`), Greek (`el`), Persian (`fa`), Sorani Kurdish (`ku`), French (`fr`), Turkish (`tr`), Italian (`it`), and Urdu (`ur`).

Framework chrome that Flutter itself localizes (date pickers, text-selection menus, accessibility labels) is separate: it comes from Flutter's own delegates, patched for the locales Flutter does not ship by `flutter_delegates.dart`.

### Key Files

| File | Purpose |
|------|---------|
| `lib/services/localization/en.dart` | **Reference locale** — all other locales mirror its keys. Defines the `En` class with `$direction` (`TextDirection`), `$name`, `$code`, and `dictionary` map. Also re-exports `TextDirection` for the per-locale files. |
| `lib/services/localization/ar.dart` | Arabic (RTL) — `implements En` |
| `lib/services/localization/es.dart` | Spanish (LTR) — `implements En` |
| `lib/services/localization/el.dart` | Greek (LTR) — `implements En` |
| `lib/services/localization/fa.dart` | Persian (RTL) — `implements En` |
| `lib/services/localization/ku.dart` | Sorani Kurdish (RTL) — `implements En` |
| `lib/services/localization/fr.dart` | French (LTR) — `implements En` |
| `lib/services/localization/tr.dart` | Turkish (LTR) — `implements En` |
| `lib/services/localization/it.dart` | Italian (LTR) — `implements En` |
| `lib/services/localization/ur.dart` | Urdu (RTL) — `implements En` |
| `lib/services/localization/locale.dart` | Runtime core — `_Localization` class, `locale`, `txt()` function, `Txt` widget. Nothing locale-specific or framework-specific lives here. |
| `lib/services/localization/intl_data.dart` | `intl` number/date symbols for locales `intl` does not ship (currently `ku`). Called from `main.dart` and from `locale.dart`. |
| `lib/services/localization/flutter_delegates.dart` | Flutter framework delegate overrides for locales Flutter does not ship (currently `ku`): `Directionality` data, Material and Cupertino localizations. Exposes `appLocalizationsDelegates`, passed to `FluentApp`. |
| `lib/services/localization/verify.dart` | CLI audit tool — checks key parity and scans for unlocalized strings. A locale file is detected by the dictionary it defines, so support files in this folder are ignored automatically. |

### Runtime Flow

1. `localSettings.selectedLocale` holds the index (0=en, 1=ar, 2=es, 3=el, 4=fa, 5=ku, 6=fr, 7=tr, 8=it, 9=ur).
2. `locale.s` returns the active `En` instance: `list[localSettings.selectedLocale]`.
3. `locale.isRtl` checks `$direction == TextDirection.rtl`.

## Adding a New Translatable String

### Step 1: Add the English key to `en.dart`

Open `lib/services/localization/en.dart` and add to the `dictionary` map:

```dart
"myNewKey": "My New String",
```

Follow existing organizational comments (`// common`, `// dashboard`, `// appointment card`, etc.) or create a new section if needed.

### Step 2: Add translations to ALL other locale files

Add the same key to **every** locale file (`ar.dart`, `es.dart`, `el.dart`):

```dart
// ar.dart
"myNewKey": "النص العربي هنا",

// es.dart
"myNewKey": "Texto en español aquí",

// el.dart
"myNewKey": "Ελληνικό κείμενο εδώ",
```

> ⚠️ **CRITICAL**: Every locale MUST have exactly the same set of keys as `en.dart`. Missing keys will cause the fallback to show the raw English key string.

### Step 3: Use in code

Resolve the key with `txt()`, then render the result:

```dart
Text(txt("myNewKey"))   // resolved once; does not follow a language switch
Txt(txt("myNewKey"))    // rebuilds when the user switches language
```

**Prefer `Txt` over `Text`** — `Txt` is a `StreamBuilder` on the locale stream, so it retranslates while the screen is open.

> ⚠️ `Txt` renders its argument **verbatim** — it does not look the key up itself. It is `Text` plus the locale stream. `Txt("myNewKey")` displays the literal text `myNewKey`; always hand it the `txt(...)` result.

### Strings that name a record

A sentence that has to name a record keeps a `{name}` token in the dictionary,
and the caller fills it in:

```dart
"openPatientRecord": "Open {name}'s record",
```

```dart
text: Txt(txt("openPatientRecord").replaceAll("{name}", patient.title)),
```

The token is plain text to `txt()`, so the sentence comes back with it intact —
the caller substitutes, and each language decides where in its sentence the name
belongs (`{name} kaydını aç` in Turkish, `Ouvrir la fiche de {name}` in French).

### Step 4: Run the audit tool

```bash
dart run lib/services/localization/verify.dart
```

This tool:
- Checks all locale files have identical keys
- Reports missing and extra keys
- Scans the entire codebase for `txt("...")` calls
- Reports keys in `dictionary` that are never used
- Reports dynamic `txt()` calls that can't be statically analyzed

## Adding a New Locale

1. Create a new file in `lib/services/localization/` (e.g., `fr.dart`).
2. Import `en.dart` and implement the `En` interface:

```dart
import 'en.dart';

class Fr implements En {
  @override
  TextDirection $direction = TextDirection.ltr;
  @override
  String $name = "Français";
  @override
  String $code = "fr";

  @override
  Map<String, String> dictionary = {
    "cancel": "Annuler",
    // ... ALL keys from en.dart ...
  };
}
```

3. Register the locale in `lib/services/localization/locale.dart`:
   - Import the new file
   - Add `Fr()` to the `list` array
   - Update `localSettings.selectedLocale` logic if needed

4. Ensure `initializeDateFormatting('fr', null)` is called in `main.dart` if the locale needs date formatting support. Custom locales may also need number/date symbols registered in `intl_data.dart` via `ensureCustomIntlLocalesInitialized()` (see `ku`).
5. If Flutter's own delegates do not support the language code, add the locale's delegates to `appLocalizationsDelegates` in `flutter_delegates.dart` — a `WidgetsLocalizations` delegate supplies `textDirection` (without one the app silently falls back to LTR) and `Material`/`Cupertino` delegates prevent the debug warning at startup. Point the Material/Cupertino delegates at the closest supported language as a fallback (see `_KuMaterialLocalizationsDelegate`).

## RTL (Right-to-Left) Support

- **Arabic** (`ar.dart`), **Persian** (`fa.dart`), **Sorani Kurdish** (`ku.dart`), and **Urdu** (`ur.dart`) are RTL: `$direction = TextDirection.rtl`
- The app's root `Directionality` comes from Flutter's `Localizations`, driven by `FluentApp(locale: Locale(locale.s.$code), localizationsDelegates: appLocalizationsDelegates)`. `Row`s, `NavigationView`, alignment and text direction therefore flip automatically — do not use `locale.isRtl` to flip a plain `Row` yourself.
- Flutter ships no `ku` data for its `Widgets`/`Material`/`Cupertino` delegates. `appLocalizationsDelegates` in `flutter_delegates.dart` supplies them: a Kurdish `WidgetsLocalizations` with `TextDirection.rtl` (this is what makes the whole app RTL) plus Material/Cupertino delegates backed by the Arabic data set. Removing that list reintroduces the `ku is not supported by all of its localization delegates` warning and an LTR layout.
- Check `locale.isRtl` only for manual, non-directional work such as custom painting, `Alignment`/`Offset` math, or animations.
- The `Txt` widget does NOT automatically set `textDirection` — it inherits the ambient `Directionality`, which is correct in RTL builds. Only pass an explicit `textDirection` when text must stay LTR regardless of the UI language (emails, URLs, phone numbers, money).

## Key Naming Conventions

- Keys are **camelCase** English strings used as dictionary keys
- No prefixes or namespaces — keys are flat
- Categorized by code comments (`// common`, `// dashboard`, etc.)
- The raw key string is used as fallback if a translation is missing

## Testing Translations

The locale can be switched at runtime via Settings → Language picker. The `localSettings` stream notifies all `Txt` widgets to rebuild.

For unit tests, you can directly set `localSettings.selectedLocale(index)` and verify `txt("someKey")` returns the expected string.

## Common Mistakes

| Mistake | Consequence |
|---------|-------------|
| Adding a key to `en.dart` but missing other locales | Raw English key shown for those locales |
| Using `Text(txt("key"))` instead of `Txt(txt("key"))` | Text won't update when user switches language at runtime |
| Passing a raw key to `Txt`, e.g. `Txt("myNewKey")` | `Txt` renders verbatim — the key itself is displayed; pass `Txt(txt("myNewKey"))` |
| Forgetting to run `verify.dart` after changes | Drift between locale files goes undetected |
| Using dynamic keys with `txt(someVariable)` | Can't be statically audited by `verify.dart` |
| Dropping `localizationsDelegates: appLocalizationsDelegates` from `FluentApp` | Kurdish gets Flutter's LTR widget data and no Material/Cupertino localizations: every row flips back to LTR, Material date/time pickers throw, and the startup warning returns |

---
description: Localization system for Apexo — how to add translations, create new locales, audit keys, and handle RTL. Applies when working with UI strings, user-facing text, locale files, or the txt()/Txt localization API.
applyTo: "lib/services/localization/**"
---

# Apexo Localization System

## Architecture

Apexo uses a **custom dictionary-based localization system** (not Flutter's `flutter_localizations`). The system is lightweight and designed for a dental clinic management app with English, Arabic, Spanish, and Greek support.

### Key Files

| File | Purpose |
|------|---------|
| `lib/services/localization/en.dart` | **Reference locale** — all other locales mirror its keys. Defines the `En` class with `$direction`, `$name`, `$code`, and `dictionary` map. |
| `lib/services/localization/ar.dart` | Arabic (RTL) — `implements En` |
| `lib/services/localization/es.dart` | Spanish (LTR) — `implements En` |
| `lib/services/localization/el.dart` | Greek (LTR) — `implements En` |
| `lib/services/localization/locale.dart` | Runtime locale selection — `_Localization` class, `txt()` function, `Txt` widget |
| `lib/services/localization/verify.dart` | CLI audit tool — checks key parity and scans for unlocalized strings |

### Runtime Flow

1. `localSettings.selectedLocale` (an `ObservableState<int>`) holds the index (0=en, 1=ar, 2=es, 3=el).
2. `locale.s` returns the active `En` instance: `list[localSettings.selectedLocale]`.
3. `locale.isRtl` checks `$direction == Direction.rtl`.

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

Use the `txt()` function for inline strings:

```dart
Text(txt("myNewKey"))
```

Or use the `Txt` widget (which auto-rebuilds on locale change):

```dart
const Txt("myNewKey")
```

**Prefer `Txt` over `Text(txt(...))`** — `Txt` is a `StreamBuilder` that automatically rebuilds when the user switches language.

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
  Direction $direction = Direction.ltr;
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

4. Ensure `initializeDateFormatting('fr', null)` is called in `main.dart` if the locale needs date formatting support.

## RTL (Right-to-Left) Support

- Only **Arabic** (`ar.dart`) is RTL: `$direction = Direction.rtl`
- Check `locale.isRtl` for conditional RTL layout adjustments
- The `Txt` widget does NOT automatically set `textDirection` — if you need RTL text direction, use `Text(txt(...), textDirection: locale.isRtl ? TextDirection.rtl : TextDirection.ltr)`

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
| Using `Text(txt("key"))` instead of `Txt("key")` | Text won't update when user switches language at runtime |
| Forgetting to run `verify.dart` after changes | Drift between locale files goes undetected |
| Using dynamic keys with `txt(someVariable)` | Can't be statically audited by `verify.dart` |

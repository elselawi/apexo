---
description: Testing conventions for Apexo — deterministic unit tests, live PocketBase tests, test boundaries, fixtures, and serial execution.
applyTo: "test/**, integration_test/**, dart_test.yaml, README.md"
---

# Apexo Testing Conventions

## Layout

Tests mirror `lib/`: `test/unit/{core,services,features,utils,app,common_widgets}/` for logic, and `test/widget/{features/<feature>,app,shared/<editor>,common_widgets}/` for pumped widgets.

| Category | Location | Rule |
|---|---|---|
| Unit | `test/unit/` | Deterministic. No `test/secret.dart`, no live helpers, no network |
| Live PocketBase | `test/live_backend/` | First line `@Tags(['live_backend'])`; may use `test/secret.dart` and `test/live_backend/test_utils.dart` |
| End-to-end | `integration_test/` | Separate from live backend; see `integration_test/readme.md` |

`test/helpers/` provides `hive_setup.dart` (isolated directories), `pump_app.dart` / `fake_session.dart` / `window_defaults.dart` (widget and panel harnesses) and `model_factory.dart`. Fixtures live in `test/fixtures/{models,pocketbase,ai_responses,dicom}/`.

## Commands

Run the deterministic unit suite serially:

```bash
flutter test test/unit --exclude-tags live_backend -j 1
```

Run live PocketBase tests serially after configuring credentials in `test/secret.dart` from `test/secret.dart.example`:

```bash
flutter test --tags live_backend test/live_backend -j 1
```

Run end-to-end tests according to `integration_test/readme.md`.

## Rules

- Use `-j 1`; tests share Hive, singleton stores, permissions, and other process-wide state. `dart_test.yaml` also defines the `serial` and `live_backend` tags.
- Keep live credentials out of committed files. `test/secret.dart` is local-only; commit only `test/secret.dart.example`.
- Prefer isolated Hive directories through `test/helpers/hive_setup.dart` for persistence tests.
- Use fixtures from `test/fixtures/` instead of live responses when testing parsing or serialization.
- Widget tests find widgets by `WK.*` keys (`lib/widget_keys.dart`), not by visible text, which changes with the locale.
- Keep live backend tests out of `test/unit/`; `test/unit/test_suite_structure_test.dart` enforces both this boundary and the tagging rule.
- Do not run live backend tests as part of the normal unit command.

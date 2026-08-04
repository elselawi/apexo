---
description: Testing conventions for Apexo — deterministic unit tests, live PocketBase tests, test boundaries, fixtures, and serial execution.
applyTo: "test/**, integration_test/**, dart_test.yaml, README.md"
---

# Apexo Testing Conventions

## Test categories

- **Unit tests** live under `test/unit/` and must be deterministic. They must not import `test/secret.dart`, live-backend helpers, or use live network credentials.
- **Live PocketBase tests** live under `test/live_backend/` and must begin with `@Tags(['live_backend'])`. They may import `test/secret.dart` and use the shared helper at `test/live_backend/test_utils.dart`.
- **End-to-end tests** live under `integration_test/` and are separate from the live PocketBase test category.

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

- Use `-j 1`; tests share Hive, singleton stores, permissions, and other process-wide state.
- Keep live credentials out of committed files. `test/secret.dart` is local-only; commit only `test/secret.dart.example`.
- Prefer isolated Hive directories through `test/helpers/hive_setup.dart` for persistence tests.
- Use fixtures from `test/fixtures/` instead of live responses when testing parsing or serialization.
- Keep live backend tests out of `test/unit/`; the boundary test in `test/unit/test_suite_structure_test.dart` enforces this separation.
- Do not run live backend tests as part of the normal unit command.

# Project instructions

## Project references

- Read `README.md` for the addon overview, installation, and standard build/test
  commands.
- Read `docs/DATA_ARCHITECTURE.md` before changing generated data, provenance,
  provider boundaries, or source merge behavior.
- Read `release.toml` when changing release, compatibility, schema, or pinned
  client-data versions. It is the source of release metadata used by
  `tools/package_release.py`.
- Update `CHANGELOG.md` for user-visible changes and release preparation.
- Keep detailed workflows and architecture in focused files under `docs/` and
  link them from this section instead of expanding `AGENTS.md` with long-form
  documentation.

## UI localization

- When adding or changing any user-facing addon feature, menu, control, tooltip, message, or other interface text, provide localization for every language currently supported by the addon.
- Do not hardcode new user-facing strings in UI or feature code. Add them to `Foreverpedia/Localization.lua` and reference them through the localization API.
- Keep the localization key sets complete and consistent across all supported languages (currently `ruRU` and `enUS`).

# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-07-11

### Added

- Server lifecycle scripts: a blocking foreground launcher (`bun run dev`) and a detached,
  non-blocking background launcher (`bun run start`) with graceful-first stop (`bun run stop`),
  modeled on a hardened detached-spawn pattern that does not inherit or pin the listening socket.
- An aggregate quality gate `bun run smoke:qc` that runs PSScriptAnalyzer, ESLint, Pester, the
  Tailwind CSS build, a Prettier format check, and knip, reporting every failure rather than
  stopping at the first.
- htmx 4 client-side extension ports (debug, json-enc, client-side-templates) maintained under
  `src/vendor/` and copied to `public/js` by the build, replacing the htmx 2.x npm extensions
  after the `htmx.org` 4.x upgrade.
- A loopback guard that restricts the debug routes (`/stop`, `/clear`, `/init`) to localhost even
  when `Podex.Debug` is enabled.
- knip dead-code configuration and project capability blueprints under `.aidd/features/`, plus a
  Features section in the README documenting the current capabilities.

### Changed

- Migrated the JavaScript toolchain from npm/npx to bun/bunx across package scripts, the build,
  and documentation.
- Unified the Tailwind theme: the primary color scale now matches the brand header/footer, the
  typography plugin is enabled, and Home and CRUD Manager share consistent card/site-shell styling
  with a reserved scrollbar gutter that removes the inter-page layout shift.
- CRUD Manager Update controls are now inline-editable text fields (previously hidden inputs), so
  item and description edits persist through `PUT /api/crud`.
- The example SQLite database now lives under `data/` at the repository root (default
  `./data/podex.db`) instead of the repository root.

### Fixed

- CRUD persistence now works end to end: SQLite errors escalate to real 500 responses (PSSQLite's
  non-terminating errors were previously swallowed, masking a missing table as fake success), and
  the canonical `items` table is created from `api/debug/init.sql`. The CRUD handlers, schema,
  views, and tests are aligned on one `items` model.
- CRUD pagination now reports the true matching row count via a separate `SELECT COUNT(*)` instead
  of the current page length, so page counts and navigation are correct beyond the first page.
- The debug `/init` and `/clear` routes now resolve their SQL files at `./api/debug/` (previously
  read `./init.sql`/`./clear.sql` from the project root and returned 500).
- Prettier no longer corrupts `.pode` templates: the HTML-parser override was removed and `.pode`
  files are ignored, and the Tailwind v4 stylesheet is configured via `tailwindStylesheet`.
- The ESLint flat config now enables browser and Node globals and ignores the vendored `public/js`
  distribution files.

### Security

- Destructive debug routes are disabled by default (`Podex.Debug = $false`); route registration
  skips `api/debug/*` entirely when debug is off, and the dedicated
  `tests/debug-route-isolation.Tests.ps1` asserts the gating. When debug is enabled, the new
  loopback guard keeps those endpoints local-only.

Versions prior to 0.2.0 predate this changelog.

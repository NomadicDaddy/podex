# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.0] - 2026-07-13

### Added

- Generated license documents for shipped browser assets, external PowerShell modules, and
  build-only dependencies such as Lightning CSS and Sharp/libvips.
- `bun run release`, which stages the files listed in `release-manifest.json` and checks that the
  required notices are included.

### Changed

- Builds now use the frozen Bun lockfile and one browser asset command for htmx, Mustache, the
  adapted extensions, and Tailwind CSS.
- `smoke:qc` now checks license drift and inspects a staged release.

### Fixed

- Mustache and Tailwind files served to the browser now include their required notices.

### Security

- Release manifest entries are confined to the project and staging roots. Release checks reject
  dependency trees, Git metadata, databases, and missing notice files.

## [0.2.0] - 2026-07-11

### Added

- Server lifecycle commands for foreground development, background start, and graceful stop.
- `bun run smoke:qc` for PSScriptAnalyzer, ESLint, Pester, the Tailwind build, formatting, and knip.
- Maintained htmx 4 ports of the debug, json-enc, and client-side-templates extensions under
  `src/vendor/`.
- A loopback guard for the debug routes `/stop`, `/clear`, and `/init`.
- knip configuration and project capability records under `.aidd/features/`.

### Changed

- Migrated the JavaScript toolchain from npm and npx to Bun.
- Updated the Tailwind theme, enabled the typography plugin, and aligned the Home and CRUD Manager
  layouts.
- Made the CRUD Manager update controls editable inline.
- Moved the example SQLite database to `data/podex.db`.

### Fixed

- CRUD persistence now reports SQLite failures correctly, creates the `items` table from
  `api/debug/init.sql`, and uses the same model in handlers, views, and tests.
- Pagination now counts all matching rows instead of only the current page.
- The `/init` and `/clear` routes now find their SQL files under `api/debug/`.
- Prettier no longer treats `.pode` files as HTML, and it uses the Tailwind v4 stylesheet setting.
- ESLint now recognizes browser and Node globals and ignores generated files under `public/js/`.

### Security

- Destructive debug routes are disabled by default and are not registered unless `Podex.Debug` is
  enabled. When enabled, they remain local-only.

Versions prior to 0.2.0 predate this changelog.

# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- `api/crud/get.ps1` now parses `page` and `pageSize` with `[int]::TryParse` instead of hard-casting
  request values, which previously threw a cast exception for non-numeric inputs. Missing,
  non-numeric, zero, or negative values fall back to the documented defaults (`page=1`,
  `pageSize=10`), and `pageSize` values greater than 100 are clamped to 100. Added five Pester tests
  covering missing, non-numeric, zero, negative, and greater-than-100 inputs.

- Removed the debug hot-path response snapshot write and full-body logging from `api/crud/get.ps1`.
  When `Podex.Debug` was enabled, the handler wrote the full response as `get.json` into the source
  tree on every list request and logged the entire serialized body via `Write-FormattedLog`. Both
  are removed; only bounded metadata (`"Items found: <count>"`) is logged. Added a Pester test that
  runs `GET /api/crud` with debug enabled and asserts no snapshot file is created.

### Added

- `bun run release:check-tag <tag>`, which reads `public/js/mustache.js` from the named git tag and
  fails when the MIT copyright notice ("Copyright (c) 2009 Chris Wanstrath") is absent or the file
  cannot be read.
- A "Historical artifacts" section in README.md directing recipients of tags before v0.3.0 to use
  v0.3.0 or later.

### Compliance

- The public v0.2.0 tag distributed `public/js/mustache.js` without the MIT copyright and
  permission notice and contained neither THIRD_PARTY_NOTICES.md nor THIRD_PARTY_LICENSES.md. Its
  LICENSE file also carried a template-leftover copyright holder ("adminware") instead of
  "Phillip Beazley". All three defects were corrected in v0.3.0, but the v0.2.0 tag remains
  downloadable as a historical artifact and should not be redistributed.

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

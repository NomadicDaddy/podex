# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.5.0] - 2026-07-30

### Added

- Added PowerShell formatting and Pode template compilation gates. The analyzer, formatter, and
  Pester runner now fail the build when they find a real problem instead of reporting success.

### Changed

- Podex now starts, stops, resolves routes, and locates its database from the application root
  regardless of the caller's working directory. Debug lifecycle routes are loopback-only and use
  explicit HTTP methods and headers.
- A clean build installs the supported Pode and PSSQLite versions, creates the data directory, and
  initializes a missing database. Initialization and clearing are repeatable and fail closed.
- CRUD responses now use stable arrays, bounded inputs, consistent error envelopes, and UTC
  timestamps. The page keeps search and pagination state across successful mutations.
- The shared header and footer use solid theme colors. The logo keeps its aspect ratio, and the
  brand and navigation remain grouped on the left.

### Fixed

- Search treats `%`, `_`, and `\` as literal characters, clamps out-of-range pages, and no longer
  lets htmx 4 overwrite a pagination button's destination with the current page.
- The add-item modal now keeps failed input visible, refreshes only after successful mutations, and
  supports keyboard focus, Escape, backdrop clicks, and clicks on SVG descendants of close controls.
- Home and CRUD page routes accept GET only. Page headings, repeated form controls, live update
  regions, responsive images, and system dark mode now have the expected accessibility behavior.
- Normal and error page titles are consistent, the OpenAPI version comes from `package.json`, and
  error pages no longer expose request data, runtime versions, exception text, or stack traces.

### Security

- Added content type, referrer, frame, and Content Security Policy headers to every route. HSTS is
  enabled only for HTTPS, and first-party scripts work without inline JavaScript.
- The withdrawn v0.2.0 and v0.3.0 releases are no longer downloadable. Their commits remain in Git
  history, but neither old release had a verified archive and v0.2.0 omitted Mustache's MIT notice.

## [0.4.0] - 2026-07-22

### Added

- `bun run release:check-tag <tag>`, which reads `public/js/mustache.js` from the named git tag and
  fails when the MIT copyright notice ("Copyright (c) 2009 Chris Wanstrath") is absent or the file
  cannot be read.
- A "Historical artifacts" section in README.md directing recipients of tags before v0.3.0 to use
  v0.3.0 or later.
- A pre-push hook under `.githooks/` that blocks a push carrying `.aidd/` metadata, enabled by
  `git config core.hooksPath .githooks`. A clean working tree says nothing about the commits behind
  it, so the guard queries the history in the push range rather than the tip. Contributors who clone
  the repository must set `core.hooksPath` themselves; Git does not install hooks on clone.
- `bun run check:license-core`, a fail-closed self-test of the license-classification core that runs
  ahead of `check:licenses`, plus a positive reviewed-license allowlist in `license-catalog.mjs`
  layered on top of the existing restrictive-license denylist.

### Changed

- Browser assets now build only the unminified htmx and Mustache files used by the application.
  Asset-build packages are classified as development dependencies, and generated release-license
  documents no longer serialize platform-specific optional build packages, which vary by host.
  Host-neutral copyleft build components remain disclosed, and `release:check` now enforces that
  the copyleft section and the Lightning CSS distribution boundary survive regeneration.
- The About page now uses explicit Tailwind utilities instead of the Typography plugin.
- The installed-closure walk, SPDX review, and manifest reading now route through the shared
  `scripts/lib/license-core` modules. These files are synced from an upstream source and carry a
  header saying so: edits must originate upstream, and exports with no caller in this repository are
  expected because other adopters consume them.
- Bumped `tailwindcss` to 4.3.3 and `prettier-plugin-tailwindcss` to 0.8.1.

### Removed

- The `/htmx/hello` example route and its `htmx/hello.ps1` handler. The htmx fragment convention is
  still demonstrated by `/htmx/item-new`, which the CRUD Manager uses. Anyone who called
  `/htmx/hello` directly will now get a 404.
- The vendored htmx debug extension (`src/vendor/debug.js`) and the `debug.js` script tag on every
  page. It logged htmx lifecycle events and was never enabled outside local experimentation.
- The minified `htmx.min.js` and `mustache.min.js` browser assets. Nothing loaded them; pages have
  always used the unminified files.
- The Sharp image optimizer (`tools/optimize-images.js`), the Knip gate, and the SQL Prettier
  plugin, none of which were reachable from the build. `bun run smoke:qc` no longer runs `knip`.
- The obsolete `tests/tests.ps1.old` CRUD test backup, superseded by the Pester suite under
  `tests/`.

### Fixed

- The Pester command now returns a nonzero process exit code when the run does not pass, correctly
  failing `smoke:qc` without leaving a test-results artifact in the repository. The gate keys on the
  overall Pester result, so a test file that fails during discovery also fails the build instead of
  reporting zero failed tests.

- `server.psd1` now sets `Web.ErrorPages.ShowExceptions = $false` in the checked-in default
  configuration. Unhandled errors no longer render full PowerShell stack traces, module paths, and
  source structure to the client. Because `ShowExceptions` and `Podex.Debug` are independent
  settings, `Podex.Debug` alone never exposes exception detail; an operator must explicitly edit
  both to `$true` to see local exception detail during development. Added
  `tests/error-page-disclosure.Tests.ps1` with three Pester tests asserting the checked-in default
  disables `ShowExceptions` and `Podex.Debug`.

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

- `bun run release` now produces a final `dist/podex-<version>.zip` archive from the staging tree,
  and `release:check` verifies the archive's extracted contents rather than the staging directory it
  was built from. Previously the process staged files but never produced or verified a shippable
  artifact, so nothing checked what recipients would actually receive. The gate fails closed on a
  missing archive, a failed extraction, or an empty extracted tree. Added
  `tests/release-archive.Tests.ps1` with three Pester tests.

- Restored fail-closed license coverage lost when the dependency closure became an installed
  listing: nested version-conflicted copies are scanned again, and the generator now fails when a
  declared dependency is missing from the installed tree. Extended the classification harness with
  GPL, AGPL, SSPL, and WTFPL cases.

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

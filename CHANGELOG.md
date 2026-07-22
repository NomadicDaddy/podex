# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- PowerShell format consistency gate and Pode template compile regression
  (`podex-powershell-and-template-quality-gates`). Added
  `PSScriptAnalyzerSettings.psd1` (tab indentation, four-column tab display
  width, OTBS braces, consistent whitespace, `PSUseCorrectCasing`) and
  `tools/format-check.ps1`, which runs `Invoke-Formatter` with those settings
  over the same recursive `.ps1`/`.psm1`/`.psd1` source set and exclusions as
  `tools/analyze.ps1` and exits 1 when any file's formatted text differs from
  its checked-in content. Added the `format:pwsh:check` package script and a
  distinct `format:pwsh:check` gate to `tools/smoke-qc.ps1` (`bun run analyze`
  remains a separate fail-closed gate). Added `tests/pode-templates.Tests.ps1`
  which reads every `views/**/*.pode` and `errors/**/*.pode` file, applies
  Pode 2.13's `ConvertFrom-PodeFile` escaping shape locally, and verifies
  `[scriptblock]::Create` succeeds — including a TestDrive malformed-template
  fixture that proves the shape rejects broken templates. Added
  `tests/powershell-format.Tests.ps1` which proves the format checker passes for
  the project source tree, exits 1 for a misformatted TestDrive fixture, and
  exits 0 for a pre-formatted fixture.

### Fixed

- Narrowed `tools/test.ps1` to discover `tests/*.Tests.ps1` containers (was
  `tests/*.ps1`), so the glob is explicit and future-proof. Normalized
  `server.psd1`, `tools/analyze.ps1`, and `tools/stop.ps1` to conform to the
  project formatting settings (spaces to tabs, OTBS `} catch {`, pipeline
  continuation indent). Removed the duplicate `Podex.Debug` /
  `ShowExceptions` assertion-only case from
  `tests/error-page-disclosure.Tests.ps1` while retaining one independent
  assertion for each setting. Fixed the `server.psd1` config backup logic in
  `tests/security-headers.Tests.ps1` and `tests/site-metadata.Tests.ps1` so
  multi-Describe containers back up the checked-in config only once; previously
  the second `Describe` overwrote the backup with a temp config, leaving
  `server.psd1` polluted (wrong port and database path) after a test run. All
  197 tests pass and `bun run smoke:qc` exits 0.

### Fixed

- Unified the error pages and site metadata into one consistent contract
  (`podex-error-pages-and-site-metadata`). `podex.ps1` now passes unprefixed
  page titles (`Home` and `CRUD Manager`) so `views/layouts/main.pode` renders
  exactly `Podex - <title>` with no double-prefix (`Podex - Podex -`). The
  OpenAPI version for `Add-PodeOAInfo -Version` is loaded once from
  `package.json`, removing the stale `0.0.1` literal. The version-bearing
  `<meta name="generator">` tag (which leaked `PSEdition`/`PSVersion` with an
  obsolete `0.1.2` Podex literal) was removed from `main.pode`,
  `errors/404.html.pode`, and `errors/default.html.pode`. Both error templates
  now reference `/public/images/podex.ico` (dropping the missing
  `favicon.svg`), follow the `Podex - <title>` convention, and no longer expose
  raw `$data | ConvertTo-Json` dumps, render timestamps, exception messages, or
  stack traces in client-visible markup. The error templates remain standalone
  but enforce the same charset, viewport, favicon, safe generator policy, and
  title convention through tests. 6 new static assertions were added to
  `tests/error-page-disclosure.Tests.ps1` and 14 new live-server assertions were
  added in the new `tests/site-metadata.Tests.ps1` (titles, favicon, no
  double-prefix, package-derived OpenAPI version, no generator tag, no
  PowerShell-version leak, and safe 404 markup including the 404 status code
  and title). Source feature `feature-framework-server` (spec line 7) amended
  to close the audit feedback loop.

- Stabilized the CRUD API contract, validation, and item data presentation
  (`podex-crud-contract-validation-and-data-presentation`). GET `/api/crud` now
  always returns `rows` as a stable array (using `ArrayList` to survive
  PowerShell's empty-array unwrapping), echoes the `search` parameter in the
  envelope, and formats `created_at` and `updated_at` as UTC RFC 3339 strings
  (`YYYY-MM-DDTHH:mm:ssZ`) via `strftime`. A `created_at_display` field
  (`YYYY-MM-DD HH:mm UTC`) is included for human-readable views. POST now
  returns `201` with `{ message, item }` containing the full created record
  with RFC 3339 timestamps, instead of a bare success message. PUT and DELETE
  now return `404 { message }` when `changes()` reports zero affected rows,
  distinguishing missing records from validation failures; DELETE also returns
  `400` for non-positive or non-numeric ids. Field-length validation (item
  1–200, description 1–2000) is enforced in POST and PUT before database
  access and mirrored as `maxlength` attributes in `crudmgr.pode` and
  `crudmgr-new.pode`. The table column uses `created_at_display` for readable
  timestamps. 22 new Pester test cases added covering empty/single row arrays,
  POST identity with timestamp format assertions, missing-record 404s, 200/2000
  boundary acceptance, over-limit 400 rejections, punctuation/Unicode round
  trips, exact timestamp/display formats, and search-echo behavior.

### Compliance

- The v0.2.0 and v0.3.0 tags were withdrawn from the public repository and are no longer
  downloadable. This supersedes the 0.4.0 note below, which recorded v0.2.0 as remaining available
  as a historical artifact. v0.4.0 is now the only published release. Neither tag carried release
  notes or a verified archive, and v0.2.0 additionally distributed `public/js/mustache.js` without
  its MIT copyright notice, so withdrawal also ends that non-compliant distribution. The underlying
  commits remain in history for anyone reconstructing the record: v0.2.0 pointed at `afcb6c0` and
  v0.3.0 at `c98f417`.

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

# Podex

Podex is a small starter for server-rendered web applications built with PowerShell,
[Pode](https://github.com/Badgerati/Pode), and [htmx](https://htmx.org/). The backend
serves Pode views and JSON endpoints; the browser uses htmx and
[Mustache](https://mustache.github.io/) for the CRUD example.

It includes:

- a SQLite-backed CRUD page with search, paging, create, edit, and delete actions;
- file-based API handlers under `api/`;
- Tailwind CSS, light and dark themes, and reusable Pode layouts and partials;
- OpenAPI output at `/docs/openapi` and Swagger UI at `/docs/swagger`;
- local-only database and server controls when `Podex.Debug` is enabled;
- Pester, PSScriptAnalyzer, ESLint, Prettier, and a single `smoke:qc` command.

## Requirements

- PowerShell 7
- Bun
- PSSQLite 1.x (runtime)
- Pode 2.x (runtime)

The build (`bun run build` / `.build.ps1`) installs PSSQLite, Pode, and the development
PowerShell modules (Pester, PSScriptAnalyzer) with pinned version ranges, then runs the
quality gates.

## Setup

```powershell
git clone https://github.com/NomadicDaddy/podex.git
Set-Location podex
bun run build
```

The CRUD example expects `data/podex.db`. To create it from the checked-in schema:

```powershell
New-Item -ItemType Directory -Path data -Force | Out-Null
$sql = Get-Content -Raw api/debug/init.sql
Invoke-SqliteQuery -DataSource data/podex.db -Query $sql
```

## Run Podex

Use `bun run dev` for a foreground server, or `bun run start` to run it in the background.
The app listens at `http://localhost:8433` by default.

```powershell
bun run dev
bun run start
bun run stop
```

## Checks and releases

`bun run smoke:qc` runs the PowerShell analyzer, ESLint, Pester, license checks, release
packaging, and formatting. It reports all failed gates before exiting.

`bun run release` rebuilds the browser assets, stages the files listed in
`release-manifest.json` under `dist/podex-<version>/`, and produces a final
`dist/podex-<version>.zip` archive from that staging tree. Pode and PSSQLite
stay external; `node_modules` is not included.

`release:check` verifies the archive's extracted contents, not the staging
tree: it extracts `dist/podex-<version>.zip` into a scratch directory, asserts
manifest presence, forbidden entries, notice text, copyright headers, and
byte-equality of staged license documents, and removes the scratch directory
afterward. A missing archive, a failed extraction, or an empty extracted tree
fails the gate.

## Release archive requirements

Use v0.4.0 or later for downloadable archives. It is the only published release: the v0.2.0 and
v0.3.0 tags were withdrawn, and no archive is distributed for either. Archives from v0.2.0 and
earlier also omitted the MIT copyright notice from `public/js/mustache.js` and contained no
third-party license documents, so any copy still in circulation should not be redistributed.

Before publishing a tag, verify its Mustache notice with `bun run release:check-tag <tag>`.

## Contributing

Run `bun run smoke:qc` before opening a pull request. Keep dependency changes in
`package.json` and `bun.lock`, and regenerate the license documents with
`bun run licenses:generate` when the dependency graph changes.

## License

Podex is available under the [MIT License](LICENSE). Third-party terms are listed in
[THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md), with full notices in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

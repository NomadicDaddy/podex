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

The build installs Pode and the development PowerShell modules. PSSQLite remains a manual
prerequisite:

```powershell
Install-Module -Name PSSQLite -MinimumVersion 1.1.0 -MaximumVersion 1.99.99 -Scope CurrentUser
```

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

`bun run release` rebuilds the browser assets and stages the files listed in
`release-manifest.json` under `dist/podex-<version>/`. Pode and PSSQLite stay external;
`node_modules` is not included.

## Release archive requirements

Use v0.3.0 or later for downloadable archives. Archives from v0.2.0 and earlier omit the MIT
copyright notice from `public/js/mustache.js` and do not contain third-party license documents.
Before publishing a tag, verify its Mustache notice with `bun run release:check-tag <tag>`.

## Contributing

Run `bun run smoke:qc` before opening a pull request. Keep dependency changes in
`package.json` and `bun.lock`, and regenerate the license documents with
`bun run licenses:generate` when the dependency graph changes.

## License

Podex is available under the [MIT License](LICENSE). Third-party terms are listed in
[THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md), with full notices in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

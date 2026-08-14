# Podex

Podex is a small starter for server-rendered web applications built with PowerShell,
[Pode](https://github.com/Badgerati/Pode), and [htmx](https://htmx.org/). The backend
serves complete Pode views, HTML fragments for htmx, and JSON responses for ordinary API
clients.

For a complete application built on the starter, see
[TodoMVC-Podex](https://github.com/NomadicDaddy/todomvc-podex). It preserves Podex's application
shell and operational conventions while replacing the reference CRUD surface with TodoMVC.

It includes:

- a SQLite-backed CRUD page with search, paging, create, edit, and delete actions;
- file-based API handlers under `api/`;
- dependency-free native CSS, light and dark themes, and reusable Pode layouts and partials;
- OpenAPI output at `/docs/openapi` and Swagger UI at `/docs/swagger`;
- local-only database and server controls when `Podex.Debug` is enabled;
- Pester, PSScriptAnalyzer, ESLint, Prettier, and a single `smoke:qc` command.

## Requirements

- PowerShell 7.6+
- Bun 1.3.14+
- TypeScript 6.0.3
- PSSQLite 1.x (runtime)
- Pode 2.14.0–2.x (runtime)

The build (`bun run build` / `.build.ps1`) installs PSSQLite, Pode, and the development
PowerShell modules (Pester, PSScriptAnalyzer) with pinned version ranges, then runs the
quality gates.

## Setup

```powershell
git clone https://github.com/NomadicDaddy/podex.git
Set-Location podex
bun run build
```

The build installs the required PowerShell modules (PSSQLite 1.x, Pode 2.14.0–2.x) for
the current user, installs Bun dependencies, runs every quality gate, and then
initializes the example database at `data/podex.db` from `api/debug/init.sql` if
it does not already exist. A clean checkout needs nothing else before
`bun run dev`.

If a database already exists at the configured path, the build leaves the
existing data intact. To reseed from the checked-in schema, delete
`data/podex.db` (or run `DELETE /clear` then `POST /init` with debug mode on).

## Run Podex

Use `bun run dev` for a foreground server, or `bun run start` to run it in the background.
The app listens at `http://localhost:8433` by default.

```powershell
bun run dev
bun run start
bun run stop
```

## Checks and releases

`bun run smoke:qc` enforces TypeScript-only source, exact dependency versions, the 300-line
runtime/tooling limit, strict type checking, PowerShell analysis and formatting, zero-warning
ESLint, Pester, license checks, and release packaging. Release verification also confirms that
every runtime-referenced public asset is present in the archive. The gate reports all failures
before exiting. `bun run smoke:qc:fast` skips only Pester.

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

## Contributing

Run `bun run smoke:qc` before opening a pull request. Keep dependency versions exact in
`package.json`, update `bun.lock`, and regenerate the license documents with
`bun run licenses:generate` when the dependency graph changes.

## License

Podex is available under the [MIT License](LICENSE). Third-party terms are listed in
[THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md), with full notices in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

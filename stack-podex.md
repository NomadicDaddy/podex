---
trigger: model_decision
description: Technical stack and working conventions for Podex
---

# Podex stack

Podex is a PowerShell 7 web application built on Pode, SQLite, htmx 4, Mustache, and
Tailwind CSS. It is not a Spernakit application and does not use the Spernakit backend or
frontend layout.

## Layout

- `podex.ps1` starts Pode and registers static, page, API, debug, and documentation routes.
- `server.psd1` holds the local server and application settings.
- `api/<domain>/<method>.ps1` contains file-based API handlers. `tools/PodexRoute.psm1`
  maps those files to routes.
- `views/` contains Pode layouts, partials, and page components.
- `src/vendor/` contains the maintained htmx 4 extension ports. The asset build copies
  them to `public/js/`.
- `public/css/tailwind.css` is the Tailwind source; `public/css/output.css` is generated.
- SQLite files belong under `data/`.

## Backend conventions

Use Pode route and response helpers rather than adding another web framework. Keep SQL
parameterized and return useful HTTP status codes from API handlers.

Debug handlers under `api/debug/` are registered only when `Podex.Debug` is enabled. They
use the short routes `/init`, `/clear`, and `/stop`, and the server restricts them to
loopback clients.

The runtime loads Pode 2.x and PSSQLite 1.x from the user's PowerShell module path. Do not
bundle those modules into the Podex release without carrying their license files as well.

## Browser code

htmx handles requests and swaps. The CRUD page uses the local `json-enc` and
`client-side-templates` extensions with Mustache templates. Keep the maintained extensions
in `src/vendor/`; edit those sources, then run `bun run css` to refresh all browser assets.

JavaScript modules and tooling use ES modules. Do not introduce CommonJS code.

## Commands

```powershell
bun install --frozen-lockfile
bun run dev
bun run start
bun run stop
bun run test
bun run smoke:qc
bun run release
```

`bun run dev` owns the foreground server. `start` and `stop` manage the background process.
Do not start, stop, or recycle a user-owned server unless the user asks.

`smoke:qc` is the required quality gate. It runs PSScriptAnalyzer, ESLint, Pester, license
checks, release packaging and verification, Prettier, and knip.

## Release and licensing

`release-manifest.json` is the release allowlist. Packaging must not include `node_modules`,
Git metadata, or a local database.

Run `bun run licenses:generate` after dependency changes and commit both generated license
documents. `bun run check:licenses` verifies them against the installed dependency graph.
Browser-delivered Mustache and Tailwind assets carry their notices directly.

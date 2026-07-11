---
trigger: model_decision
description: Technical Stack and Architecture Reference for Podex (Pode + HTMX)
---

## Development Workflow (TODO: update required)

- **Testing**: `bun run build`
- **Verification**: `bun run check-page-dev` (dev) or `bun run check-page-preview` (preview) - page-check "passing" means the script ended without a failure in itself. The logs and screenshots show good or bad results for the actual application. If there are any ERROR or UNCAUGHT EXCEPTIONS in the log, page isn't loading.
- **Server Management**: Don't restart dev/preview servers or local Convex dev server (always running)
- **Page Validation**: ANY uncaught exception/stack trace/browser error = failed check
- **Build Priority**: Ensure build passes before proceeding
- **Localhost**: Use 127.0.0.1 (not localhost) for consistency

Use these commands for validation:

```bash
bun run build
bun run check-page-dev      # Outputs to /scripts/check-page.log
bun run check-page-preview  # Outputs to /scripts/check-page.log
```

## Template-first Architecture

- Implementations must mirror the template’s structure and conventions first.
- Add custom features only after a clearly marked boundary comment (e.g., `// ===== CUSTOM APP SECTION =====`).
- If an implementation introduces an improvement, backport it into the template first, then re-apply downstream.
- Implementations may not diverge on naming, envelopes, or ordering unless the template has been updated accordingly.

## Additional Expertise

You also specialize in Pode, htmx, and \_hyperscript.

## Additional Environmental Considerations

- The application should be executable on any platform supported by that version of PowerShell.
- Unless otherwise specified, if a database is used, it will be sqlite and located in the application's data directory, e.g. `/data/{AppName}.db`.
- **NEVER start, restart, or recycle the server services** - they are always running and will hot-load all file changes except for `./{AppName}.ps1`. The user manages the server lifecycle. If you encounter any server connectivity issues, prompt the user rather than attempting to start/restart services.
- Since we're using PowerShell, any JavaScript parsed by PowerShell must not use template literals (backtick-based strings). Use traditional string concatenation to avoid syntax errors.
- Ensure you're running in PowerShell 7.x (pwsh.exe) when testing or running shell commands/scripts for optimal performance and compatibility. Examples:

```
    pwsh.exe -Command "./{AppName}.ps1 -Recycle"                        # recycling the application service
    pwsh.exe -Command "./tests/Invoke-Tests.ps1 -TestTypes Unit"        # invoking unit tests
```

## Reference Documentation

ALWAYS refer to the stack reference documentation in the `/devdocs` folder and ensure your code is compliant and follows best practices provided therein.

The `/devdocs` folder is refreshed on build and contains essential reference documentation for the technology stack used for this project. Examples:

- `/devdocs/devguide-pode.md` - Pode development guidelines
- `/devdocs/devguide-htmx.md` - htmx development guidelines
- `/devdocs/devguide-mustache.md` - mustache templating development guidelines

## Code Writing

- You want to use htmx for the request/response cycle, events, and indicators, but keep the backend providing JSON and use client-side templating (via the client-side-templates extension) to render the UI based on that JSON.
  This approach uses htmx as the "conductor" to fetch JSON data and manage interactions, but delegates the actual HTML rendering to a client-side templating engine integrated via the client-side-templates extension.

## Routing Structure

### api routes -> routes/api/[resource]/[method].ps1

    GET /api/status/            ->  `/routes/api/status/get.ps1`
    GET /api/status/details/    ->  `/routes/api/status/get.ps1`
    GET /api/schedule/          ->  `/routes/api/schedule/get.ps1`
    POST /api/schedule/         ->  `/routes/api/schedule/post.ps1`

### web routes -> routes/web/[page].ps1

    GET /                       ->  `/routes/web/index.ps1`
    POST /                      ->  `/routes/web/index.ps1`
    GET /config                 ->  `/routes/web/config.ps1`

## Pre-Commit Process

NEVER initiate this process without explicit instructions to do so!

To ensure all changes are taken into consideration, ensure that you review all files that are pending commit as well as any memory you may have.

1. Bump the version number in the config file (server.psd1).
2. Update the `CHANGELOG.md` file with the new version number and changes, additions, fixed listed properly (create if necessary).
3. Update the `README.md` file with the new version number and any applicable changes to other sections to keep in sync with new features and capabilities (create if necessary).
4. Update the `ROADMAP.md` file with any applicable changes to keep tabs on current and future development progress (create if necessary).
5. Update the `tests\api\Config.Tests.ps1` and `tests\api\Status.Tests.ps1` files (if exists) with the new version number.
6. Update the `{{AppName}}.psd1` file with the new version number.
7. Update FunctionsToExport in `{{AppName}}.psd1` (if necessary).
8. Update `{{AppName}}.db.sql` to be in sync with any schema changes made. This file should be able to reconstruct the database schema from scratch.
9. Generate appropriate commit messages for the changes.
10. Clear the completed and logged tasks.

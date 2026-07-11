# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

### Changed

### Deprecated

### Removed

### Fixed

- Aligned the CRUD handlers, initialization schema, view bindings, and focused Pester coverage on
  the canonical `items` model. Headless GET/POST/PUT/DELETE verification passes against a
  throwaway SQLite database.
- Verified the canonical item CRUD journey through a throwaway Pode server (port 8435, away from
  the user-owned 8433 instance). `/crudmgr` renders the Mustache template with `{{id}}`/`{{item}}`/
  `{{description}}` bindings; `/htmx/crudmgr-new` renders the item/description form posting to
  `/api/crud`; the full GET/POST/PUT/DELETE journey returns canonical data with correct status
  codes.

#### Live verification completed: 2026-07-10

**Feature:** `audit-codebase-analysis-data-model-mismatch`

The canonical item CRUD journey was verified through a throwaway Pode server booted on port 8435
(away from the user-owned 8433 pantry instance, which was left untouched). All four acceptance
criteria passed:

1. `api/debug/init.sql` creates the canonical `items` table with `id, item, description,
created_at, updated_at`.
2. `api/crud/get.ps1`, `post.ps1`, `put.ps1`, and `delete.ps1` read/write only the `items` table
   using `item` and `description` field names; no `feature`, `tag`, `rank`, or `tagFilter` model
   remains in the active CRUD surface.
3. `views/components/crudmgr.pode` renders the Mustache template binding `{{id}}`, `{{item}}`,
   `{{description}}`; `crudmgr-new.pode` renders `name="item"` and `name="description"` form
   controls posting to `/api/crud`.
4. `tests/crud-model.Tests.ps1` initializes a throwaway SQLite database from `init.sql` and
   exercises successful GET, POST, PUT, and DELETE handler paths (Pester: 1 passed, 0 failed).

The PSScriptAnalyzer scan of `api/crud/` reported no warnings or errors.

### Security

#### Resolved model decision: 2026-07-10

**Feature:** `audit-codebase-analysis-sql-injection-tag-query`

**Decision:** Keep the canonical items-only model and permanently remove the legacy tag query and
tag-filter surface.

**Context:** The selected feature requires the tag-list SELECT to remain and bind `tagFilter`
through `-SqlParameters`. The current product specification instead says the CRUD workflow must
use only the canonical `items` model and must not mix in the unrelated feature/tag/rank model. The
uncommitted canonical-model remediation already removes `$tagFilter`, the tag-list SELECT, and the
`tags` response field from `api/crud/get.ps1`.

**Disposition:** `audit-codebase-analysis-sql-injection-tag-query` is stale after the approved model
correction and has been removed from the backlog. Removing the request-derived tag query eliminates
the injection surface instead of preserving an otherwise unsupported tag domain solely to
parameterize it.

**Options considered:**

1. Keep the canonical items-only model and treat removal of the unreachable tag query as the
   security resolution, which requires revising this feature's parameter-binding acceptance
   criterion.
2. Restore the tag model and parameterize the selected-tag query, which conflicts with the current
   product specification and would require an explicit end-to-end model decision.

**Selected:** Option 1. The canonical data-model feature now explicitly verifies that no active
feature, tag, rank, or tagFilter surface remains.

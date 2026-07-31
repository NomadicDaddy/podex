# Database lifecycle tests.
#
# Covers the fresh-checkout database bootstrap (.build.ps1 init contract), the
# POST /init and DELETE /clear debug handlers (idempotency, success/failure
# status codes, accurate log messages, data/ containment), and rejection of a
# configured database path that escapes the data/ directory.

BeforeAll {
	Import-Module -Name PSSQLite -MaximumVersion 1.99.99 -Force

	$script:RepoRoot = (Resolve-Path "$PSScriptRoot/..").Path

	# Shared test state for the debug-handler harness.
	$script:DatabasePath = Join-Path $TestDrive 'podex-test.db'
	$script:Response = $null

	function Get-PodeConfig {
		return @{
			Podex = @{
				DBFile = $script:DatabasePath
				Debug = $true
			}
		}
	}

	function Write-FormattedLog {
		param([string]$Tag, [string]$Log)
		# Record the last message written so tests can assert log accuracy.
		$script:LastLogTag = $Tag
		$script:LastLogMessage = $Log
	}

	function Write-PodeJsonResponse {
		param(
			[Parameter(ValueFromPipeline)]$Value,
			[int]$StatusCode
		)

		process {
			$script:Response = @{
				StatusCode = $StatusCode
				Value = $Value
			}
		}
	}

	# Invoke a debug handler script (init.ps1 or clear.ps1) the same way Pode
	# dot-sources a route file: the file returns a scriptblock that Pode then
	# executes. This mirrors the Invoke-CrudHandler pattern in crud-model tests.
	function Invoke-DebugHandler {
		param([string]$Name)

		$script:Response = $null
		$handlerPath = Join-Path $PSScriptRoot "../api/debug/$Name.ps1"
		$handler = . $handlerPath
		& $handler

		return $script:Response
	}
}

# ---------------------------------------------------------------------------
# POST /init lifecycle
# ---------------------------------------------------------------------------
Describe 'POST /init database lifecycle' {
	BeforeEach {
		# Start each test with no database so idempotent creation is exercised.
		if (Test-Path -LiteralPath $script:DatabasePath) {
			Remove-Item -LiteralPath $script:DatabasePath -Force
		}
	}

	It 'creates and seeds the database when it does not exist' {
		$response = Invoke-DebugHandler -Name 'init'

		$response.StatusCode | Should -Be 200
		$response.Value.message | Should -Be 'Database initialized'

		# The database file now exists and contains the seeded rows.
		$script:DatabasePath | Should -Exist
		$count = (Invoke-SqliteQuery -DataSource $script:DatabasePath -Query 'SELECT COUNT(*) AS [count] FROM [items];' -As SingleValue)
		$count | Should -BeGreaterThan 0
	}

	It 'is idempotent: a second POST /init reseeds without error' {
		$first = Invoke-DebugHandler -Name 'init'
		$first.StatusCode | Should -Be 200

		$countAfterFirst = (Invoke-SqliteQuery -DataSource $script:DatabasePath -Query 'SELECT COUNT(*) AS [count] FROM [items];' -As SingleValue)

		# Insert an extra row so reseed is observable (init.sql drops and recreates).
		Invoke-SqliteQuery -DataSource $script:DatabasePath -Query "INSERT INTO [items] ([item], [description]) VALUES ('Extra', 'Should be removed by reseed');"

		$second = Invoke-DebugHandler -Name 'init'

		$second.StatusCode | Should -Be 200
		$second.Value.message | Should -Be 'Database initialized'

		$countAfterSecond = (Invoke-SqliteQuery -DataSource $script:DatabasePath -Query 'SELECT COUNT(*) AS [count] FROM [items];' -As SingleValue)
		# Reseed restored the original seed count; the extra row is gone.
		$countAfterSecond | Should -Be $countAfterFirst
	}

	It 'logs "initialized" accurately on success' {
		$null = Invoke-DebugHandler -Name 'init'
		$script:LastLogMessage | Should -BeExactly 'Database initialized'
	}

	It 'returns 500 with { message } when the SQL operation fails' {
		# Force a SQLite failure: point the configured path at a corrupt file.
		$corruptDb = Join-Path $TestDrive 'corrupt.db'
		[System.IO.File]::WriteAllBytes($corruptDb, [byte[]](1, 2, 3, 4, 5, 6, 7, 8))

		$savedDb = $script:DatabasePath
		$script:DatabasePath = $corruptDb
		try {
			$response = Invoke-DebugHandler -Name 'init'

			$response.StatusCode | Should -Be 500
			$response.Value.message | Should -Be 'Internal server error'
		} finally {
			$script:DatabasePath = $savedDb
		}
	}
}

# ---------------------------------------------------------------------------
# DELETE /clear lifecycle
# ---------------------------------------------------------------------------
Describe 'DELETE /clear database lifecycle' {
	BeforeEach {
		if (Test-Path -LiteralPath $script:DatabasePath) {
			Remove-Item -LiteralPath $script:DatabasePath -Force
		}
		# Seed with the canonical schema/data for the populated-table path.
		$initSql = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'api/debug/init.sql') -Raw
		Invoke-SqliteQuery -DataSource $script:DatabasePath -Query $initSql
	}

	It 'clears a populated database and returns 200' {
		$countBefore = (Invoke-SqliteQuery -DataSource $script:DatabasePath -Query 'SELECT COUNT(*) AS [count] FROM [items];' -As SingleValue)
		$countBefore | Should -BeGreaterThan 0

		$response = Invoke-DebugHandler -Name 'clear'

		$response.StatusCode | Should -Be 200
		$response.Value.message | Should -Be 'Database cleared'

		# The table still exists but is empty.
		$tableExists = (Invoke-SqliteQuery -DataSource $script:DatabasePath -Query "SELECT name FROM [sqlite_master] WHERE [type]='table' AND [name]='items';" -As SingleValue)
		$tableExists | Should -Be 'items'
		$countAfter = (Invoke-SqliteQuery -DataSource $script:DatabasePath -Query 'SELECT COUNT(*) AS [count] FROM [items];' -As SingleValue)
		$countAfter | Should -Be 0
	}

	It 'is idempotent: returns 200 when the table is already absent' {
		# Drop the table entirely so clear.sql's DROP TABLE IF EXISTS path runs.
		Invoke-SqliteQuery -DataSource $script:DatabasePath -Query 'DROP TABLE [items];'

		$response = Invoke-DebugHandler -Name 'clear'

		$response.StatusCode | Should -Be 200
		$response.Value.message | Should -Be 'Database cleared'

		# The table is recreated by clear.sql and is empty.
		$tableExists = (Invoke-SqliteQuery -DataSource $script:DatabasePath -Query "SELECT name FROM [sqlite_master] WHERE [type]='table' AND [name]='items';" -As SingleValue)
		$tableExists | Should -Be 'items'
		$countAfter = (Invoke-SqliteQuery -DataSource $script:DatabasePath -Query 'SELECT COUNT(*) AS [count] FROM [items];' -As SingleValue)
		$countAfter | Should -Be 0
	}

	It 'is idempotent: returns 200 when the table is already empty' {
		# Empty the table but leave it present.
		Invoke-SqliteQuery -DataSource $script:DatabasePath -Query 'DELETE FROM [items];'

		$response = Invoke-DebugHandler -Name 'clear'

		$response.StatusCode | Should -Be 200
		$response.Value.message | Should -Be 'Database cleared'
	}

	It 'logs "cleared" accurately on success' {
		$null = Invoke-DebugHandler -Name 'clear'
		$script:LastLogMessage | Should -BeExactly 'Database cleared'
	}

	It 'returns 500 with { message } when the SQL operation fails' {
		$corruptDb = Join-Path $TestDrive 'corrupt-clear.db'
		[System.IO.File]::WriteAllBytes($corruptDb, [byte[]](1, 2, 3, 4, 5, 6, 7, 8))

		$savedDb = $script:DatabasePath
		$script:DatabasePath = $corruptDb
		try {
			$response = Invoke-DebugHandler -Name 'clear'

			$response.StatusCode | Should -Be 500
			$response.Value.message | Should -Be 'Internal server error'
		} finally {
			$script:DatabasePath = $savedDb
		}
	}
}

# ---------------------------------------------------------------------------
# Fresh-checkout build bootstrap (.build.ps1 database initialization)
# ---------------------------------------------------------------------------
Describe 'Fresh-checkout build database bootstrap' {
	BeforeAll {
		# The build script is NOT dot-sourced here (it runs the full QC suite).
		# Instead these tests assert the static contract the build must uphold:
		# version requirement, fail-closed error preference, module install
		# floors, LASTEXITCODE checks, and the DBFile containment + auto-init
		# logic. A focused functional test exercises the exact init.sql + data/
		# path resolution the build performs.
		$script:BuildContent = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot '.build.ps1')
	}

	It 'declares #Requires -Version 7.6' {
		$script:BuildContent | Should -Match '#Requires\s+-Version\s+7\.6'
	}

	It 'sets $ErrorActionPreference to Stop' {
		$script:BuildContent | Should -Match '\$ErrorActionPreference\s*=\s*''Stop'''
	}

	It 'installs PSSQLite with the supported version floor' {
		$script:BuildContent | Should -Match 'Install-Module.*PSSQLite.*MinimumVersion\s+1\.1\.0.*MaximumVersion\s+1\.99\.99'
	}

	It 'installs Pode with the supported version floor' {
		$script:BuildContent | Should -Match 'Install-Module.*Pode.*MinimumVersion\s+2\.12\.1.*MaximumVersion\s+2\.99\.99'
	}

	It 'installs modules before invoking either module' {
		# The first Install-Module must precede the first Invoke-SqliteQuery.
		$installPos = $script:BuildContent.IndexOf('Install-Module')
		$invokePos = $script:BuildContent.IndexOf('Invoke-SqliteQuery')
		$installPos | Should -BeLessThan $invokePos
	}

	It 'checks $LASTEXITCODE after bun install --frozen-lockfile' {
		$script:BuildContent | Should -Match 'bun install --frozen-lockfile[\s\S]*?\$LASTEXITCODE'
	}

	It 'checks $LASTEXITCODE after bun run check:licenses' {
		$pattern = 'bun run check:licenses[\s\S]*?\$LASTEXITCODE'
		$script:BuildContent | Should -Match $pattern
	}

	It 'checks $LASTEXITCODE after bun run assets:build' {
		$pattern = 'bun run assets:build[\s\S]*?\$LASTEXITCODE'
		$script:BuildContent | Should -Match $pattern
	}

	It 'checks $LASTEXITCODE after bun run smoke:qc' {
		$pattern = 'bun run smoke:qc[\s\S]*?\$LASTEXITCODE'
		$script:BuildContent | Should -Match $pattern
	}

	It 'does not prompt interactively for database reinitialization' {
		$script:BuildContent | Should -Not -Match 'Read-Host'
	}

	It 'initializes a missing database from api/debug/init.sql' {
		$script:BuildContent | Should -Match 'api/debug/init\.sql'
	}

	It 'creates the data/ directory when it is missing' {
		$script:BuildContent | Should -Match 'New-Item.*Directory.*data'
	}

	It 'resolves DBFile beneath the script root' {
		# The build must read the configured path from server.psd1 and anchor it
		# beneath $PSScriptRoot, not the caller's cwd.
		$script:BuildContent | Should -Match 'Import-PowerShellDataFile.*server\.psd1'
		$script:BuildContent | Should -Match '\$root\s*=\s*\$PSScriptRoot'
	}

	It 'rejects a configured DBFile outside data/' {
		# Containment guard: the build must refuse a path that escapes data/.
		$script:BuildContent | Should -Match 'outside the data'
	}

	It 'does not require a pre-existing database file' {
		# The init branch runs on -not (Test-Path), so a missing file is fine.
		$script:BuildContent | Should -Match 'if\s*\(\s*-not\s*\(Test-Path'
	}
}

# ---------------------------------------------------------------------------
# Functional: build bootstrap initializes a missing database from init.sql
# ---------------------------------------------------------------------------
Describe 'Build bootstrap functional initialization' {
	It 'creates a missing database with the canonical schema and seed data' {
		# Simulate the build's init branch against a clean temp directory.
		$freshDataDir = Join-Path $TestDrive 'fresh-data'
		$freshDb = Join-Path $freshDataDir 'podex.db'

		# data/ does not exist yet (clean checkout).
		$freshDataDir | Should -Not -Exist
		$freshDb | Should -Not -Exist

		$null = New-Item -ItemType Directory -Path $freshDataDir -Force
		$initSql = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'api/debug/init.sql') -Raw
		Invoke-SqliteQuery -DataSource $freshDb -Query $initSql -ErrorAction Stop

		# The database now exists with the canonical items table and seed rows.
		$freshDb | Should -Exist
		$count = (Invoke-SqliteQuery -DataSource $freshDb -Query 'SELECT COUNT(*) AS [count] FROM [items];' -As SingleValue)
		$count | Should -BeGreaterThan 0
	}
}

# ---------------------------------------------------------------------------
# Containment: no database outside data/
# ---------------------------------------------------------------------------
Describe 'Database containment' {
	It 'ensures no SQLite database exists outside data/' {
		$dbFiles = @(Get-ChildItem -LiteralPath $script:RepoRoot -Recurse -File -Filter '*.db' -ErrorAction SilentlyContinue |
				Where-Object {
					$_.DirectoryName -notmatch '[\\/]data$' -and
					$_.FullName -notmatch '[\\/]TestDrive[\\/]' -and
					$_.FullName -notmatch '[\\/]dist[\\/]'
				})
		$dbFiles.Count | Should -Be 0 -Because 'no SQLite database may exist outside data/'
	}
}

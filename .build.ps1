#Requires -Version 7.6
$ErrorActionPreference = 'Stop'

# Script root anchors every relative path so the build is correct regardless of
# the caller's working directory, mirroring the runtime resolution in podex.ps1.
$root = $PSScriptRoot
Set-Location -LiteralPath $root

'# required powershell modules (CurrentUser so no elevation is required)'
Install-Module -Name PSSQLite -Scope CurrentUser -MinimumVersion 1.1.0 -MaximumVersion 1.99.99 -Verbose # MIT
Install-Module -Name Pode -Scope CurrentUser -MinimumVersion 2.14.0 -MaximumVersion 2.99.99 -Verbose # MIT

'# development powershell modules'
Install-Module -Name Pester -Scope CurrentUser -MinimumVersion 6.0.0 -MaximumVersion 6.99.99 -Verbose # Apache 2.0
Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -MinimumVersion 1.23.0 -MaximumVersion 1.99.99 -Verbose # MIT

'# required bun packages'
bun install --frozen-lockfile
if ($LASTEXITCODE -ne 0) {
	throw "bun install --frozen-lockfile failed with exit code $LASTEXITCODE"
}

'# quality checks'
bun run check:licenses
if ($LASTEXITCODE -ne 0) {
	throw "bun run check:licenses failed with exit code $LASTEXITCODE"
}
bun run assets:build
if ($LASTEXITCODE -ne 0) {
	throw "bun run assets:build failed with exit code $LASTEXITCODE"
}
bun run smoke:qc
if ($LASTEXITCODE -ne 0) {
	throw "bun run smoke:qc failed with exit code $LASTEXITCODE"
}

'# initialize database'
# Resolve the configured database beneath the script root's data/ directory,
# create that directory when missing, and initialize a missing database through
# the application's database initializer.
$config = Import-PowerShellDataFile -LiteralPath (Join-Path $root 'server.psd1')
$configDbFile = [string]$config.Podex.DBFile
$dbFile = if ([System.IO.Path]::IsPathRooted($configDbFile)) {
	$configDbFile
} else {
	Join-Path $root $configDbFile
}

# Containment: the database must live under the script-root data/ directory.
# A misconfigured path outside data/ is rejected rather than silently honored.
$dataRoot = Join-Path $root 'data'
$dataRootFull = if (Test-Path -LiteralPath $dataRoot) {
	(Resolve-Path -LiteralPath $dataRoot).Path
} else {
	(New-Item -ItemType Directory -Path $dataRoot -Force).FullName
}
$dbParentFull = (New-Item -ItemType Directory -Path (Split-Path -Parent $dbFile) -Force).FullName
if (-not $dbParentFull.StartsWith($dataRootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
	throw "Configured DBFile '$configDbFile' resolves outside the data/ directory ($dataRootFull). Refusing to initialize."
}
$dbFile = Join-Path $dbParentFull (Split-Path -Leaf $dbFile)

if (-not (Test-Path -LiteralPath $dbFile)) {
	$initSqlPath = Join-Path $root 'api/debug/init.sql'
	$initSql = Get-Content -LiteralPath $initSqlPath -Raw
	Invoke-SqliteQuery -DataSource $dbFile -Query $initSql -ErrorAction Stop
	Write-Output "Initialized database at $dbFile"
} else {
	Write-Output "Database already exists at $dbFile; leaving existing data intact."
}

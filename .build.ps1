'# required powershell modules'
# Install-Module -Name PSSQLite -MinimumVersion 1.1.0 -MaximumVersion 1.99.99 -Verbose # MIT
Install-Module -Name Pode -MinimumVersion 2.11.1 -MaximumVersion 2.99.99 -Verbose # MIT

'# development powershell modules'
Install-Module -Name Pester -MinimumVersion 5.6.1 -MaximumVersion 5.99.99 -Verbose # Apache 2.0
Install-Module -Name PSScriptAnalyzer -MinimumVersion 1.23.0 -MaximumVersion 1.99.99 -Verbose # MIT

'# required bun packages'
bun install --frozen-lockfile

'# quality checks'
bun run check:licenses
bun run assets:build
bun run smoke:qc

'# initialize database'
$db = './data/podex.db'
if (-not (Test-Path -Path './data')) {
	New-Item -ItemType Directory -Path './data' -Force | Out-Null
}
if ((Test-Path -Path $db)) {
	$confirm = Read-Host 'Do you want to reinitialize the database? (y/N)'
	if ($confirm -eq 'y') {
		Invoke-SqliteQuery -DataSource $db -Query (Get-Content -Path './api/debug/init.sql' -Raw) -Verbose
	}
}

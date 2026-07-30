$ErrorActionPreference = 'Stop'

Import-Module -Name 'Pester'

# Snapshot server.psd1 before tests run. The site-metadata tests swap this
# file for an isolated-port config and restore it in AfterAll; this snapshot
# is a safety net so the working tree is never left with a mutated config
# even when Pester's lifecycle cleanup doesn't run (e.g., interrupted process).
$root = Split-Path $PSScriptRoot -Parent
$serverConfig = Join-Path $root 'server.psd1'
$serverSnapshot = if (Test-Path $serverConfig) { Get-Content -Raw -LiteralPath $serverConfig } else { $null }

# Gate on Result, not FailedCount: a test file that throws during discovery produces a failed
# container with zero failed tests, which FailedCount would report as a pass.
$result = Invoke-Pester -Path "$PSScriptRoot/../tests/*.Tests.ps1" -PassThru

# Restore server.psd1 if any test mutated it and left it behind.
if ($null -ne $serverSnapshot -and (Test-Path $serverConfig)) {
	$current = Get-Content -Raw -LiteralPath $serverConfig
	if ($current -cne $serverSnapshot) {
		Set-Content -LiteralPath $serverConfig -Value $serverSnapshot -NoNewline -Force
	}
}

if ($result.Result -ne 'Passed') {
	exit 1
}

exit 0

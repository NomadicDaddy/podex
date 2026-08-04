#Requires -Version 7.6

# Aggregate application quality gate.
#
# Runs every order-independent gate and reports all failures at the end so one
# failed step cannot mask another. Exits 1 if any gate fails and 0 only if all
# pass.
#
# Pass -SkipTests for the fast variant (smoke:qc:fast): runs every gate except
# the Pester test suite, which is the only slow gate (~70s), and check:leak-guard,
# which the pre-commit hook has already covered by the time it calls this. Useful
# for rapid iteration between full test runs.
#
# Gates use the repository's existing scripts and binaries. Caching is omitted because
# the gates complete in seconds.

[CmdletBinding()]
param([switch]$SkipTests)

$ErrorActionPreference = 'Continue'
Write-Output "Don't Panic."

$root = Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $root
$config = Import-PowerShellDataFile -LiteralPath (Join-Path $root 'server.psd1')

$gates = @(
	@{ Name = 'check:leak-guard'; Cmd = { bun run check:leak-guard } },
	@{ Name = 'analyze'; Cmd = { bun run analyze } },
	@{ Name = 'format:pwsh:check'; Cmd = { bun run format:pwsh:check } },
	@{ Name = 'check:typescript-only'; Cmd = { bun run check:typescript-only } },
	@{ Name = 'check-deps'; Cmd = { bun run check-deps } },
	@{ Name = 'check:max-lines'; Cmd = { bun run check:max-lines } },
	@{ Name = 'typecheck'; Cmd = { bun run typecheck } },
	@{ Name = 'lint'; Cmd = { bun run lint } },
	@{ Name = 'test'; Cmd = { bun run test } },
	@{ Name = 'check:licenses'; Cmd = { bun run check:licenses } },
	@{ Name = 'release'; Cmd = { bun run release } },
	@{ Name = 'format:check'; Cmd = { bun run format:check } }
)

if ($SkipTests) {
	# check:leak-guard joins test here, not because it is slow but because the pre-commit hook
	# already ran .githooks/leak-guard.sh directly, ahead of smoke:qc:fast. The self-test verifies
	# that same script against synthetic fixtures; re-running it inside the fast subset would pay
	# for the guard twice on every commit and report nothing the direct call did not.
	$gates = @($gates | Where-Object { $_.Name -notin @('test', 'check:leak-guard') })
}

$failed = @()
foreach ($gate in $gates) {
	Write-Output ""
	Write-Output "=== $($gate.Name) ==="
	Set-Location -LiteralPath $root
	& $gate.Cmd
	$gateExitCode = $LASTEXITCODE
	Set-Location -LiteralPath $root
	if ($gateExitCode -ne 0) {
		$failed += $gate.Name
	}
}

Write-Output ''
if ($failed.Count -gt 0) {
	Write-Output ("{0} gate(s) failed:" -f $failed.Count)
	foreach ($f in $failed) {
		Write-Output "  [FAIL] $f"
	}
	exit 1
}
Write-Output "All $($config.Podex.AppName) smoke:qc gates passed."
exit 0

# Podex smoke:qc - aggregate quality gate.
#
# Runs every order-independent gate and reports all failures at the end so one
# failed step cannot mask another. Exits 1 if any gate fails and 0 only if all
# pass.
#
# Gates use Podex's existing scripts and binaries. Caching is omitted because
# the gates complete in seconds.

$ErrorActionPreference = 'Continue'
Write-Output "Don't Panic."

$root = Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $root

$gates = @(
	@{ Name = 'analyze'; Cmd = { bun run analyze } },
	@{ Name = 'lint'; Cmd = { bun run lint } },
	@{ Name = 'test'; Cmd = { bun run test } },
	@{ Name = 'check:licenses'; Cmd = { bun run check:licenses } },
	@{ Name = 'release'; Cmd = { bun run release } },
	@{ Name = 'format:check'; Cmd = { bun run format:check } },
	@{ Name = 'knip'; Cmd = { bunx knip } }
)

$failed = @()
foreach ($gate in $gates) {
	Write-Output ""
	Write-Output "=== $($gate.Name) ==="
	& $gate.Cmd
	if ($LASTEXITCODE -ne 0) {
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
Write-Output 'All podex smoke:qc gates passed.'
exit 0

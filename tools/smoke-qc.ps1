# Podex smoke:qc - aggregate quality gate.
#
# Mirrors spernakit's smoke:qc semantics: runs every order-independent gate and
# reports ALL failures at the end, so one red step can't mask the others
# (spernakit learned this the hard way when unacknowledged template drift hid
# max-line violations behind a persistently-red earlier gate). Exits 1 if any
# gate fails; 0 only if all pass.
#
# Gates use podex's existing scripts/binaries. Caching is intentionally omitted
# - podex's gates are fast (~seconds), unlike spernakit's heavier pipeline.

$ErrorActionPreference = 'Continue'
Write-Output "Don't Panic."

$root = Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $root

$gates = @(
	@{ Name = 'analyze'; Cmd = { bun run analyze } },
	@{ Name = 'lint'; Cmd = { bun run lint } },
	@{ Name = 'test'; Cmd = { bun run test } },
	@{ Name = 'css'; Cmd = { bun run css } },
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

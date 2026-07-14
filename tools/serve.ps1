# Podex server launcher.
#   bun run dev    -> pwsh ./tools/serve.ps1             (foreground, blocking)
#   bun run start  -> pwsh ./tools/serve.ps1 -Background (detached, non-blocking)
#
# Detached start uses a hidden Start-Process bridge without inheritable handles.
# This lets the launcher exit without leaving an inherited socket bound to the
# server port.
param([switch]$Background)

$root = Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $root
$port = 8433
$scriptPath = Join-Path $root 'podex.ps1'

if ($Background) {
	Start-Process -FilePath 'pwsh' `
		-ArgumentList '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath `
		-WorkingDirectory $root -WindowStyle Hidden

	$ready = $false
	for ($i = 0; $i -lt 60; $i++) {
		if (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue) {
			$ready = $true
			break
		}
		Start-Sleep -Milliseconds 500
	}

	if ($ready) {
		Write-Output "Podex running in background at http://localhost:$port"
		Write-Output "Logs: $root\logs\  |  Stop: bun run stop"
		exit 0
	}
	Write-Error "Podex did not bind port $port within 30s; check $root\logs\."
	exit 1
}

& $scriptPath

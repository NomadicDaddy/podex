#Requires -Version 7.6

# Pode application server launcher.
#   bun run dev    -> pwsh ./tools/serve.ps1             (foreground, blocking)
#   bun run start  -> pwsh ./tools/serve.ps1 -Background (detached, non-blocking)
#
# Background start spawns podex.ps1 detached, records the spawned PID under
# data/ using the configured filename, and polls the HTTP/HTTPS endpoint.
# Uses only cross-platform PowerShell 7 APIs (no Windows-only TCP or window
# cmdlets) so the same script works on Windows, Linux, and macOS.
[CmdletBinding()]
param([switch]$Background)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $root

# Browser assets are generated and ignored, so every supported launch must
# rebuild them before the server can answer requests.
bun run assets:build
if ($LASTEXITCODE -ne 0) {
	throw "bun run assets:build failed with exit code $LASTEXITCODE"
}

# Read the configured endpoint from server.psd1 so serve.ps1 never hardcodes a
# port and stays in sync with PodeCfg.
$configPath = Join-Path $root 'server.psd1'
$config = Import-PowerShellDataFile -LiteralPath $configPath
$port = $config.PodeCfg.HttpPort
$address = $config.PodeCfg.HttpUrl
$https = [bool]$config.PodeCfg.HttpsEnabled
$scheme = if ($https) { 'https' } else { 'http' }
$endpointUrl = "${scheme}://${address}:${port}"

$scriptPath = Join-Path $root 'podex.ps1'

if ($Background) {
	$spawnArgs = @(
		'-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass',
		'-File', $scriptPath
	)

	# Start-Process with -PassThru works cross-platform. The Windows-only
	# window-style parameter is omitted; on headless Linux/macOS it is ignored.
	$process = Start-Process -FilePath 'pwsh' `
		-ArgumentList $spawnArgs `
		-WorkingDirectory $root `
		-PassThru

	# Record the spawned PID so stop.ps1 can target this exact process instead
	# of guessing by port ownership.
	$dataDir = Join-Path $root 'data'
	if (-not (Test-Path -LiteralPath $dataDir)) {
		New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
	}
	$pidFile = Join-Path $dataDir $config.Podex.PidFile
	Set-Content -LiteralPath $pidFile -Value $process.Id -NoNewline -Force

	# Poll the configured HTTP/HTTPS endpoint for readiness (up to ~30s). This
	# works on every platform because it checks the actual served response, not
	# a Windows-specific TCP table.
	$ready = $false
	for ($i = 0; $i -lt 60; $i++) {
		if ($process.HasExited) { break }
		try {
			$null = Invoke-WebRequest -Uri $endpointUrl -UseBasicParsing -TimeoutSec 2 `
				-SkipCertificateCheck:$https
			$ready = $true
			break
		} catch {
			Start-Sleep -Milliseconds 500
		}
	}

	if ($ready) {
		Write-Output "$($config.Podex.AppName) running in background at $endpointUrl"
		Write-Output "Logs: $root/logs/  |  Stop: bun run stop"
		exit 0
	}
	Write-Error "$($config.Podex.AppName) did not answer $endpointUrl within 30s; check $root/logs/."
	exit 1
}

& $scriptPath

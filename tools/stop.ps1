#Requires -Version 7.6

# Stop the Podex server: graceful-first, then PID kill, then port fallback.
#
# Reads the configured endpoint from server.psd1, requests graceful shutdown
# via POST /stop with the X-Podex-Debug: true header when the application
# exposes that endpoint, waits for the configured PID under data/, and
# force-stops only that PID if graceful shutdown does not release in time.
# When no PID is recorded (e.g. the server was started in the foreground via
# `bun run dev`, which writes no PID file), falls back to the OS-native
# process owning the configured port. Uses no Windows-specific TCP cmdlets so
# the same script runs on Windows, Linux, and macOS.

[CmdletBinding()]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $root

# Read the configured endpoint and debug flag from server.psd1.
$configPath = Join-Path $root 'server.psd1'
$config = Import-PowerShellDataFile -LiteralPath $configPath
$port = $config.PodeCfg.HttpPort
$address = $config.PodeCfg.HttpUrl
$https = [bool]$config.PodeCfg.HttpsEnabled
$scheme = if ($https) { 'https' } else { 'http' }
$endpointUrl = "${scheme}://${address}:${port}"

$pidFile = Join-Path $root "data/$($config.Podex.PidFile)"
$recordedPid = $null
if (Test-Path -LiteralPath $pidFile) {
	$recordedPid = (Get-Content -LiteralPath $pidFile -Raw).Trim()
}

# Resolve the OS-native PID owning the configured listening port. Uses
# external commands (netstat on Windows, lsof on Unix) rather than any
# Windows-only network cmdlet so the same logic is cross-platform. Returns
# $null when nothing is listening on the port.
function Get-PodexPortOwnerPid {
	param([Parameter(Mandatory)][int]$Port)
	if ($IsWindows) {
		foreach ($line in (netstat -ano 2>$null)) {
			$cols = @($line -split '\s+' | Where-Object { $_ })
			if ($cols.Count -ge 5 -and
				$cols[1] -like "*:$Port" -and
				$cols[3] -eq 'LISTENING' -and
				$cols[4] -match '^\d+$' -and $cols[4] -ne '0') {
				return [int]$cols[4]
			}
		}
	} else {
		$owner = (lsof -t -i ":$Port" -sTCP:LISTEN 2>$null | Select-Object -First 1)
		if ($owner -and $owner -match '^\d+$') {
			return [int]$owner
		}
	}
	return $null
}

# 1. Graceful: ask Pode to close its own listener via POST /stop when that
#    route is available. The X-Podex-Debug header satisfies Podex's guard.
$graceful = $false
try {
	$headers = @{ 'X-Podex-Debug' = 'true' }
	$resp = Invoke-WebRequest -Uri "$endpointUrl/stop" -Method Post -Headers $headers `
		-UseBasicParsing -SkipHttpErrorCheck -TimeoutSec 3 `
		-SkipCertificateCheck:$https
	if ($resp.StatusCode -lt 300) {
		$graceful = $true
	}
} catch {
	$graceful = $false   # listener absent or /stop unregistered; escalate to PID kill
}

# 2. Wait for the recorded PID to exit (up to ~5s), then force-stop only that
#    PID if it is still alive. This avoids killing an arbitrary process that
#    happens to own the port.
$stopped = $false
if ($recordedPid) {
	for ($i = 0; $i -lt 10; $i++) {
		$alive = Get-Process -Id ([int]$recordedPid) -ErrorAction SilentlyContinue
		if (-not $alive) {
			$stopped = $true
			break
		}
		Start-Sleep -Milliseconds 500
	}
	if (-not $stopped) {
		Stop-Process -Id ([int]$recordedPid) -Force -ErrorAction SilentlyContinue
		Start-Sleep -Milliseconds 500
		$stillAlive = Get-Process -Id ([int]$recordedPid) -ErrorAction SilentlyContinue
		$stopped = -not $stillAlive
	}
}

# 3. Port fallback: if no PID was recorded (the server was started in the
#    foreground via `bun run dev`, which writes no PID file) or the recorded
#    PID could not be stopped, locate the process owning the configured port
#    and stop it. This is the path that frees a port held by a foreground
#    server so a subsequent `bun run dev` does not collide on the same port.
if (-not $stopped) {
	$portPid = Get-PodexPortOwnerPid -Port $port
	if ($portPid) {
		Stop-Process -Id $portPid -Force -ErrorAction SilentlyContinue
		Start-Sleep -Milliseconds 500
		$stillAlive = Get-Process -Id $portPid -ErrorAction SilentlyContinue
		$stopped = -not $stillAlive
	}
}

# Clean up the PID file regardless of outcome.
if (Test-Path -LiteralPath $pidFile) {
	Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
}

if ($stopped -or $graceful) {
	Write-Output "$($config.Podex.AppName) stopped."
} else {
	# Confirm nothing is still listening on the configured port so the
	# message reflects reality rather than an assumption.
	$owner = Get-PodexPortOwnerPid -Port $port
	if ($owner) {
		Write-Output "$($config.Podex.AppName) could not be stopped (process $owner still owns port $port)."
	} else {
		Write-Output "$($config.Podex.AppName) not running (no recorded PID, no graceful endpoint, port is free)."
	}
}

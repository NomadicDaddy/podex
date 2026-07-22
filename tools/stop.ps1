# Stop the Podex server: graceful-first, then PID kill.
#
# Reads the configured endpoint from server.psd1, requests graceful shutdown
# via POST /stop with the X-Podex-Debug: true header (registered when
# Podex.Debug is on), waits for the recorded PID under data/podex.pid, and
# force-stops only that PID if graceful shutdown does not release in time.
# Uses no Windows-specific TCP cmdlets so the same script runs on Windows,
# Linux, and macOS.

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

$pidFile = Join-Path $root 'data/podex.pid'
$recordedPid = $null
if (Test-Path -LiteralPath $pidFile) {
	$recordedPid = (Get-Content -LiteralPath $pidFile -Raw).Trim()
}

# 1. Graceful: ask Pode to close its own listener via POST /stop (registered
#    when Podex.Debug is on). The X-Podex-Debug header satisfies the debug
#    middleware guard.
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

# Clean up the PID file regardless of outcome.
if (Test-Path -LiteralPath $pidFile) {
	Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
}

if ($stopped -or $graceful) {
	Write-Output 'Podex stopped.'
} else {
	Write-Output 'Podex not running (no recorded PID and no graceful endpoint).'
}

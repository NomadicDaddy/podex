# Stop the Podex server: graceful-first, then port-kill.
#
# Prefers Pode's own Close-PodeServer via the loopback /stop route (clean socket
# release) and only escalates to force-killing the port listener if graceful
# shutdown is unavailable or doesn't release in time. This prevents an orphaned
# Windows socket from keeping the port bound.
$port = 8433

# 1. Graceful: ask Pode to close its own listener (registered when Podex.Debug is on).
$graceful = $false
try {
	$resp = Invoke-WebRequest -Uri "http://localhost:$port/stop" -Method Post -UseBasicParsing -SkipHttpErrorCheck -TimeoutSec 3
	if ($resp.StatusCode -lt 300) {
		$graceful = $true
	}
} catch {
	$graceful = $false   # listener absent or /stop unregistered; escalate to port-kill
}
if ($graceful) {
	Start-Sleep -Milliseconds 800
}

# 2. Verify release; escalate to force-killing the port listener if still bound.
$procs = @(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue |
	Select-Object -ExpandProperty OwningProcess -Unique)

if ($procs.Count -gt 0) {
	$procs | ForEach-Object { Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue }
	Write-Output "Podex stopped (port $port listener killed)."
} elseif ($graceful) {
	Write-Output "Podex stopped (graceful)."
} else {
	Write-Output "Podex not running."
}

#Requires -Version 7.6

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

function Start-PodexLogSession {
	<#
	.SYNOPSIS
	Starts a fresh Podex logging session.

	.DESCRIPTION
	Moves root log files into one timestamped archive directory so Pode opens
	new request and error logs for the current server process.

	.PARAMETER Path
	The directory containing Podex log files.
	#>
	[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
	[OutputType([System.IO.DirectoryInfo])]
	param(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$Path
	)

	$logPath = [System.IO.Path]::GetFullPath($Path)
	if (-not (Test-Path -LiteralPath $logPath)) {
		if ($PSCmdlet.ShouldProcess($logPath, 'Create log directory')) {
			New-Item -ItemType Directory -Path $logPath -Force | Out-Null
		} else {
			return
		}
	}

	$logFiles = @(Get-ChildItem -LiteralPath $logPath -Filter '*.log' -File)
	if ($logFiles.Count -eq 0) {
		return
	}

	$archiveRoot = Join-Path $logPath 'archive'
	New-Item -ItemType Directory -Path $archiveRoot -Force | Out-Null

	$archiveName = [DateTimeOffset]::UtcNow.ToString('yyyyMMddTHHmmss.fffZ')
	$archivePath = Join-Path $archiveRoot $archiveName
	$suffix = 0
	while (Test-Path -LiteralPath $archivePath) {
		$suffix++
		$archivePath = Join-Path $archiveRoot ('{0}-{1:D3}' -f $archiveName, $suffix)
	}
	if (-not $PSCmdlet.ShouldProcess(
			$archivePath,
			"Archive $($logFiles.Count) log file(s)"
		)) {
		return
	}
	New-Item -ItemType Directory -Path $archivePath | Out-Null

	foreach ($logFile in $logFiles) {
		Move-Item -LiteralPath $logFile.FullName -Destination $archivePath
	}

	return Get-Item -LiteralPath $archivePath
}

Export-ModuleMember -Function Start-PodexLogSession

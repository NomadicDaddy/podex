#Requires -Version 7.6
# PowerShell format consistency gate.
#
# Runs PSScriptAnalyzer's Invoke-Formatter with the project formatting settings
# (PSScriptAnalyzerSettings.psd1) over the same recursive .ps1/.psm1/.psd1 source
# set that tools/analyze.ps1 covers, excluding generated and runtime directories.
# Exits 1 when any file's formatted text differs from its current content.

[CmdletBinding()]
param(
	[Parameter()]
	[ValidateNotNullOrEmpty()]
	[string]$Path = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

try {
	Import-Module -Name PSScriptAnalyzer -ErrorAction Stop
	$settingsPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'PSScriptAnalyzerSettings.psd1'
	if (-not (Test-Path -LiteralPath $settingsPath -PathType Leaf)) {
		Write-Output "Formatting settings not found: $settingsPath"
		exit 1
	}
	$resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
	$excludedDirectoryPattern = '[\\/](?:\.git|data|dist|logs|node_modules|public)[\\/]'
	$sourceFiles = @(
		Get-ChildItem -LiteralPath $resolvedPath -Recurse -File -ErrorAction Stop |
			Where-Object {
				$_.Extension -in @('.ps1', '.psd1', '.psm1') -and
				$_.FullName -notmatch $excludedDirectoryPattern
			}
	)
	$drift = @()
	foreach ($file in $sourceFiles) {
		$raw = Get-Content -Raw -LiteralPath $file.FullName
		$formatted = Invoke-Formatter -ScriptDefinition $raw -Settings $settingsPath
		if ($raw -cne $formatted) {
			$drift += $file.FullName.Substring($resolvedPath.Length)
		}
	}
} catch {
	Write-Output "PowerShell format check failed: $($_.Exception.Message)"
	exit 1
}

if ($drift.Count -gt 0) {
	Write-Output ("PowerShell format drift in {0} file(s):" -f $drift.Count)
	foreach ($d in $drift) {
		Write-Output "  $d"
	}
	Write-Output 'Run Invoke-Formatter with PSScriptAnalyzerSettings.psd1 to normalize.'
	exit 1
}

Write-Output ("PowerShell format check passed for {0} source file(s)." -f $sourceFiles.Count)
exit 0

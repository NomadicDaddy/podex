#Requires -Version 7.0

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
	$resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
	$excludedDirectoryPattern = '[\\/](?:\.git|dist|node_modules)[\\/]'
	$sourceFiles = @(
		Get-ChildItem -LiteralPath $resolvedPath -Recurse -File -ErrorAction Stop |
			Where-Object {
				$_.Extension -in @('.ps1', '.psd1', '.psm1') -and
				$_.FullName -notmatch $excludedDirectoryPattern
			}
	)
	$diagnostics = @(
		$sourceFiles | ForEach-Object {
			Invoke-ScriptAnalyzer -Path $_.FullName -ErrorAction Stop
		}
	)
} catch {
	Write-Output "PSScriptAnalyzer failed: $($_.Exception.Message)"
	exit 1
}

if ($diagnostics.Count -gt 0) {
	$diagnostics | Write-Output
	Write-Output ("PSScriptAnalyzer found {0} diagnostic(s)." -f $diagnostics.Count)
	exit 1
}

Write-Output ("PSScriptAnalyzer found no diagnostics in {0} source file(s)." -f $sourceFiles.Count)
exit 0

# Regression gate for the PowerShell format consistency checker
# (tools/format-check.ps1).
#
# The format checker runs PSScriptAnalyzer's Invoke-Formatter with the project
# formatting settings over the recursive .ps1/.psm1/.psd1 source set and exits
# non-zero when any file drifts. These tests prove the checker passes for the
# real source tree and fails closed for a misformatted fixture.

BeforeAll {
	$script:FormatScript = Join-Path $PSScriptRoot '../tools/format-check.ps1'
	$script:SettingsPath = Join-Path $PSScriptRoot '../PSScriptAnalyzerSettings.psd1'

	# Helper that writes a known-conformant fixture by formatting a sample
	# through Invoke-Formatter with the project settings, so the clean case
	# cannot be tripped by here-string line-ending differences. Defined as a
	# scriptblock (not a function) to avoid the PSUseShouldProcess warning on
	# the New verb inside a test file.
	$script:WriteFormattedFixture = {
		param([string]$Directory, [string]$FileName, [string]$ScriptText)
		Import-Module PSScriptAnalyzer
		$formatted = Invoke-Formatter -ScriptDefinition $ScriptText -Settings $script:SettingsPath
		New-Item -ItemType Directory -Path $Directory -Force | Out-Null
		# Use [System.IO.File]::WriteAllText to avoid Set-Content's platform
		# line-ending conversion, which would introduce mixed endings and trip
		# Invoke-Formatter's mixed-ending guard.
		[System.IO.File]::WriteAllText((Join-Path $Directory $FileName), $formatted, [System.Text.UTF8Encoding]::new($false))
	}
}

Describe 'PowerShell format consistency checker' {
	It 'exits 0 for the project source tree' {
		$output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $script:FormatScript 2>&1
		$exitCode = $LASTEXITCODE

		if ($exitCode -ne 0) {
			$output | Out-String | Write-Output
		}
		$exitCode | Should -Be 0
		$output | Out-String | Should -Match 'format check passed'
	}

	It 'exits 1 when a fixture file is misformatted' {
		$fixtureRoot = Join-Path $TestDrive 'drift'
		New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
		# Misformatted: missing space after the open brace and around the operator,
		# which the consistent-whitespace rule will normalize.
		Set-Content -LiteralPath (Join-Path $fixtureRoot 'drift.ps1') -Value "function Get-Foo{if(`$x-eq1){Write-Output 'hi'}}"

		$output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $script:FormatScript -Path $fixtureRoot 2>&1
		$exitCode = $LASTEXITCODE

		$exitCode | Should -Be 1
		$output | Out-String | Should -Match 'format drift'
	}

	It 'exits 0 for an already-formatted fixture' {
		$fixtureRoot = Join-Path $TestDrive 'clean'
		& $script:WriteFormattedFixture $fixtureRoot 'clean.ps1' @'
function Get-Foo {
	param([string]$Name)
	if ($Name -eq 'x') {
		Write-Output "hi"
	}
}
'@

		$output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $script:FormatScript -Path $fixtureRoot 2>&1
		$exitCode = $LASTEXITCODE

		if ($exitCode -ne 0) {
			$output | Out-String | Write-Output
		}
		$exitCode | Should -Be 0
		$output | Out-String | Should -Match 'format check passed'
	}
}

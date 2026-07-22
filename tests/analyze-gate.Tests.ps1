BeforeAll {
	$script:AnalyzeScript = Join-Path $PSScriptRoot '../tools/analyze.ps1'
}

Describe 'PowerShell analyzer gate' {
	It 'passes clean recursive analysis and excludes generated directories' {
		$fixtureRoot = Join-Path $TestDrive 'clean'
		$nestedRoot = Join-Path $fixtureRoot 'nested'
		$generatedRoot = Join-Path $fixtureRoot 'dist'
		New-Item -ItemType Directory -Path $nestedRoot | Out-Null
		New-Item -ItemType Directory -Path $generatedRoot | Out-Null
		Set-Content -LiteralPath (Join-Path $nestedRoot 'clean.ps1') -Value "Write-Output 'clean'"
		Set-Content -LiteralPath (Join-Path $generatedRoot 'ignored.ps1') -Value 'function InvalidVerb-Fixture { }'

		$output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $script:AnalyzeScript -Path $fixtureRoot 2>&1
		$exitCode = $LASTEXITCODE

		$exitCode | Should -Be 0
		$output | Out-String | Should -Match 'found no diagnostics'
	}

	It 'fails when a nested script contains an analyzer diagnostic' {
		$fixtureRoot = Join-Path $TestDrive 'diagnostic'
		$nestedRoot = Join-Path $fixtureRoot 'nested'
		New-Item -ItemType Directory -Path $nestedRoot | Out-Null
		Set-Content -LiteralPath (Join-Path $nestedRoot 'warning.ps1') -Value 'function InvalidVerb-Fixture { }'

		$output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $script:AnalyzeScript -Path $fixtureRoot 2>&1
		$exitCode = $LASTEXITCODE

		$exitCode | Should -Be 1
		$output | Out-String | Should -Match 'PSUseApprovedVerbs'
	}

	It 'fails closed when the requested path does not exist' {
		$missingPath = Join-Path $TestDrive 'missing'

		$output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $script:AnalyzeScript -Path $missingPath 2>&1
		$exitCode = $LASTEXITCODE

		$exitCode | Should -Be 1
		$output | Out-String | Should -Match 'PSScriptAnalyzer failed'
	}
}

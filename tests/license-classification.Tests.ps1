BeforeAll {
	$script:RepoRoot = (Resolve-Path "$PSScriptRoot/..").Path
	$script:HarnessPath = Join-Path $PSScriptRoot 'license-classification-harness.ts'
	$script:GenerateScript = Join-Path $script:RepoRoot 'scripts/generate-third-party-licenses.ts'
}

Describe 'License inventory restrictive classification' {
	It 'classifies restrictive, source-available, and non-commercial licenses as RESTRICTIVE' {
		$output = bun $script:HarnessPath 2>&1
		$exitCode = $LASTEXITCODE
		$output | Should -Match 'All license classification assertions passed'
		$exitCode | Should -Be 0
	}

	It 'runs the license gate against the locked dependency graph' {
		# The current locked dependency graph must have zero restrictive packages,
		# so the license check must pass cleanly. This confirms the gate is active.
		Push-Location $script:RepoRoot
		try {
			$output = bun $script:GenerateScript --check 2>&1 | Out-String
			$exitCode = $LASTEXITCODE
		} finally {
			Pop-Location
		}
		$output | Should -Match 'match the installed packages and release assets'
		$exitCode | Should -Be 0
	}
}

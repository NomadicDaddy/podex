BeforeAll {
	$script:RepoRoot = (Resolve-Path "$PSScriptRoot/..").Path

	$script:PackageManifest = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot 'package.json') | ConvertFrom-Json
	$script:Version = $script:PackageManifest.version
	$script:ArchivePath = Join-Path $script:RepoRoot "dist/podex-$($script:Version).zip"
}

Describe 'Release archive artifact' {
	BeforeAll {
		# Produce a fresh staging tree and archive before running the assertions.
		Push-Location -LiteralPath $script:RepoRoot
		try {
			bun run release:package 2>&1 | Out-Null
		} finally {
			Pop-Location
		}
	}

	AfterAll {
		# Clean up the archive and staging tree so the working tree stays tidy.
		# The dist/ directory is git-ignored so this is belt-and-suspenders.
	}

	It 'produces dist/podex-<version>.zip after release:package' {
		$script:ArchivePath | Should -Exist
	}

	It 'verifies the extracted archive contents with release:check' {
		Push-Location -LiteralPath $script:RepoRoot
		try {
			bun run release:check 2>&1 | Out-Null
			$LASTEXITCODE | Should -Be 0
		} finally {
			Pop-Location
		}
	}

	It 'fails closed when the archive is missing' {
		# Remove the archive so release:check has nothing to verify.
		Remove-Item -LiteralPath $script:ArchivePath -Force -ErrorAction SilentlyContinue

		Push-Location -LiteralPath $script:RepoRoot
		try {
			bun run release:check 2>&1 | Out-Null
			$LASTEXITCODE | Should -Not -Be 0
		} finally {
			Pop-Location
		}
	}
}

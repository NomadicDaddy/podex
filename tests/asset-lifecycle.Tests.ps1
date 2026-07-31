BeforeAll {
	$script:RepoRoot = (Resolve-Path "$PSScriptRoot/..").Path
	$script:StaleAsset = Join-Path $script:RepoRoot 'public/js/htmx.min.js'
}

Describe 'Generated browser asset lifecycle' {
	It 'removes stale generated assets before rebuilding' {
		$staleDirectory = Split-Path -Parent $script:StaleAsset
		New-Item -ItemType Directory -Path $staleDirectory -Force | Out-Null
		Set-Content -LiteralPath $script:StaleAsset -Value 'stale generated asset'

		Push-Location -LiteralPath $script:RepoRoot
		try {
			bun run assets:build 2>&1 | Out-Null
			$LASTEXITCODE | Should -Be 0
		} finally {
			Pop-Location
		}

		$script:StaleAsset | Should -Not -Exist
		Join-Path $script:RepoRoot 'public/css/podex.css' | Should -Exist
		Get-Content -LiteralPath (Join-Path $script:RepoRoot 'public/css/podex.css') -Raw |
			Should -Match '\.site-header'
	}
}

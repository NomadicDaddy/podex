BeforeAll {
	Import-Module -Name "$PSScriptRoot/../tools/PodexRoute.psm1" -Force
}

Describe 'Debug route registration isolation' {
	BeforeAll {
		$script:RepoRoot = (Resolve-Path "$PSScriptRoot/..").Path
	}

	It 'excludes all debug routes when Debug is disabled' {
		$debugFiles = @(
			Join-Path $script:RepoRoot 'api/debug/stop.ps1'
			Join-Path $script:RepoRoot 'api/debug/clear.ps1'
			Join-Path $script:RepoRoot 'api/debug/init.ps1'
		)

		foreach ($file in $debugFiles) {
			$result = Resolve-PodexApiRoute -FilePath $file -BaseDirectory $script:RepoRoot -DebugEnabled $false
			$result.Skip | Should -Be $true
			$result.Path | Should -BeNullOrEmpty
		}
	}

	It 'registers debug routes at short paths with correct methods when Debug is enabled' {
		$result = Resolve-PodexApiRoute -FilePath (Join-Path $script:RepoRoot 'api/debug/stop.ps1') -BaseDirectory $script:RepoRoot -DebugEnabled $true
		$result.Skip | Should -Be $false
		$result.Path | Should -Be '/stop'
		$result.Method | Should -Be 'Post'

		$result = Resolve-PodexApiRoute -FilePath (Join-Path $script:RepoRoot 'api/debug/init.ps1') -BaseDirectory $script:RepoRoot -DebugEnabled $true
		$result.Skip | Should -Be $false
		$result.Path | Should -Be '/init'
		$result.Method | Should -Be 'Post'

		$result = Resolve-PodexApiRoute -FilePath (Join-Path $script:RepoRoot 'api/debug/clear.ps1') -BaseDirectory $script:RepoRoot -DebugEnabled $true
		$result.Skip | Should -Be $false
		$result.Path | Should -Be '/clear'
		$result.Method | Should -Be 'Delete'
	}

	It 'never exposes debug routes as GET regardless of Debug flag' {
		$debugFiles = @(
			Join-Path $script:RepoRoot 'api/debug/stop.ps1'
			Join-Path $script:RepoRoot 'api/debug/clear.ps1'
			Join-Path $script:RepoRoot 'api/debug/init.ps1'
		)

		foreach ($enabled in @($true, $false)) {
			foreach ($file in $debugFiles) {
				$result = Resolve-PodexApiRoute -FilePath $file -BaseDirectory $script:RepoRoot -DebugEnabled $enabled
				if (-not $result.Skip) {
					$result.Method | Should -Not -Be 'Get' -Because 'debug routes must never be GET (no drive-by state changes)'
				}
			}
		}
	}

	It 'never exposes debug routes under /api/debug/ regardless of Debug flag' {
		$debugFiles = @(
			Join-Path $script:RepoRoot 'api/debug/stop.ps1'
			Join-Path $script:RepoRoot 'api/debug/clear.ps1'
			Join-Path $script:RepoRoot 'api/debug/init.ps1'
		)

		foreach ($enabled in @($true, $false)) {
			foreach ($file in $debugFiles) {
				$result = Resolve-PodexApiRoute -FilePath $file -BaseDirectory $script:RepoRoot -DebugEnabled $enabled
				if (-not $result.Skip) {
					$result.Path | Should -Not -BeLike '/api/debug/*'
				}
			}
		}
	}

	It 'registers CRUD routes correctly regardless of Debug flag' {
		foreach ($enabled in @($true, $false)) {
			$result = Resolve-PodexApiRoute -FilePath (Join-Path $script:RepoRoot 'api/crud/get.ps1') -BaseDirectory $script:RepoRoot -DebugEnabled $enabled
			$result.Skip | Should -Be $false
			$result.Path | Should -Be '/api/crud'
			$result.Method | Should -Be 'Get'

			$result = Resolve-PodexApiRoute -FilePath (Join-Path $script:RepoRoot 'api/crud/post.ps1') -BaseDirectory $script:RepoRoot -DebugEnabled $enabled
			$result.Skip | Should -Be $false
			$result.Path | Should -Be '/api/crud'
			$result.Method | Should -Be 'Post'

			$result = Resolve-PodexApiRoute -FilePath (Join-Path $script:RepoRoot 'api/crud/put.ps1') -BaseDirectory $script:RepoRoot -DebugEnabled $enabled
			$result.Skip | Should -Be $false
			$result.Path | Should -Be '/api/crud'
			$result.Method | Should -Be 'Put'

			$result = Resolve-PodexApiRoute -FilePath (Join-Path $script:RepoRoot 'api/crud/delete.ps1') -BaseDirectory $script:RepoRoot -DebugEnabled $enabled
			$result.Skip | Should -Be $false
			$result.Path | Should -Be '/api/crud'
			$result.Method | Should -Be 'Delete'
		}
	}

	It 'strips only a terminal verb segment, not a verb appearing mid-path' {
		# A resource path like api/post/get.ps1 should map to GET /api/post, not
		# GET /api (the get segment is terminal; post appears mid-path and must
		# survive).
		$tempDir = Join-Path $TestDrive 'apiverb'
		$subDir = Join-Path $tempDir 'api/post'
		New-Item -ItemType Directory -Path $subDir -Force | Out-Null
		$verbFile = Join-Path $subDir 'get.ps1'
		Set-Content -LiteralPath $verbFile -Value '{ }'
		$result = Resolve-PodexApiRoute -FilePath $verbFile -BaseDirectory $tempDir -DebugEnabled $false
		$result.Path | Should -Be '/api/post'
		$result.Method | Should -Be 'Get'
	}
}

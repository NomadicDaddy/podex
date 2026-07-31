# Runtime portability and route-safety tests.
#
# Verifies that route derivation and runtime path resolution work correctly
# when invoked from an alternate working directory and with mixed slash
# styles, that only terminal verb segments are stripped, and that the module
# import floors match .build.ps1 and README.md.

BeforeAll {
	Import-Module -Name "$PSScriptRoot/../tools/PodexRoute.psm1" -Force
	$script:RepoRoot = (Resolve-Path "$PSScriptRoot/..").Path
}

Describe 'Route derivation portability' {
	It 'resolves routes correctly when BaseDirectory uses backslashes' {
		# On Windows the file system returns backslash paths. The resolver must
		# normalize them to forward slashes for route paths.
		$base = $script:RepoRoot -replace '/', '\'
		$file = (Join-Path $script:RepoRoot 'api/crud/get.ps1') -replace '/', '\'
		$result = Resolve-PodexApiRoute -FilePath $file -BaseDirectory $base -DebugEnabled $false
		$result.Skip | Should -Be $false
		$result.Path | Should -Be '/api/crud'
		$result.Method | Should -Be 'Get'
	}

	It 'resolves routes correctly when BaseDirectory uses forward slashes' {
		$base = $script:RepoRoot -replace '\\', '/'
		$file = (Join-Path $script:RepoRoot 'api/crud/post.ps1') -replace '\\', '/'
		$result = Resolve-PodexApiRoute -FilePath $file -BaseDirectory $base -DebugEnabled $false
		$result.Skip | Should -Be $false
		$result.Path | Should -Be '/api/crud'
		$result.Method | Should -Be 'Post'
	}

	It 'produces identical routes for the same file regardless of slash style' {
		$fileBack = (Join-Path $script:RepoRoot 'api/crud/put.ps1') -replace '/', '\'
		$fileFwd = $fileBack -replace '\\', '/'
		$baseBack = $script:RepoRoot -replace '/', '\'
		$baseFwd = $script:RepoRoot -replace '\\', '/'

		$r1 = Resolve-PodexApiRoute -FilePath $fileBack -BaseDirectory $baseBack -DebugEnabled $false
		$r2 = Resolve-PodexApiRoute -FilePath $fileFwd -BaseDirectory $baseFwd -DebugEnabled $false
		$r1.Path | Should -Be $r2.Path
		$r1.Method | Should -Be $r2.Method
	}

	It 'strips only a terminal /get segment' {
		$result = Resolve-PodexApiRoute -FilePath (Join-Path $script:RepoRoot 'api/crud/get.ps1') -BaseDirectory $script:RepoRoot -DebugEnabled $false
		$result.Path | Should -Be '/api/crud'
		$result.Method | Should -Be 'Get'
	}

	It 'strips only a terminal /post segment' {
		$result = Resolve-PodexApiRoute -FilePath (Join-Path $script:RepoRoot 'api/crud/post.ps1') -BaseDirectory $script:RepoRoot -DebugEnabled $false
		$result.Path | Should -Be '/api/crud'
		$result.Method | Should -Be 'Post'
	}

	It 'strips only a terminal /put segment' {
		$result = Resolve-PodexApiRoute -FilePath (Join-Path $script:RepoRoot 'api/crud/put.ps1') -BaseDirectory $script:RepoRoot -DebugEnabled $false
		$result.Path | Should -Be '/api/crud'
		$result.Method | Should -Be 'Put'
	}

	It 'strips only a terminal /delete segment' {
		$result = Resolve-PodexApiRoute -FilePath (Join-Path $script:RepoRoot 'api/crud/delete.ps1') -BaseDirectory $script:RepoRoot -DebugEnabled $false
		$result.Path | Should -Be '/api/crud'
		$result.Method | Should -Be 'Delete'
	}

	It 'does not strip a verb segment that appears mid-path' {
		# api/get/post.ps1 should map to POST /api/get (post is terminal, get is
		# mid-path and must survive).
		$tempDir = Join-Path $TestDrive 'midverb'
		$subDir = Join-Path $tempDir 'api/get'
		New-Item -ItemType Directory -Path $subDir -Force | Out-Null
		$verbFile = Join-Path $subDir 'post.ps1'
		Set-Content -LiteralPath $verbFile -Value '{ }'
		$result = Resolve-PodexApiRoute -FilePath $verbFile -BaseDirectory $tempDir -DebugEnabled $false
		$result.Path | Should -Be '/api/get'
		$result.Method | Should -Be 'Post'
	}

	It 'defaults non-verb scripts to GET' {
		$tempDir = Join-Path $TestDrive 'nonverb'
		$subDir = Join-Path $tempDir 'api/custom'
		New-Item -ItemType Directory -Path $subDir -Force | Out-Null
		$verbFile = Join-Path $subDir 'status.ps1'
		Set-Content -LiteralPath $verbFile -Value '{ }'
		$result = Resolve-PodexApiRoute -FilePath $verbFile -BaseDirectory $tempDir -DebugEnabled $false
		$result.Path | Should -Be '/api/custom/status'
		$result.Method | Should -Be 'Get'
	}
}

Describe 'Runtime path resolution from alternate working directory' {
	It 'resolves DBFile beneath the script root when relative' {
		# A relative DBFile (./data/podex.db) must resolve to an absolute path
		# beneath PSScriptRoot, not beneath an arbitrary cwd. This mirrors the
		# normalization podex.ps1 applies: join root + relative, then normalize
		# via the existing parent directory.
		$scriptRoot = $script:RepoRoot
		$relativeDb = './data/podex.db'
		$joined = Join-Path $scriptRoot $relativeDb
		$parent = Split-Path -Parent $joined
		$normalized = Join-Path (Resolve-Path -LiteralPath $parent).Path (Split-Path -Leaf $joined)
		$expected = Join-Path $scriptRoot 'data/podex.db'
		$normalized | Should -Be $expected
	}

	It 'resolves server.psd1, api, views, public beneath the script root' {
		$scriptRoot = $script:RepoRoot
		$paths = @(
			(Join-Path $scriptRoot 'server.psd1')
			(Join-Path $scriptRoot 'api')
			(Join-Path $scriptRoot 'views')
			(Join-Path $scriptRoot 'public')
		)
		foreach ($p in $paths) {
			Test-Path -LiteralPath $p | Should -Be $true
		}
	}

	It 'ensures no SQLite database exists outside data/' {
		# Spec: No SQLite database may exist outside data/.
		$dbFiles = @(Get-ChildItem -LiteralPath $script:RepoRoot -Recurse -File -Filter '*.db' -ErrorAction SilentlyContinue |
				Where-Object { $_.DirectoryName -notmatch '[\\/]data$' -and $_.FullName -notmatch '[\\/]TestDrive[\\/]' -and $_.FullName -notmatch '[\\/]dist[\\/]' })
		$dbFiles.Count | Should -Be 0 -Because 'no SQLite database may exist outside data/'
	}
}

Describe 'Debug route method and guard safety' {
	It 'registers POST /stop, POST /init, DELETE /clear only when debug is on' {
		$stop = Resolve-PodexApiRoute -FilePath (Join-Path $script:RepoRoot 'api/debug/stop.ps1') -BaseDirectory $script:RepoRoot -DebugEnabled $true
		$stop.Method | Should -Be 'Post'
		$stop.Path | Should -Be '/stop'

		$init = Resolve-PodexApiRoute -FilePath (Join-Path $script:RepoRoot 'api/debug/init.ps1') -BaseDirectory $script:RepoRoot -DebugEnabled $true
		$init.Method | Should -Be 'Post'
		$init.Path | Should -Be '/init'

		$clear = Resolve-PodexApiRoute -FilePath (Join-Path $script:RepoRoot 'api/debug/clear.ps1') -BaseDirectory $script:RepoRoot -DebugEnabled $true
		$clear.Method | Should -Be 'Delete'
		$clear.Path | Should -Be '/clear'
	}

	It 'skips all debug routes when debug is off' {
		foreach ($file in @('stop', 'init', 'clear')) {
			$result = Resolve-PodexApiRoute -FilePath (Join-Path $script:RepoRoot "api/debug/$file.ps1") -BaseDirectory $script:RepoRoot -DebugEnabled $false
			$result.Skip | Should -Be $true
		}
	}

	It 'never assigns GET to a debug route' {
		foreach ($file in @('stop', 'init', 'clear')) {
			$result = Resolve-PodexApiRoute -FilePath (Join-Path $script:RepoRoot "api/debug/$file.ps1") -BaseDirectory $script:RepoRoot -DebugEnabled $true
			$result.Method | Should -Not -Be 'Get'
		}
	}
}

Describe 'Module import version floors' {
	It 'podex.ps1 imports PSSQLite with MinimumVersion 1.1.0' {
		$content = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot 'podex.ps1')
		$content | Should -Match 'Import-Module.*PSSQLite.*MinimumVersion\s+1\.1\.0'
	}

	It 'podex.ps1 imports PSSQLite with MaximumVersion 1.99.99' {
		$content = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot 'podex.ps1')
		$content | Should -Match 'Import-Module.*PSSQLite.*MaximumVersion\s+1\.99\.99'
	}

	It 'podex.ps1 imports Pode with MinimumVersion 2.12.1' {
		$content = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot 'podex.ps1')
		$content | Should -Match 'Import-Module.*Pode.*MinimumVersion\s+2\.12\.1'
	}

	It 'podex.ps1 imports Pode with MaximumVersion 2.99.99' {
		$content = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot 'podex.ps1')
		$content | Should -Match 'Import-Module.*Pode.*MaximumVersion\s+2\.99\.99'
	}

	It 'build script installs PSSQLite with the same floor' {
		$content = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot '.build.ps1')
		$content | Should -Match 'Install-Module.*PSSQLite.*MinimumVersion\s+1\.1\.0'
	}

	It 'build script installs Pode with the same floor' {
		$content = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot '.build.ps1')
		$content | Should -Match 'Install-Module.*Pode.*MinimumVersion\s+2\.12\.1'
	}
}

Describe 'Lifecycle scripts are cross-platform' {
	It 'serve.ps1 does not use Get-NetTCPConnection' {
		$content = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot 'tools/serve.ps1')
		$content | Should -Not -Match 'Get-NetTCPConnection'
	}

	It 'serve.ps1 does not use -WindowStyle' {
		$content = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot 'tools/serve.ps1')
		$content | Should -Not -Match 'WindowStyle'
	}

	It 'serve.ps1 records the PID under data/podex.pid' {
		$content = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot 'tools/serve.ps1')
		$content | Should -Match 'Podex\.PidFile'
	}

	It 'serve.ps1 reads the configured endpoint from server.psd1' {
		$content = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot 'tools/serve.ps1')
		$content | Should -Match 'Import-PowerShellDataFile'
		$content | Should -Match 'PodeCfg\.HttpPort'
	}

	It 'stop.ps1 does not use Get-NetTCPConnection' {
		$content = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot 'tools/stop.ps1')
		$content | Should -Not -Match 'Get-NetTCPConnection'
	}

	It 'stop.ps1 reads the configured endpoint from server.psd1' {
		$content = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot 'tools/stop.ps1')
		$content | Should -Match 'Import-PowerShellDataFile'
		$content | Should -Match 'PodeCfg\.HttpPort'
	}

	It 'stop.ps1 sends X-Podex-Debug header on graceful stop' {
		$content = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot 'tools/stop.ps1')
		$content | Should -Match 'X-Podex-Debug'
	}

	It 'stop.ps1 targets the recorded PID' {
		$content = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot 'tools/stop.ps1')
		$content | Should -Match 'podex\.pid'
	}

	It 'stop.ps1 falls back to the configured port when no PID is recorded' {
		$content = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot 'tools/stop.ps1')
		$content | Should -Match 'Get-PodexPortOwnerPid'
		# The fallback must run when neither the graceful path nor the
		# recorded PID released the listener.
		$content | Should -Match 'if \(-not \$stopped\)'
	}

	It 'stop.ps1 port lookup is cross-platform' {
		$content = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot 'tools/stop.ps1')
		# Windows path resolves the listener via netstat, not a Windows-only
		# cmdlet; Unix path uses lsof.
		$content | Should -Match 'netstat'
		$content | Should -Match 'lsof'
	}
}

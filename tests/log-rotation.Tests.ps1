BeforeAll {
	$script:RepoRoot = (Resolve-Path "$PSScriptRoot/..").Path
	Import-Module -Name (Join-Path $script:RepoRoot 'tools/PodexLog.psm1') -Force
}

Describe 'Startup log rotation' {
	It 'creates a missing log directory without creating an archive' {
		$logPath = Join-Path $TestDrive 'missing/logs'

		$result = Start-PodexLogSession -Path $logPath

		$logPath | Should -Exist
		$result | Should -BeNullOrEmpty
		Join-Path $logPath 'archive' | Should -Not -Exist
	}

	It 'moves existing logs into one timestamped startup archive without changing content' {
		$logPath = Join-Path $TestDrive 'existing/logs'
		New-Item -ItemType Directory -Path $logPath -Force | Out-Null
		Set-Content -LiteralPath (Join-Path $logPath 'requests_2026-07-30_001.log') `
			-Value 'request log'
		Set-Content -LiteralPath (Join-Path $logPath 'errors_2026-07-30_001.log') `
			-Value 'error log'
		Set-Content -LiteralPath (Join-Path $logPath 'placeholder.txt') -Value 'keep'

		$archive = Start-PodexLogSession -Path $logPath

		@(Get-ChildItem -LiteralPath $logPath -Filter '*.log' -File).Count | Should -Be 0
		$archive.Parent.Name | Should -Be 'archive'
		$archive.Name | Should -Match '^\d{8}T\d{6}\.\d{3}Z(?:-\d{3})?$'
		Get-Content -Raw -LiteralPath (
			Join-Path $archive.FullName 'requests_2026-07-30_001.log'
		) | Should -Match '^request log'
		Get-Content -Raw -LiteralPath (
			Join-Path $archive.FullName 'errors_2026-07-30_001.log'
		) | Should -Match '^error log'
		Join-Path $logPath 'placeholder.txt' | Should -Exist
	}

	It 'leaves prior archives untouched' {
		$logPath = Join-Path $TestDrive 'prior/logs'
		$priorArchive = Join-Path $logPath 'archive/20260729T120000.000Z'
		New-Item -ItemType Directory -Path $priorArchive -Force | Out-Null
		Set-Content -LiteralPath (Join-Path $priorArchive 'requests.log') -Value 'prior'
		Set-Content -LiteralPath (Join-Path $logPath 'requests.log') -Value 'current'

		$newArchive = Start-PodexLogSession -Path $logPath

		Get-Content -Raw -LiteralPath (Join-Path $priorArchive 'requests.log') |
			Should -Match '^prior'
		Get-Content -Raw -LiteralPath (Join-Path $newArchive.FullName 'requests.log') |
			Should -Match '^current'
	}

	It 'supports WhatIf without moving logs or creating an archive' {
		$logPath = Join-Path $TestDrive 'whatif/logs'
		New-Item -ItemType Directory -Path $logPath -Force | Out-Null
		$logFile = Join-Path $logPath 'requests.log'
		Set-Content -LiteralPath $logFile -Value 'current'

		Start-PodexLogSession -Path $logPath -WhatIf

		$logFile | Should -Exist
		Join-Path $logPath 'archive' | Should -Not -Exist
	}

	It 'archives the preceding logs and writes the live request log during real startup' {
		$logPath = Join-Path $TestDrive 'startup/logs'
		New-Item -ItemType Directory -Path $logPath -Force | Out-Null
		Set-Content -LiteralPath (Join-Path $logPath 'requests_previous.log') `
			-Value 'previous request'
		Set-Content -LiteralPath (Join-Path $logPath 'errors_previous.log') `
			-Value 'previous error'

		$listener = [System.Net.Sockets.TcpListener]::new(
			[System.Net.IPAddress]::Loopback,
			0
		)
		$listener.Start()
		$port = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
		$listener.Stop()

		$process = Start-Process -FilePath 'pwsh' `
			-ArgumentList @(
			'-NoLogo'
			'-NoProfile'
			'-ExecutionPolicy'
			'Bypass'
			'-File'
			(Join-Path $script:RepoRoot 'podex.ps1')
		) `
			-WorkingDirectory $script:RepoRoot `
			-Environment @{
			PODEX_DB_FILE = Join-Path $TestDrive 'startup/podex.db'
			PODEX_HTTP_PORT = [string]$port
			PODEX_LOG_PATH = $logPath
		} `
			-PassThru

		try {
			$ready = $false
			for ($attempt = 0; $attempt -lt 60; $attempt++) {
				if ($process.HasExited) {
					break
				}
				try {
					Invoke-WebRequest -Uri "http://127.0.0.1:$port/health" -TimeoutSec 2 |
						Out-Null
					$ready = $true
					break
				} catch {
					Start-Sleep -Milliseconds 500
				}
			}
			$ready | Should -Be $true

			$archives = @(Get-ChildItem -LiteralPath (Join-Path $logPath 'archive') -Directory)
			$archives.Count | Should -Be 1
			Join-Path $archives[0].FullName 'requests_previous.log' | Should -Exist
			Join-Path $archives[0].FullName 'errors_previous.log' | Should -Exist

			# The readiness request can complete before Pode's asynchronous file
			# logger has opened its output. Send one request after readiness, then
			# allow the logger enough time to flush on slower full-suite runs.
			Invoke-WebRequest -Uri "http://127.0.0.1:$port/health" -TimeoutSec 2 |
				Out-Null
			$freshLogs = @()
			for ($attempt = 0; $attempt -lt 50; $attempt++) {
				$freshLogs = @(
					Get-ChildItem -LiteralPath $logPath -Filter 'requests_*.log' -File
				)
				if ($freshLogs.Count -gt 0) {
					break
				}
				Start-Sleep -Milliseconds 200
			}
			$freshLogs.Count | Should -Be 1
		} finally {
			if (-not $process.HasExited) {
				Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
				$process.WaitForExit(5000) | Out-Null
			}
		}
	}

	It 'wires rotation before Pode server startup and packages the helper' {
		$entrypoint = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot 'podex.ps1')
		$manifest = Get-Content -Raw -LiteralPath (
			Join-Path $script:RepoRoot 'release-manifest.json'
		)

		$rotationIndex = $entrypoint.IndexOf('Start-PodexLogSession')
		$serverIndex = $entrypoint.IndexOf('Start-PodeServer')
		$rotationIndex | Should -BeGreaterThan -1
		$serverIndex | Should -BeGreaterThan $rotationIndex
		$entrypoint | Should -Match 'PODEX_LOG_PATH'
		$manifest | Should -Match '"tools/PodexLog\.psm1"'
	}
}

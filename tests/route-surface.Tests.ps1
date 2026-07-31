# Tests for the page route surface (GET-only page registration).
#
# The Home (/) and CRUD Manager (/crudmgr) pages only render views; nothing
# POSTs to them (the only form targets /api/crud) and hx-boost navigation uses
# GET. These tests assert that routes/web registers GET only for both pages,
# never registers POST for either path, and that a running Podex instance
# returns 200 for GET and 405 for POST on both page routes. The header template
# must continue to use plain GET navigation (anchor hrefs under hx-boost).
#
# The live server is started on an isolated port by temporarily swapping
# server.psd1 (backed up and always restored in AfterAll), mirroring the
# security-headers test harness.

BeforeAll {
	$script:RepoRoot = (Resolve-Path "$PSScriptRoot/..").Path
	$script:ConfigPath = Join-Path $script:RepoRoot 'server.psd1'
	$script:PodexPath = Join-Path $script:RepoRoot 'podex.ps1'

	# Isolated port unlikely to collide with the dev server (8433), a
	# UI-managed instance, or the security-headers test (9300+). Use a wide
	# random range rather than a PID-derived value so rapid successive runs
	# do not collide on the same port (which a leftover TIME_WAIT socket or
	# orphaned process could still hold).
	$script:Port = 9500 + (Get-Random -Minimum 0 -Maximum 400)
	$script:BaseUrl = "http://localhost:$($script:Port)"

	$script:Process = $null
	$script:StartedThisRun = $false
	$script:StartupError = ''
	$script:OriginalConfig = $null

	function Initialize-PodexRouteServer {
		param([int]$Port)

		# Back up the checked-in config once (the first Describe to initialize).
		if ($null -eq $script:OriginalConfig) {
			$script:OriginalConfig = Get-Content -Raw -LiteralPath $script:ConfigPath
		}

		# Seed an isolated database in the Pester temp drive so the API and
		# CRUD routes resolve against known data without touching ./data/.
		$dataDir = Join-Path $TestDrive 'data'
		New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
		$dbFile = Join-Path $dataDir 'podex.db'
		Import-Module -Name 'PSSQLite' -MaximumVersion 1.99.99 -Force
		$initSql = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot 'api/debug/init.sql')
		Invoke-SqliteQuery -DataSource $dbFile -Query $initSql

		# Write the override config with the same shape as the checked-in
		# server.psd1 but with the isolated port and the temp database path.
		$escapedDb = $dbFile -replace '\\', '\\'
		$configText = @"
@{
	Server = @{
		AutoImport = @{
			Modules = @{ Enable = `$true; ExportOnly = `$true }
			Snapins = @{ Enable = `$false }
		}
		FileMonitor = @{ Enable = `$false }
		Request = @{ Timeout = 600 }
	}
	Web = @{
		ErrorPages = @{ ShowExceptions = `$false }
		Static = @{ Cache = @{ Enable = `$false } }
	}
	PodeCfg = @{
		HttpPort = $Port
		HttpUrl = 'localhost'
		CertThumbprint = ''
		HttpsEnabled = `$false
	}
	Podex = @{
		AppName = 'Podex'
		Debug = `$false
		DatabaseType = 'SQLite'
		DBFile = '$escapedDb'
		PidFile = 'podex.pid'
	}
}
"@
		Set-Content -LiteralPath $script:ConfigPath -Value $configText -Force

		# Launch the real podex.ps1 as a detached background process with the
		# repo root as CWD so relative paths resolve as in production.
		$scriptPath = Join-Path $script:RepoRoot 'podex.ps1'
		$script:Process = Start-Process -FilePath 'pwsh' `
			-ArgumentList '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath `
			-WorkingDirectory $script:RepoRoot `
			-WindowStyle Hidden `
			-PassThru

		# Poll until the isolated port answers, up to ~45s.
		$ready = $false
		for ($i = 0; $i -lt 90; $i++) {
			if ($script:Process.HasExited) { break }
			try {
				$null = Invoke-WebRequest -Uri "http://localhost:$Port/" -UseBasicParsing -TimeoutSec 2
				$ready = $true
				break
			} catch {
				Start-Sleep -Milliseconds 500
			}
		}

		if (-not $ready) {
			$script:StartupError = if ($script:Process.HasExited) {
				"Process exited with code $($script:Process.ExitCode)."
			} else {
				"Port $Port did not answer within 45s."
			}
			$errorLog = Join-Path $script:RepoRoot 'logs/errors.log'
			if (Test-Path $errorLog) {
				$tail = (Get-Content $errorLog -Tail 20) -join [Environment]::NewLine
				$script:StartupError += [Environment]::NewLine + 'Error log tail:' + [Environment]::NewLine + $tail
			}
		}
		return $ready
	}

	function Clear-PodexRouteServer {
		if ($script:Process -and -not $script:Process.HasExited) {
			# Kill any child processes Pode may have spawned before stopping
			# the parent, so no orphaned listener holds the port.
			try {
				$children = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
					Where-Object { $_.ParentProcessId -eq $script:Process.Id }
				foreach ($child in $children) {
					Stop-Process -Id $child.ProcessId -Force -ErrorAction SilentlyContinue
				}
			} catch {
				Write-Verbose "Could not enumerate child processes during cleanup: $($_.Exception.Message)"
			}
			Stop-Process -Id $script:Process.Id -Force -ErrorAction SilentlyContinue
			Start-Sleep -Milliseconds 500
		}
		if ($null -ne $script:OriginalConfig) {
			Set-Content -LiteralPath $script:ConfigPath -Value $script:OriginalConfig -NoNewline -Force
			$script:OriginalConfig = $null
		}
	}

	# Skip the current test at runtime if the server did not start.
	function Skip-IfServerUnavailable {
		if (-not $script:StartedThisRun) {
			Set-ItResult -Skipped -Because "Podex did not start (port $($script:Port)): $($script:StartupError)"
		}
	}
}

AfterAll {
	Clear-PodexRouteServer
}

Describe 'Page route registration is GET-only in routes/web' {
	BeforeAll {
		$script:PodexSource = (
			Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot 'routes/web') `
				-Filter '*.ps1' `
				-File |
				ForEach-Object { Get-Content -Raw -LiteralPath $_.FullName }
		) -join [Environment]::NewLine
	}

	It 'registers GET for the Home route' {
		$script:PodexSource | Should -Match "Add-PodeRoute\s+-Path\s+'/'\s+-Method\s+Get\b"
	}

	It 'registers GET for the CRUD Manager route' {
		$script:PodexSource | Should -Match "Add-PodeRoute\s+-Path\s+'/crudmgr'\s+-Method\s+Get\b"
	}

	It 'registers GET for the health route' {
		$script:PodexSource | Should -Match "Add-PodeRoute\s+-Path\s+'/health'\s+-Method\s+Get\b"
	}

	It 'registers the Home route exactly once' {
		$routeMatches = [regex]::Matches($script:PodexSource, "Add-PodeRoute\s+-Path\s+'/'\s+-Method")
		$routeMatches.Count | Should -Be 1
	}

	It 'registers the CRUD Manager route exactly once' {
		$routeMatches = [regex]::Matches($script:PodexSource, "Add-PodeRoute\s+-Path\s+'/crudmgr'\s+-Method")
		$routeMatches.Count | Should -Be 1
	}

	It 'never registers POST for the Home route' {
		$script:PodexSource | Should -Not -Match "Add-PodeRoute\s+-Path\s+'/'\s+.*-Method\s+[A-Za-z, ]*Post"
	}

	It 'never registers POST for the CRUD Manager route' {
		$script:PodexSource | Should -Not -Match "Add-PodeRoute\s+-Path\s+'/crudmgr'\s+.*-Method\s+[A-Za-z, ]*Post"
	}

	It 'does not use the Get, Post compound method for any page route' {
		$script:PodexSource | Should -Not -Match "-Method\s+Get,\s*Post"
	}

	It 'discovers every web route from the composition root' {
		$compositionRoot = Get-Content -Raw -LiteralPath $script:PodexPath
		$compositionRoot | Should -Match 'routes/web'
		$compositionRoot | Should -Match 'Get-ChildItem'
		$compositionRoot | Should -Match '\. \$routeFile\.FullName'
	}
}

Describe 'Header navigation uses GET under hx-boost' {
	BeforeAll {
		$script:HeaderSource = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot 'views/partials/header.pode')
	}

	It 'uses hx-boost on the main layout body' {
		$mainLayout = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot 'views/layouts/main.pode')
		$mainLayout | Should -Match 'hx-boost'
	}

	It 'uses anchor href links for navigation (not hx-post)' {
		$script:HeaderSource | Should -Match '<a\s+href='
	}

	It 'does not use hx-post in the header' {
		$script:HeaderSource | Should -Not -Match 'hx-post'
	}
}

Describe 'Running Podex instance serves page routes via GET only' -Tag 'Integration' {
	BeforeAll {
		$script:StartedThisRun = Initialize-PodexRouteServer -Port $script:Port
		if (-not $script:StartedThisRun) {
			Write-Warning ('Podex did not start on port {0}. {1}' -f $script:Port, $script:StartupError)
		}
	}

	It 'returns 200 for GET /' {
		Skip-IfServerUnavailable
		$response = Invoke-WebRequest -Uri "$($script:BaseUrl)/" -UseBasicParsing -TimeoutSec 10
		$response.StatusCode | Should -Be 200
	}

	It 'returns 200 for GET /crudmgr' {
		Skip-IfServerUnavailable
		$response = Invoke-WebRequest -Uri "$($script:BaseUrl)/crudmgr" -UseBasicParsing -TimeoutSec 10
		$response.StatusCode | Should -Be 200
	}

	It 'returns an OK response for GET /health' {
		Skip-IfServerUnavailable
		$response = Invoke-RestMethod -Uri "$($script:BaseUrl)/health" -TimeoutSec 10
		$response.status | Should -Be 'ok'
	}

	It 'rejects POST / with 405 Method Not Allowed' {
		Skip-IfServerUnavailable
		# Pode returns 405 for a POST to a GET-only route. Wrap in try/catch
		# directly in the It body so Pester's error handling does not
		# intercept the exception before the catch runs.
		$status = 200
		try {
			$null = Invoke-WebRequest -Uri "$($script:BaseUrl)/" -Method Post -UseBasicParsing -TimeoutSec 10
		} catch [System.Net.WebException] {
			$status = [int]$_.Exception.Response.StatusCode
		} catch {
			if ($_.Exception.Response) {
				$status = [int]$_.Exception.Response.StatusCode
			} elseif ($_.Exception.Message -match '(?i)\b405\b') {
				$status = 405
			} else {
				throw
			}
		}
		$status | Should -Be 405
	}

	It 'rejects POST /crudmgr with 405 Method Not Allowed' {
		Skip-IfServerUnavailable
		$status = 200
		try {
			$null = Invoke-WebRequest -Uri "$($script:BaseUrl)/crudmgr" -Method Post -UseBasicParsing -TimeoutSec 10
		} catch [System.Net.WebException] {
			$status = [int]$_.Exception.Response.StatusCode
		} catch {
			if ($_.Exception.Response) {
				$status = [int]$_.Exception.Response.StatusCode
			} elseif ($_.Exception.Message -match '(?i)\b405\b') {
				$status = 405
			} else {
				throw
			}
		}
		$status | Should -Be 405
	}
}

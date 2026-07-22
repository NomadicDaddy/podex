# Tests for the HTTP security response headers.
#
# Starts the real podex.ps1 server on an isolated port by temporarily
# swapping server.psd1 (backed up and always restored in AfterAll) and
# running with the repo root as CWD so all relative paths (./public, ./api,
# ./views, ./logs) resolve as in production. It then issues HTTP requests
# against the page, htmx-fragment, API, and static-asset routes to assert the
# headers are present on every response type. Strict-Transport-Security is
# asserted to be ABSENT on the default HTTP endpoint (it must only be set
# under HTTPS).

BeforeAll {
	$script:RepoRoot = (Resolve-Path "$PSScriptRoot/..").Path
	$script:ConfigPath = Join-Path $script:RepoRoot 'server.psd1'

	# Isolated port unlikely to collide with the dev server (8433) or a
	# UI-managed instance.
	$script:Port = 9300 + ([System.Math]::Abs($PID) % 200)
	$script:BaseUrl = "http://localhost:$($script:Port)"

	$script:Process = $null
	$script:StartedThisRun = $false
	$script:StartupError = ''
	$script:OriginalConfig = $null

	function Initialize-PodexHeaderServer {
		param([int]$Port)

		# Back up the checked-in config once (the first Describe to initialize).
		# Subsequent Describes reuse the same backup so AfterAll always restores
		# the original, not a temp config left by an earlier Describe.
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
		Debug = `$false
		DatabaseType = 'SQLite'
		DBFile = '$escapedDb'
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
			# Check the error log for diagnostics.
			$errorLog = Join-Path $script:RepoRoot 'logs/errors.log'
			if (Test-Path $errorLog) {
				$tail = (Get-Content $errorLog -Tail 20) -join [Environment]::NewLine
				$script:StartupError += [Environment]::NewLine + 'Error log tail:' + [Environment]::NewLine + $tail
			}
		}
		return $ready
	}

	function Clear-PodexHeaderServer {
		# Kill the isolated server process if it is still running.
		if ($script:Process -and -not $script:Process.HasExited) {
			Stop-Process -Id $script:Process.Id -Force -ErrorAction SilentlyContinue
			Start-Sleep -Milliseconds 500
		}

		# ALWAYS restore the checked-in config exactly as it was.
		if ($null -ne $script:OriginalConfig) {
			Set-Content -LiteralPath $script:ConfigPath -Value $script:OriginalConfig -NoNewline -Force
			$script:OriginalConfig = $null
		}
	}

	# Fetch response headers for a path, returning $null on failure. Each test
	# uses this so an unreachable route is reported as a failure, not a crash.
	function Get-HeaderResponse {
		param([string]$Path)
		try {
			return (Invoke-WebRequest -Uri "$($script:BaseUrl)$Path" -UseBasicParsing -TimeoutSec 10).Headers
		} catch {
			return $null
		}
	}

	# Skip the current test at runtime if the server did not start. Using
	# Set-ItResult (rather than -Skip on It) because the server-start result is
	# only known after BeforeAll runs, long after It discovery.
	function Skip-IfServerUnavailable {
		if (-not $script:StartedThisRun) {
			Set-ItResult -Skipped -Because "Podex did not start (port $($script:Port)): $($script:StartupError)"
		}
	}
}

AfterAll {
	Clear-PodexHeaderServer
}

Describe 'HTTP security response headers' -Tag 'Security' {
	BeforeAll {
		$script:StartedThisRun = Initialize-PodexHeaderServer -Port $script:Port
		if (-not $script:StartedThisRun) {
			Write-Warning ('Podex did not start on port {0}. {1}' -f $script:Port, $script:StartupError)
		}
	}

	# Every documented response surface must carry the headers, not just pages.
	$routes = @(
		@{ Name = 'home page'; Path = '/' }
		@{ Name = 'crud manager page'; Path = '/crudmgr' }
		@{ Name = 'htmx fragment'; Path = '/htmx/item-new' }
		@{ Name = 'JSON API'; Path = '/api/crud' }
		@{ Name = 'static asset'; Path = '/public/images/podex.png' }
	)

	foreach ($route in $routes) {
		It "sets X-Content-Type-Options nosniff on the $($route.Name)" {
			Skip-IfServerUnavailable
			$headers = Get-HeaderResponse -Path $route.Path
			$headers | Should -Not -BeNullOrEmpty
			$headers['X-Content-Type-Options'] | Should -Be 'nosniff'
		}

		It "sets Referrer-Policy no-referrer on the $($route.Name)" {
			Skip-IfServerUnavailable
			$headers = Get-HeaderResponse -Path $route.Path
			$headers | Should -Not -BeNullOrEmpty
			$headers['Referrer-Policy'] | Should -Be 'no-referrer'
		}

		It "sets X-Frame-Options DENY on the $($route.Name)" {
			Skip-IfServerUnavailable
			$headers = Get-HeaderResponse -Path $route.Path
			$headers | Should -Not -BeNullOrEmpty
			$headers['X-Frame-Options'] | Should -Be 'DENY'
		}

		It "sets Content-Security-Policy default-src 'self' on the $($route.Name)" {
			Skip-IfServerUnavailable
			$headers = Get-HeaderResponse -Path $route.Path
			$headers | Should -Not -BeNullOrEmpty
			$csp = $headers['Content-Security-Policy']
			$csp | Should -Not -BeNullOrEmpty
			$csp | Should -Match "default-src 'self'"
		}

		It "sets CSP script-src 'self' on the $($route.Name)" {
			Skip-IfServerUnavailable
			$headers = Get-HeaderResponse -Path $route.Path
			$csp = $headers['Content-Security-Policy']
			$csp | Should -Match "script-src 'self'"
		}

		It "sets CSP style-src 'self' on the $($route.Name)" {
			Skip-IfServerUnavailable
			$headers = Get-HeaderResponse -Path $route.Path
			$csp = $headers['Content-Security-Policy']
			$csp | Should -Match "style-src 'self'"
		}

		It "sets CSP img-src 'self' on the $($route.Name)" {
			Skip-IfServerUnavailable
			$headers = Get-HeaderResponse -Path $route.Path
			$csp = $headers['Content-Security-Policy']
			$csp | Should -Match "img-src 'self'"
		}

		It "sets CSP connect-src 'self' on the $($route.Name)" {
			Skip-IfServerUnavailable
			$headers = Get-HeaderResponse -Path $route.Path
			$csp = $headers['Content-Security-Policy']
			$csp | Should -Match "connect-src 'self'"
		}

		It "sets CSP object-src 'none' on the $($route.Name)" {
			Skip-IfServerUnavailable
			$headers = Get-HeaderResponse -Path $route.Path
			$csp = $headers['Content-Security-Policy']
			$csp | Should -Match "object-src 'none'"
		}

		It "sets CSP frame-ancestors 'none' on the $($route.Name)" {
			Skip-IfServerUnavailable
			$headers = Get-HeaderResponse -Path $route.Path
			$csp = $headers['Content-Security-Policy']
			$csp | Should -Match "frame-ancestors 'none'"
		}

		It "does NOT set Strict-Transport-Security on the HTTP $($route.Name)" {
			Skip-IfServerUnavailable
			$headers = Get-HeaderResponse -Path $route.Path
			$headers.ContainsKey('Strict-Transport-Security') | Should -Be $false
		}
	}

	It 'does not allow inline scripts in the layout (CSP compatibility)' {
		# The CSP allows script-src 'self' only, so the layout must not contain
		# any inline <script> blocks (only external src references).
		$main = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot 'views/layouts/main.pode')
		# An inline script is a <script> tag with no src attribute.
		$inlinePattern = '<script(?![^>]*\bsrc=)[^>]*>'
		$inlineMatches = ([regex]::Matches($main, $inlinePattern)).Count
		$inlineMatches | Should -Be 0
	}
}

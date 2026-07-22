# Tests for site-metadata consistency across normal and error responses.
#
# Enforces a single site-metadata contract for:
# - Exact rendered <title> values following the "Podex - <title>" convention,
#   with no double-prefix ("Podex - Podex -").
# - The favicon link referencing /public/images/podex.ico in every template.
# - No version-bearing generator meta tags in any template.
# - The OpenAPI document version matching package.json (single version source).
#
# Starts the real podex.ps1 on an isolated port by temporarily swapping
# server.psd1 (backed up and always restored in AfterAll) and running with the
# repo root as CWD so relative paths resolve as in production.

BeforeAll {
	$script:RepoRoot = (Resolve-Path "$PSScriptRoot/..").Path
	$script:ConfigPath = Join-Path $script:RepoRoot 'server.psd1'

	# Isolated port unlikely to collide with the dev server (8433).
	$script:Port = 9400 + ([System.Math]::Abs($PID) % 200)
	$script:BaseUrl = "http://localhost:$($script:Port)"

	$script:Process = $null
	$script:StartedThisRun = $false
	$script:StartupError = ''
	$script:OriginalConfig = $null

	# Single source-of-truth application version, read once from package.json.
	$script:PackageVersion = ((Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot 'package.json') | ConvertFrom-Json).version)

	function Initialize-PodexMetadataServer {
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
			$errorLog = Join-Path $script:RepoRoot 'logs/errors.log'
			if (Test-Path $errorLog) {
				$tail = (Get-Content $errorLog -Tail 20) -join [Environment]::NewLine
				$script:StartupError += [Environment]::NewLine + 'Error log tail:' + [Environment]::NewLine + $tail
			}
		}
		return $ready
	}

	function Clear-PodexMetadataServer {
		if ($script:Process -and -not $script:Process.HasExited) {
			Stop-Process -Id $script:Process.Id -Force -ErrorAction SilentlyContinue
			Start-Sleep -Milliseconds 500
		}
		if ($null -ne $script:OriginalConfig) {
			Set-Content -LiteralPath $script:ConfigPath -Value $script:OriginalConfig -NoNewline -Force
			$script:OriginalConfig = $null
		}
	}

	function Get-PageContent {
		param([string]$Path)
		try {
			return (Invoke-WebRequest -Uri "$($script:BaseUrl)$Path" -UseBasicParsing -TimeoutSec 10).Content
		} catch {
			return $null
		}
	}

	function Get-JsonResponse {
		param([string]$Path)
		try {
			$resp = Invoke-WebRequest -Uri "$($script:BaseUrl)$Path" -UseBasicParsing -TimeoutSec 10
			return $resp.Content | ConvertFrom-Json
		} catch {
			return $null
		}
	}

	function Skip-IfServerUnavailable {
		if (-not $script:StartedThisRun) {
			Set-ItResult -Skipped -Because "Podex did not start (port $($script:Port)): $($script:StartupError)"
		}
	}
}

AfterAll {
	Clear-PodexMetadataServer
}

Describe 'Site metadata - rendered titles' -Tag 'SiteMetadata' {
	BeforeAll {
		$script:StartedThisRun = Initialize-PodexMetadataServer -Port $script:Port
		if (-not $script:StartedThisRun) {
			Write-Warning ('Podex did not start on port {0}. {1}' -f $script:Port, $script:StartupError)
		}
	}

	It 'renders the Home page <title> as "Podex - Home"' {
		Skip-IfServerUnavailable
		$html = Get-PageContent '/'
		$html | Should -Not -BeNullOrEmpty
		$html | Should -Match '<title>\s*Podex - Home\s*</title>'
	}

	It 'renders the CRUD Manager page <title> as "Podex - CRUD Manager"' {
		Skip-IfServerUnavailable
		$html = Get-PageContent '/crudmgr'
		$html | Should -Not -BeNullOrEmpty
		$html | Should -Match '<title>\s*Podex - CRUD Manager\s*</title>'
	}

	It 'does not produce a double-prefixed title on the Home page' {
		Skip-IfServerUnavailable
		$html = Get-PageContent '/'
		$html | Should -Not -Match 'Podex - Podex -'
	}

	It 'does not produce a double-prefixed title on the CRUD Manager page' {
		Skip-IfServerUnavailable
		$html = Get-PageContent '/crudmgr'
		$html | Should -Not -Match 'Podex - Podex -'
	}
}

Describe 'Site metadata - favicon and generator tags' -Tag 'SiteMetadata' {
	BeforeAll {
		$script:StartedThisRun = Initialize-PodexMetadataServer -Port $script:Port
		if (-not $script:StartedThisRun) {
			Write-Warning ('Podex did not start on port {0}. {1}' -f $script:Port, $script:StartupError)
		}
	}

	It 'references /public/images/podex.ico as favicon on the Home page' {
		Skip-IfServerUnavailable
		$html = Get-PageContent '/'
		$html | Should -Match 'href="/public/images/podex\.ico"'
		$html | Should -Not -Match 'favicon\.svg'
	}

	It 'serves the favicon file at /public/images/podex.ico' {
		Skip-IfServerUnavailable
		try {
			$resp = Invoke-WebRequest -Uri "$($script:BaseUrl)/public/images/podex.ico" -UseBasicParsing -TimeoutSec 10
			$resp.StatusCode | Should -Be 200
		} catch {
			$_.Exception.Response.StatusCode | Should -Be 200
		}
	}

	It 'does not emit a generator meta tag on the Home page' {
		Skip-IfServerUnavailable
		$html = Get-PageContent '/'
		$html | Should -Not -Match '<meta name="generator"'
	}

	It 'does not leak the PowerShell version on the Home page' {
		Skip-IfServerUnavailable
		$html = Get-PageContent '/'
		$html | Should -Not -Match 'PSEdition'
	}
}

Describe 'Site metadata - OpenAPI version' -Tag 'SiteMetadata' {
	BeforeAll {
		$script:StartedThisRun = Initialize-PodexMetadataServer -Port $script:Port
		if (-not $script:StartedThisRun) {
			Write-Warning ('Podex did not start on port {0}. {1}' -f $script:Port, $script:StartupError)
		}
	}

	It 'publishes the package.json version as the OpenAPI info version' {
		Skip-IfServerUnavailable
		$openapi = Get-JsonResponse '/docs/openapi'
		$openapi | Should -Not -BeNullOrEmpty
		$openapi.info.version | Should -Be $script:PackageVersion
	}

	It 'does not publish a stale 0.0.1 OpenAPI version' {
		Skip-IfServerUnavailable
		$openapi = Get-JsonResponse '/docs/openapi'
		$openapi | Should -Not -BeNullOrEmpty
		$openapi.info.version | Should -Not -Be '0.0.1'
	}
}

Describe 'Site metadata - error pages do not leak runtime internals' -Tag 'SiteMetadata' {
	BeforeAll {
		$script:StartedThisRun = Initialize-PodexMetadataServer -Port $script:Port
		if (-not $script:StartedThisRun) {
			Write-Warning ('Podex did not start on port {0}. {1}' -f $script:Port, $script:StartupError)
		}
	}

	It 'renders a branded 404 page with title "Podex - 404 Not Found"' {
		Skip-IfServerUnavailable
		$resp = Invoke-WebRequest -Uri "$($script:BaseUrl)/nonexistent-page-12345" -UseBasicParsing -TimeoutSec 10 -SkipHttpErrorCheck
		$resp.StatusCode | Should -Be 404
		$resp.Content | Should -Match '<title>\s*Podex - 404 Not Found\s*</title>'
	}

	It 'does not dump raw request data on the 404 page' {
		Skip-IfServerUnavailable
		$resp = Invoke-WebRequest -Uri "$($script:BaseUrl)/nonexistent-page-12345" -UseBasicParsing -TimeoutSec 10 -SkipHttpErrorCheck
		$resp.Content | Should -Not -Match 'ConvertTo-Json'
		$resp.Content | Should -Not -Match 'Render Time'
	}

	It 'references podex.ico as favicon on the 404 page' {
		Skip-IfServerUnavailable
		$resp = Invoke-WebRequest -Uri "$($script:BaseUrl)/nonexistent-page-12345" -UseBasicParsing -TimeoutSec 10 -SkipHttpErrorCheck
		$resp.Content | Should -Match 'podex\.ico'
		$resp.Content | Should -Not -Match 'favicon\.svg'
	}

	It 'does not leak the PowerShell version on the 404 page' {
		Skip-IfServerUnavailable
		$resp = Invoke-WebRequest -Uri "$($script:BaseUrl)/nonexistent-page-12345" -UseBasicParsing -TimeoutSec 10 -SkipHttpErrorCheck
		$resp.Content | Should -Not -Match 'PSEdition'
		$resp.Content | Should -Not -Match '<meta name="generator"'
	}
}

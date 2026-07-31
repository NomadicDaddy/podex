#Requires -Version 7.6

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

Import-Module -Name 'PSSQLite' -MinimumVersion 1.1.0 -MaximumVersion 1.99.99 -Force
Import-Module -Name 'Pode' -MinimumVersion 2.12.1 -MaximumVersion 2.99.99 -Force
Import-Module -Name "$PSScriptRoot/tools/PodexLog.psm1" -Force
Import-Module -Name "$PSScriptRoot/tools/PodexRoute.psm1" -Force

# All runtime paths are resolved beneath the script root so the server starts
# correctly regardless of the caller's working directory.
$root = $PSScriptRoot
Set-Location -LiteralPath $root
$bootstrapConfig = Import-PowerShellDataFile -LiteralPath (Join-Path $root 'server.psd1')
$logPath = if ($env:PODEX_LOG_PATH) { $env:PODEX_LOG_PATH } else { Join-Path $root 'logs' }
if (-not [System.IO.Path]::IsPathRooted($logPath)) {
	$logPath = Join-Path $root $logPath
}
$env:PODEX_LOG_PATH = [System.IO.Path]::GetFullPath($logPath)
Start-PodexLogSession -Path $env:PODEX_LOG_PATH | Out-Null

function Write-FormattedLog {
	param([string]$tag, [string]$log, [switch]$save)
	switch ($tag) {
		'debug' { $icon = '🐞' }
		'database' { $icon = '💾' }
		'api' { $icon = '🔗' }
		'informational' { $icon = 'ℹ️' }
		'verbose' { $icon = '🔍' }
		'warning' { $icon = '⚠️' }
		'error' { $icon = '❌' }
		default { $icon = '✅' }
	}
	$timestamp = Get-Date -Format 'yyyyMMddHHmmss'
	$prefix = '{0} {1} {2} ' -f $timestamp, $tag.PadRight(11), $icon
	Write-PodeHost $prefix -NoNewLine
	$maxLineLength = [int]($Host.UI.RawUI.WindowSize.Width - $prefix.Length - 1)
	$currentPosition = 0
	while ($currentPosition -lt $log.Length) {
		$endPosition = [math]::Min(($log.Length - $currentPosition), $maxLineLength)
		$line = $log.Substring($currentPosition, $endPosition)
		if ($currentPosition -ne 0) {
			Write-PodeHost "$(' ' * $($prefix.Length))$($line)"
		} else {
			Write-PodeHost "$($line)"
		}
		$currentPosition += $line.Length
	}
	if ($save) {
		$log |
			Out-File -FilePath "./$($WebEvent.Request.Url.AbsolutePath)/$($WebEvent.Method).json" -Force
	}
}

Start-PodeServer -Name $bootstrapConfig.Podex.AppName -Threads 5 -ScriptBlock {
	$cfg = Get-PodeConfig
	. "$PSScriptRoot/src/ItemStore.ps1"
	. "$PSScriptRoot/src/ItemApp.ps1"
	Use-PodeScript -Path "$PSScriptRoot/src/ItemStore.ps1"
	Use-PodeScript -Path "$PSScriptRoot/src/ItemApp.ps1"
	Set-PodeViewEngine -Type Pode

	$dbFile = if ($env:PODEX_DB_FILE) { $env:PODEX_DB_FILE } else { $cfg.Podex.DBFile }
	if (-not [System.IO.Path]::IsPathRooted($dbFile)) {
		$dbFile = Join-Path $PSScriptRoot $dbFile
	}
	$dataDirectory = Split-Path -Parent $dbFile
	if (-not (Test-Path -LiteralPath $dataDirectory)) {
		New-Item -ItemType Directory -Path $dataDirectory -Force | Out-Null
	}
	$dbFile = Join-Path (Resolve-Path -LiteralPath $dataDirectory).Path (Split-Path -Leaf $dbFile)
	$cfg.Podex.DBFile = $dbFile

	New-PodeLoggingMethod -File -Path $env:PODEX_LOG_PATH -Name 'requests' |
		Enable-PodeRequestLogging
	if ($cfg.Podex.Debug) {
		New-PodeLoggingMethod -Terminal | Enable-PodeErrorLogging
	} else {
		New-PodeLoggingMethod -File -Path $env:PODEX_LOG_PATH -Name 'errors' |
			Enable-PodeErrorLogging
	}

	$httpPort = if ($env:PODEX_HTTP_PORT) { [int]$env:PODEX_HTTP_PORT } else {
		[int]$cfg.PodeCfg.HttpPort
	}
	if ($cfg.PodeCfg.HttpsEnabled -and $cfg.PodeCfg.CertThumbprint) {
		Add-PodeEndpoint -Address $cfg.PodeCfg.HttpUrl `
			-Port $httpPort `
			-Protocol Https `
			-CertificateThumbprint $cfg.PodeCfg.CertThumbprint `
			-CertificateStoreLocation LocalMachine
	} else {
		Add-PodeEndpoint -Address $cfg.PodeCfg.HttpUrl -Port $httpPort -Protocol Http
	}

	Set-PodeSecurityContentTypeOptions
	Set-PodeSecurityReferrerPolicy -Type No-Referrer
	Set-PodeSecurityFrameOptions -Type Deny
	Set-PodeSecurityPermissionsPolicy -Camera 'none' -Geolocation 'none' -Microphone 'none'
	Set-PodeSecurityContentSecurityPolicy `
		-Default 'self' `
		-Scripts 'self' `
		-Style 'self' `
		-Image 'self' `
		-Connect 'self' `
		-Object 'none' `
		-FrameAncestor 'none'
	if ($cfg.PodeCfg.HttpsEnabled) {
		Set-PodeSecurityStrictTransportSecurity -Duration 31536000 -IncludeSubDomains
	}

	Add-PodeStaticRoute -Path '/public' -Source "$PSScriptRoot/public"

	$webRouteDirectory = Join-Path $PSScriptRoot 'routes/web'
	foreach ($routeFile in (Get-ChildItem -LiteralPath $webRouteDirectory -Filter '*.ps1' -File |
				Sort-Object -Property Name)) {
		. $routeFile.FullName
	}

	# file-based api routes (json or html)
	# Debug-only routes (api/debug/*.ps1) register only when Podex.Debug is
	# enabled and use the short public paths /stop, /clear, and /init. With
	# debug disabled those destructive endpoints are absent entirely. When debug
	# is enabled, a loopback guard and an X-Podex-Debug header guard restrict
	# them to local tooling so a reachable debug-enabled host cannot be driven
	# by a remote or unauthenticated caller.
	$debugLoopbackGuard = {
		$clientIp = $WebEvent.Request.Handler.RemoteEndPoint.Address
		if ((-not ($clientIp -eq [System.Net.IPAddress]::Loopback)) -and
			(-not ($clientIp -eq [System.Net.IPAddress]::IPv6Loopback))) {
			Set-PodeResponseStatus -Code 403 -Description 'Debug endpoints are restricted to localhost.'
			return $false
		}
		$header = $WebEvent.Request.Headers['X-Podex-Debug']
		if (-not $header -or $header -ne 'true') {
			Set-PodeResponseStatus -Code 403 -Description 'Debug endpoints require X-Podex-Debug: true.'
			return $false
		}
		return $true
	}
	foreach ($file in (Get-ChildItem -Path "$PSScriptRoot/api" -Filter *.ps1 -Recurse -File)) {
		$routeInfo = Resolve-PodexApiRoute -FilePath $file.FullName -BaseDirectory $PSScriptRoot -DebugEnabled $cfg.Podex.Debug
		if ($routeInfo.Skip) {
			continue
		}
		$routeParams = @{
			Path = $routeInfo.Path
			Method = $routeInfo.Method
			FilePath = $file.FullName
		}
		if ($file.FullName -match '[\\/]api[\\/]debug[\\/]') {
			$routeParams['Middleware'] = $debugLoopbackGuard
		}
		Add-PodeRoute @routeParams
	}

	if ($cfg.Podex.Debug) {
		foreach ($route in (Get-PodeRoute | Sort-Object -Unique -Property Path, Method)) {
			Write-FormattedLog -tag 'routes' `
				-log "$($route.Path.PadRight(30)) -> $($route.Method.PadRight(10))"
		}
	}

	# api docs
	# The application version is loaded once from package.json so there is no
	# independent version literal that can drift. Pode renders the OpenAPI
	# document at /docs/openapi with this version.
	$podexVersion = ((Get-Content -Raw -LiteralPath "$PSScriptRoot/package.json" | ConvertFrom-Json).version)
	Enable-PodeOpenApi -RouteFilter '/api/*' -Path '/docs/openapi'
	Add-PodeOAInfo -Title 'Podex - OpenAPI 3.0' -Version $podexVersion -Description 'Podex API'
	Enable-PodeOAViewer -Type Swagger -Path '/docs/swagger' -DarkMode -Title 'Podex API' -OpenApiUrl '/docs/openapi'

}

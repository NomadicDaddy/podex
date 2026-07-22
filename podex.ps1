Import-Module -Name 'PSSQLite' -MinimumVersion 1.1.0 -MaximumVersion 1.99.99 -Force
Import-Module -Name 'Pode' -MinimumVersion 2.11.1 -MaximumVersion 2.99.99 -Force
Import-Module -Name "$PSScriptRoot/tools/PodexRoute.psm1" -Force

# All runtime paths are resolved beneath the script root so the server starts
# correctly regardless of the caller's working directory. This keeps
# server.psd1, logs/, public/, api/, views/, and the SQLite database file
# anchored to the repository root rather than to an arbitrary cwd.
$root = $PSScriptRoot
Set-Location -LiteralPath $root

function Write-FormattedLog {
	param([string]$tag, [string]$log, [switch]$save)
	switch ($tag) {
		'debug' { $icon = '🐞' }
		'database'	{ $icon = '💾' }
		'api' { $icon = '🔗' }
		'informational' { $icon = 'ℹ️' }
		'verbose'	{ $icon = '🔍' }
		'warning'	{ $icon = '⚠️' }
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
		$log | Out-File -FilePath "./$($WebEvent.Request.Url.AbsolutePath)/$($WebEvent.Method).json" -Force
	}
}
# Start-PodeServer -Name 'Podex' -ConfigFile '.\podex.psd1' -Threads 5 -ScriptBlock {
Start-PodeServer -Name 'Podex' -Threads 5 -ScriptBlock {

	# get config
	$cfg = (Get-PodeConfig)
	Set-PodeViewEngine -Type Pode

	# Resolve the configured SQLite database file to an absolute, normalized
	# path beneath the script root so query handlers always read and write the
	# intended file regardless of the working directory at request time. The
	# parent directory is created if missing so initialization is idempotent.
	$dbFile = $cfg.Podex.DBFile
	if (-not [System.IO.Path]::IsPathRooted($dbFile)) {
		$dbFile = (Join-Path $PSScriptRoot $dbFile)
	}
	$dataDir = (Split-Path -Parent $dbFile)
	if (-not (Test-Path -LiteralPath $dataDir)) {
		New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
	}
	# Normalize the full path (strips ./ segments, resolves .. etc.) against the
	# now-existing parent directory.
	$cfg.Podex.DBFile = (Join-Path (Resolve-Path -LiteralPath $dataDir).Path (Split-Path -Leaf $dbFile))

	# setup logging
	New-PodeLoggingMethod -File -Path './logs' -Name 'requests' | Enable-PodeRequestLogging
	if ($cfg.Podex.Debug) {
		New-PodeLoggingMethod -Terminal | Enable-PodeErrorLogging
	} else {
		New-PodeLoggingMethod -File -Path './logs' -Name 'errors' | Enable-PodeErrorLogging
	}

	# create appropriate endpoint
	if ($($cfg.PodeCfg.HttpsEnabled) -and $($cfg.PodeCfg.CertThumbprint) -ne '') {
		Add-PodeEndpoint -Address $($cfg.PodeCfg.HttpUrl) -Port $($cfg.PodeCfg.HttpPort) -Protocol Https -CertificateThumbprint $($cfg.PodeCfg.CertThumbprint) -CertificateStoreLocation LocalMachine
	} else {
		Add-PodeEndpoint -Address $($cfg.PodeCfg.HttpUrl) -Port $($cfg.PodeCfg.HttpPort) -Protocol Http
	}

	# security response headers (defense-in-depth against XSS, clickjacking,
	# MIME-sniffing, and transport downgrade). Strict-Transport-Security is
	# added only when the endpoint is HTTPS so the default HTTP development
	# endpoint never advertises a transport policy it cannot honour.
	# Content-Security-Policy permits first-party assets only; it relies on
	# the modal controller in src/crudmgr.js so no inline script is required.
	Set-PodeSecurityContentTypeOptions
	Set-PodeSecurityReferrerPolicy -Type No-Referrer
	Set-PodeSecurityFrameOptions -Type Deny
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

	# static routes
	Add-PodeStaticRoute -Path '/public' -Source './public'

	# front-end routes
	Add-PodeRoute -Path '/' -Method Get, Post -ScriptBlock { Write-PodeViewResponse -Path 'layouts/main' -Data @{ PageName = 'Home'; Title = 'Home'; Components = @('about'); } }
	Add-PodeRoute -Path '/crudmgr'	-Method Get, Post -ScriptBlock { Write-PodeViewResponse -Path 'layouts/main' -Data @{ PageName = 'CRUDMgr'; Title = 'CRUD Manager'; Components = @('crudmgr'); } }

	# htmx routes (html only)
	Add-PodeRoute -Path '/htmx/item-new' -Method Get -ScriptBlock { Write-PodeViewResponse -Path 'layouts/bare' -Data @{ Components = @('crudmgr-new'); } }

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

	# show routes
	if ($cfg.Podex.Debug) {
		foreach ($route in (Get-PodeRoute | Sort-Object -Unique -Property Path, Method)) {
			# Write-FormattedLog -tag 'routes' -log "$($route.Path.PadRight(30)) -> $($route.Method.PadRight(10)) -> $($logic)"
			Write-FormattedLog -tag 'routes' -log "$($route.Path.PadRight(30)) -> $($route.Method.PadRight(10))"
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

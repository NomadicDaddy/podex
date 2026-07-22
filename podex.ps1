Import-Module -Name 'PSSQLite' -MaximumVersion 1.99.99 -Force
Import-Module -Name 'Pode' -MaximumVersion 2.99.99 -Force
Import-Module -Name "$PSScriptRoot/tools/PodexRoute.psm1" -Force

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
	# is enabled, a loopback guard still restricts them to localhost so a
	# reachable debug-enabled host cannot be driven by a remote, unauthenticated
	# caller.
	$debugLoopbackGuard = {
		$clientIp = $WebEvent.Request.Handler.RemoteEndPoint.Address
		if (($clientIp -eq [System.Net.IPAddress]::Loopback) -or ($clientIp -eq [System.Net.IPAddress]::IPv6Loopback)) {
			return $true
		}
		Set-PodeResponseStatus -Code 403 -Description 'Debug endpoints are restricted to localhost.'
		return $false
	}
	foreach ($file in (Get-ChildItem -Path './api' -Filter *.ps1 -Recurse -File)) {
		$routeInfo = Resolve-PodexApiRoute -FilePath $file.FullName -BaseDirectory $PWD.Path -DebugEnabled $cfg.Podex.Debug
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
	$podexVersion = ((Get-Content -Raw -LiteralPath './package.json' | ConvertFrom-Json).version)
	Enable-PodeOpenApi -RouteFilter '/api/*' -Path '/docs/openapi'
	Add-PodeOAInfo -Title 'Podex - OpenAPI 3.0' -Version $podexVersion -Description 'Podex API'
	Enable-PodeOAViewer -Type Swagger -Path '/docs/swagger' -DarkMode -Title 'Podex API' -OpenApiUrl '/docs/openapi'

}

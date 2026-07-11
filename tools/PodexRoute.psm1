# PodexRoute.psm1
# Resolves file-based API routes for Podex. This module centralizes the route
# registration decision so it can be tested independently of Start-PodeServer.
#
# Debug-only routes (api/debug/*.ps1) register only when Podex.Debug is enabled
# and use the short public paths /stop, /clear, and /init. With debug disabled
# those destructive endpoints are absent entirely.

function Resolve-PodexApiRoute {
	<#
	.SYNOPSIS
		Determines whether a given api/*.ps1 file should be registered as a route,
		and if so, what HTTP method and URL path it maps to.

	.DESCRIPTION
		Mirrors the file-based route conventions documented in the Podex spec:
		- api/<resource>/get.ps1 -> GET /api/<resource>
		- api/<resource>/post.ps1 -> POST /api/<resource>
		- api/<resource>/put.ps1 -> PUT /api/<resource>
		- api/<resource>/delete.ps1 -> DELETE /api/<resource>
		- api/debug/*.ps1 -> GET /<basename> (only when Debug is enabled)
		- Other scripts -> GET /api/<relative-path-without-extension>

	.PARAMETER FilePath
		The full path to the .ps1 route file.

	.PARAMETER BaseDirectory
		The project root used to compute the relative path.

	.PARAMETER DebugEnabled
		Whether Podex.Debug is enabled. When false, api/debug/* files are excluded.

	.OUTPUTS
		A hashtable with keys 'Path' (string), 'Method' (string), and 'Skip'
		(bool). When 'Skip' is true, the file should not be registered.
	#>
	param(
		[Parameter(Mandatory)]
		[string]$FilePath,
		[Parameter(Mandatory)]
		[string]$BaseDirectory,
		[bool]$DebugEnabled = $false
	)

	$normalizedBase = $BaseDirectory.TrimEnd('\', '/') + '\'
	$relativePath = $FilePath -replace [regex]::Escape($normalizedBase), '' -replace '\\', '/'

	$result = @{
		Skip = $false
		Path = $null
		Method = $null
	}

	if ($relativePath -match '/debug/') {
		if (-not $DebugEnabled) {
			$result.Skip = $true
			return $result
		}
		$baseName = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
		$result.Path = '/' + $baseName
		$result.Method = 'Get'
		return $result
	}

	$method = (Get-Culture).TextInfo.ToTitleCase([System.IO.Path]::GetFileName($FilePath)) -replace '\.ps1$', ''
	$apiPath = '/' + ($relativePath -replace '\.ps1$', '')
	if ($method -in @('Get', 'Post', 'Put', 'Delete')) {
		$apiPath = $apiPath -replace "/$($method)", ''
	} else {
		$method = 'Get'
	}
	$result.Path = $apiPath
	$result.Method = $method
	return $result
}

Export-ModuleMember -Function Resolve-PodexApiRoute

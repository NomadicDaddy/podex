# PodexRoute.psm1
# Resolves file-based API routes for Podex. This module centralizes the route
# registration decision so it can be tested independently of Start-PodeServer.
#
# Debug-only routes (api/debug/*.ps1) register only when Podex.Debug is enabled
# and use the short public paths /stop, /init, and /clear. With debug disabled
# those destructive endpoints are absent entirely.

function Resolve-PodexApiRoute {
	<#
	.SYNOPSIS
		Determines whether a given api/*.ps1 file should be registered as a route,
		and if so, what HTTP method and URL path it maps to.

	.DESCRIPTION
		Mirrors the file-based route conventions documented in the Podex spec:
		- api/<resource>/get.ps1    -> GET    /api/<resource>
		- api/<resource>/post.ps1   -> POST   /api/<resource>
		- api/<resource>/put.ps1    -> PUT    /api/<resource>
		- api/<resource>/delete.ps1 -> DELETE /api/<resource>
		- api/debug/stop.ps1  -> POST   /stop  (only when Debug is enabled)
		- api/debug/init.ps1  -> POST   /init  (only when Debug is enabled)
		- api/debug/clear.ps1 -> DELETE /clear (only when Debug is enabled)
		- Other scripts -> GET /api/<relative-path-without-extension>

		Path computation uses [IO.Path]::GetRelativePath and normalizes both
		slash styles so route derivation is consistent on Windows, Linux, and
		macOS. Only a terminal /get, /post, /put, or /delete segment is stripped
		when selecting the HTTP method.

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

	# Compute the relative path using the .NET relative-path API, then normalize
	# both forward and back slashes to forward slashes so route derivation is
	# identical on every platform.
	$relativePath = [System.IO.Path]::GetRelativePath($BaseDirectory, $FilePath)
	$relativePath = $relativePath -replace '\\', '/'

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
		switch ($baseName) {
			'stop' {
				$result.Path = '/stop'
				$result.Method = 'Post'
			}
			'init' {
				$result.Path = '/init'
				$result.Method = 'Post'
			}
			'clear' {
				$result.Path = '/clear'
				$result.Method = 'Delete'
			}
			default {
				$result.Path = '/' + $baseName
				$result.Method = 'Post'
			}
		}
		return $result
	}

	$method = (Get-Culture).TextInfo.ToTitleCase([System.IO.Path]::GetFileName($FilePath)) -replace '\.ps1$', ''
	$apiPath = '/' + ($relativePath -replace '\.ps1$', '')
	if ($method -in @('Get', 'Post', 'Put', 'Delete')) {
		# Strip only a terminal verb segment so the resource path is clean.
		$apiPath = $apiPath -replace "/$($method)$", ''
	} else {
		$method = 'Get'
	}
	$result.Path = $apiPath
	$result.Method = $method
	return $result
}

Export-ModuleMember -Function Resolve-PodexApiRoute

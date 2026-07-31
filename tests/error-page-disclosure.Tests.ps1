# Tests for client-visible disclosure of runtime internals on error pages.
#
# The error templates (errors/404.html.pode and errors/default.html.pode)
# must not embed PowerShell edition/version, raw request data, exception
# messages, stack traces, render timestamps, or filesystem/module paths in
# the markup served to a browser when Web.ErrorPages.ShowExceptions is false.
# The checked-in configuration must keep that flag off.

BeforeAll {
	$script:RepoRoot = (Resolve-Path "$PSScriptRoot/..").Path
	$script:ConfigPath = Join-Path $script:RepoRoot 'server.psd1'
	$script:ErrorTemplates = @('errors/404.html.pode', 'errors/default.html.pode')

	function Get-FileContent {
		param([string]$RelativePath)
		return Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot $RelativePath)
	}
}

Describe 'Error page exception disclosure configuration' {
	It 'disables Web.ErrorPages.ShowExceptions in the checked-in default configuration' {
		$config = Import-PowerShellDataFile -Path $script:ConfigPath
		$config.Web.ErrorPages.ShowExceptions | Should -Be $false
	}

	It 'keeps Podex.Debug disabled in the checked-in default configuration' {
		$config = Import-PowerShellDataFile -Path $script:ConfigPath
		$config.Podex.Debug | Should -Be $false
	}
}

Describe 'Error templates do not leak runtime internals' {
	It 'does not reference a PowerShell edition/version generator meta tag in any error template' {
		foreach ($tpl in $script:ErrorTemplates) {
			$content = Get-FileContent $tpl
			$content | Should -Not -Match 'PSVersionTable'
			$content | Should -Not -Match 'PSEdition'
			$content | Should -Not -Match 'generator'
		}
	}

	It 'does not dump raw request data JSON in the 404 template' {
		$content = Get-FileContent 'errors/404.html.pode'
		$content | Should -Not -Match 'ConvertTo-Json'
		$content | Should -Not -Match '\$data \| ConvertTo-Json'
		$content | Should -Not -Match 'Render Time'
	}

	It 'does not dump raw request data JSON in the default error template' {
		$content = Get-FileContent 'errors/default.html.pode'
		$content | Should -Not -Match 'ConvertTo-Json'
		$content | Should -Not -Match '\$data \| ConvertTo-Json'
		$content | Should -Not -Match 'Render Time'
	}

	It 'does not embed exception message or stack trace output in the default error template' {
		$content = Get-FileContent 'errors/default.html.pode'
		$content | Should -Not -Match 'exception\.message'
		$content | Should -Not -Match 'exception\.stacktrace'
		$content | Should -Not -Match 'stacktrace'
	}

	It 'references podex.ico (not the missing favicon.svg) in the 404 template' {
		$content = Get-FileContent 'errors/404.html.pode'
		$content | Should -Match 'podex\.ico'
		$content | Should -Not -Match 'favicon\.svg'
	}

	It 'references podex.ico (not the missing favicon.svg) in the default error template' {
		$content = Get-FileContent 'errors/default.html.pode'
		$content | Should -Match 'podex\.ico'
		$content | Should -Not -Match 'favicon\.svg'
	}

	It 'uses configured branding and only the shared Podex stylesheet' {
		foreach ($tpl in $script:ErrorTemplates) {
			$content = Get-FileContent $tpl
			$content | Should -Match 'Get-PodeConfig'
			$content | Should -Match '/public/css/podex\.css'
			$content | Should -Not -Match '/public/css/(output|todomvc)'
		}
	}
}

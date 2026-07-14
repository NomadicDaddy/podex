BeforeAll {
	$script:RepoRoot = (Resolve-Path "$PSScriptRoot/..").Path
	$script:ConfigPath = Join-Path $script:RepoRoot 'server.psd1'
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

	It 'does not expose exception details when Podex.Debug is false' {
		$config = Import-PowerShellDataFile -Path $script:ConfigPath
		$config.Podex.Debug | Should -Be $false
		$config.Web.ErrorPages.ShowExceptions | Should -Be $false
	}
}

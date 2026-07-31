BeforeAll {
	$script:RepoRoot = (Resolve-Path "$PSScriptRoot/..").Path

	function Get-FileContent {
		param([string]$RelativePath)
		return Get-Content -LiteralPath (Join-Path $script:RepoRoot $RelativePath) -Raw
	}
}

Describe 'Native CSS toolchain' {
	It 'has no Tailwind dependencies, scripts, or formatting plugin' {
		$package = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'package.json') -Raw |
			ConvertFrom-Json
		$prettier = Get-FileContent '.prettierrc'

		$package.devDependencies.PSObject.Properties.Name | Should -Not -Contain 'tailwindcss'
		$package.devDependencies.PSObject.Properties.Name | Should -Not -Contain '@tailwindcss/cli'
		$package.devDependencies.PSObject.Properties.Name |
			Should -Not -Contain 'prettier-plugin-tailwindcss'
		$package.scripts.PSObject.Properties.Name | Should -Not -Contain 'css:compile'
		$prettier | Should -Not -Match 'tailwind'
	}

	It 'bundles the native stylesheet entry point with Bun' {
		$buildAssets = Get-FileContent 'scripts/build-assets.ts'

		$buildAssets | Should -Match "src/podex\.css.*public/css/podex\.css"
		$buildAssets | Should -Match 'Bun\.build'
	}

	It 'contains no Tailwind directives or utility variants in authored UI files' {
		$styleFiles = Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot 'src') -Filter '*.css' -Recurse
		$viewFiles = Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot 'views') -Filter '*.pode' -Recurse
		$styles = ($styleFiles | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
		$views = ($viewFiles | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"

		$styles | Should -Not -Match '@(?:apply|config|plugin|theme|utility)|tailwindcss'
		$views | Should -Not -Match '\b(?:dark|sm|md|lg|xl):'
		$views | Should -Not -Match '\b(?:bg|border|font|gap|grid|items|justify|m[trblxy]?|p[trblxy]?|shadow|space-[xy]|text|w|h)-'
	}

	It 'does not classify Tailwind as a distributed browser asset' {
		Get-FileContent 'scripts/lib/license-catalog.ts' | Should -Not -Match 'tailwind'
	}
}

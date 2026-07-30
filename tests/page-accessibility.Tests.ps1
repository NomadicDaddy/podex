BeforeAll {
	$script:RepoRoot = (Resolve-Path "$PSScriptRoot/..").Path

	function Get-FileContent {
		param([string]$RelativePath)
		return Get-Content -LiteralPath (Join-Path $script:RepoRoot $RelativePath) -Raw
	}
}

Describe 'Document-level h1 headings' {
	It 'renders one h1 containing Podex on the Home page in about.pode' {
		$about = Get-FileContent 'views/components/about.pode'
		$about | Should -Match '<h1[^>]*>\s*Podex\s*</h1>'
	}

	It 'renders one h1 containing CRUD Manager in crudmgr.pode' {
		$crudmgr = Get-FileContent 'views/components/crudmgr.pode'
		$crudmgr | Should -Match '<h1[^>]*>\s*CRUD Manager\s*</h1>'
	}

	It 'has no h1 reading Item Management in crudmgr.pode' {
		$crudmgr = Get-FileContent 'views/components/crudmgr.pode'
		$crudmgr | Should -Not -Match '<h1[^>]*>Item Management</h1>'
	}

	It 'uses h2 for subsection headings in about.pode (no h3 headings)' {
		$about = Get-FileContent 'views/components/about.pode'
		$h2Matches = ([regex]::Matches($about, '<h2')).Count
		$h2Matches | Should -BeGreaterOrEqual 7
		$about | Should -Not -Match '<h3'
	}
}

Describe 'Distinct accessible names for row inputs' {
	It 'gives the item input an aria-label containing its purpose and {{id}}' {
		$crudmgr = Get-FileContent 'views/components/crudmgr.pode'
		$crudmgr | Should -Match 'aria-label="Item name \{\{id\}\}"'
	}

	It 'gives the description input an aria-label containing its purpose and {{id}}' {
		$crudmgr = Get-FileContent 'views/components/crudmgr.pode'
		$crudmgr | Should -Match 'aria-label="Description \{\{id\}\}"'
	}

	It 'uses different label text for item vs description inputs' {
		$crudmgr = Get-FileContent 'views/components/crudmgr.pode'
		$crudmgr | Should -Match 'aria-label="Item name'
		$crudmgr | Should -Match 'aria-label="Description'
	}
}

Describe 'Live region and busy state for htmx updates' {
	It 'sets aria-live=polite and aria-atomic=false on #crud-list' {
		$crudmgr = Get-FileContent 'views/components/crudmgr.pode'
		$crudmgr | Should -Match 'id="crud-list"'
		$crudmgr | Should -Match 'aria-live="polite"'
		$crudmgr | Should -Match 'aria-atomic="false"'
	}

	It 'keeps the visual loading indicator aria-hidden=true' {
		$crudmgr = Get-FileContent 'views/components/crudmgr.pode'
		$loadingBlock = [regex]::Match($crudmgr, '(?s)id="loading".*?</div>')
		$loadingBlock.Value | Should -Match 'aria-hidden="true"'
	}

	It 'toggles aria-busy from src/crudmgr.js during htmx:before:request and htmx:after:request' {
		$controller = Get-FileContent 'src/crudmgr.js'
		$controller | Should -Match "htmx:before:request"
		$controller | Should -Match "htmx:after:request"
		$controller | Should -Match "aria-busy"
		$controller | Should -Match "crud-list"
		# The setBusy helper must set true on before and false on after.
		$controller | Should -Match "setAttribute\('aria-busy', 'true'\)"
		$controller | Should -Match "setAttribute\('aria-busy', 'false'\)"
	}
}

Describe 'Prefers-color-scheme dark theme behavior' {
	It 'removes the class-only @custom-variant dark override' {
		$css = Get-FileContent 'public/css/tailwind.css'
		$css | Should -Not -Match '@custom-variant dark'
	}

	It 'relies on prefers-color-scheme for dark overrides' {
		$css = Get-FileContent 'public/css/tailwind.css'
		$css | Should -Match 'prefers-color-scheme:\s*dark'
	}

	It 'does not add a JavaScript theme toggle' {
		$controller = Get-FileContent 'src/crudmgr.js'
		$controller | Should -Not -Match 'theme'
		$controller | Should -Not -Match 'toggleDark'
	}

	It 'sets color-scheme: light dark on :root' {
		$css = Get-FileContent 'public/css/tailwind.css'
		$css | Should -Match 'color-scheme:\s*light dark'
	}
}

Describe 'Header logo dimensions and empty alt' {
	It 'sets width and height attributes matching podex.png intrinsic dimensions' {
		$header = Get-FileContent 'views/partials/header.pode'
		$header | Should -Match 'width="1024"'
		$header | Should -Match 'height="1024"'
	}

	It 'constrains the logo to matching responsive width and height' {
		$header = Get-FileContent 'views/partials/header.pode'
		$header | Should -Match 'class="[^"]*\bsize-8\b[^"]*\bsm:size-10\b[^"]*"'
		$header | Should -Match '\bshrink-0\b'
		$header | Should -Match '\bobject-contain\b'
	}

	It 'uses empty alt because the adjacent span says Podex' {
		$header = Get-FileContent 'views/partials/header.pode'
		$header | Should -Match 'alt=""'
		$header | Should -Not -Match 'alt="Podex"'
	}

	It 'keeps the adjacent Podex span text' {
		$header = Get-FileContent 'views/partials/header.pode'
		$header | Should -Match '>Podex</span>'
	}
}

Describe 'Header and footer surfaces' {
	It 'keeps the brand and navigation together on the left' {
		$header = Get-FileContent 'views/partials/header.pode'

		$header | Should -Match '\bgap-x-8\b'
		$header | Should -Not -Match '\bjustify-between\b'
	}

	It 'uses solid primary colors without gradients' {
		$header = Get-FileContent 'views/partials/header.pode'
		$footer = Get-FileContent 'views/partials/footer.pode'

		foreach ($surface in @($header, $footer)) {
			$surface | Should -Match '\bbg-primary-800\b'
			$surface | Should -Match '\bdark:bg-primary-950\b'
			$surface | Should -Not -Match '\bbg-linear-'
			$surface | Should -Not -Match '\b(from|via|to)-'
		}
	}
}

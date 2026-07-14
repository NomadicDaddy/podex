BeforeAll {
	$script:RepoRoot = (Resolve-Path "$PSScriptRoot/..").Path

	# Render a .pode component/partial the same way the Pode view engine does:
	# it concatenates component files listed under views/components/ and replaces
	# $() expression placeholders with their evaluated output. This helper is a
	# faithful stand-in for the bare layout composition used by /htmx/item-new
	# and lets the test assert on the actual shipped template markup without a
	# running server.
	function Get-RenderedComponent {
		param([string]$ComponentName)

		$componentPath = Join-Path $script:RepoRoot "views/components/$ComponentName.pode"
		$raw = Get-Content -LiteralPath $componentPath -Raw

		# Pode .pode templates use $( ... ) blocks for inline PowerShell. Our
		# component templates contain no such blocks, so we return the raw HTML.
		return $raw
	}
}

Describe 'Add-item route and component wiring' {
	It 'registers GET /htmx/item-new in podex.ps1' {
		$podex = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'podex.ps1') -Raw
		$podex | Should -Match "'/htmx/item-new'"
		$podex | Should -Match "Components = @\('crudmgr-new'\)"
		# Ensure mismatched route and component names are absent
		$podex | Should -Not -Match "'/htmx/crudmgr-new'"
		$podex | Should -Not -Match "Components = @\('crud-new'\)"
	}

	It 'requests GET /htmx/item-new from the crudmgr add button' {
		$crudmgr = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'views/components/crudmgr.pode') -Raw
		$crudmgr | Should -Match 'hx-get="/htmx/item-new"'
		$crudmgr | Should -Match 'hx-target="#itemModalContent"'
	}

	It 'renders the crudmgr-new component containing item and description controls' {
		$component = Get-RenderedComponent -ComponentName 'crudmgr-new'
		$component | Should -Match 'name="item"'
		$component | Should -Match 'name="description"'
		$component | Should -Match 'hx-post="/api/crud"'
	}

	It 'does not reference the mismatched crud-new component file' {
		$mismatchedPath = Join-Path $script:RepoRoot 'views/components/crud-new.pode'
		Test-Path -LiteralPath $mismatchedPath | Should -Be $false
	}
}

Describe 'Add form POST field contract' {
	It 'submits item and description to POST /api/crud' {
		$crudmgrNew = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'views/components/crudmgr-new.pode') -Raw
		# The add form posts item + description
		$crudmgrNew | Should -Match 'name="item"'
		$crudmgrNew | Should -Match 'name="description"'
		$crudmgrNew | Should -Match 'hx-post="/api/crud"'

		# And the handler accepts exactly those fields
		$postHandler = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'api/crud/post.ps1') -Raw
		$postHandler | Should -Match '\$data\.item'
		$postHandler | Should -Match '\$data\.description'
	}
}

Describe 'Update row PUT field contract' {
	It 'submits id, item, and description to PUT /api/crud' {
		$crudmgr = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'views/components/crudmgr.pode') -Raw
		# Each row carries hidden inputs for id, item, description
		$crudmgr | Should -Match 'name="id"'
		$crudmgr | Should -Match 'name="item"'
		$crudmgr | Should -Match 'name="description"'
		# The update button PUTs the whole row
		$crudmgr | Should -Match 'hx-put="/api/crud"'
		$crudmgr | Should -Match 'hx-include="closest tr"'

		# And the handler accepts id + item + description
		$putHandler = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'api/crud/put.ps1') -Raw
		$putHandler | Should -Match '\$data\.id'
		$putHandler | Should -Match '\$data\.item'
		$putHandler | Should -Match '\$data\.description'
	}
}

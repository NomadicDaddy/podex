BeforeAll {
	$script:RepoRoot = (Resolve-Path "$PSScriptRoot/..").Path

	function Get-FileContent {
		param([string]$RelativePath)
		return Get-Content -LiteralPath (Join-Path $script:RepoRoot $RelativePath) -Raw
	}

	function Get-RenderedComponent {
		param([string]$ComponentName)

		$componentPath = Join-Path $script:RepoRoot "views/components/$ComponentName.pode"
		return Get-Content -LiteralPath $componentPath -Raw
	}
}

Describe 'Modal wrapper consolidation' {
	It 'keeps #itemModal and #itemModalContent only in crudmgr.pode' {
		$crudmgr = Get-FileContent 'views/components/crudmgr.pode'
		$crudmgr | Should -Match 'id="itemModal"'
		$crudmgr | Should -Match 'id="itemModalContent"'

		# crudmgr-new.pode must NOT contain a second modal wrapper
		$crudmgrNew = Get-RenderedComponent -ComponentName 'crudmgr-new'
		$crudmgrNew | Should -Not -Match 'id="itemModal"'
		$crudmgrNew | Should -Not -Match 'id="itemModalContent"'
	}

	It 'does not render a second overlay or dialog role from crudmgr-new' {
		$crudmgrNew = Get-RenderedComponent -ComponentName 'crudmgr-new'
		$crudmgrNew | Should -Not -Match 'role="dialog"'
		$crudmgrNew | Should -Not -Match 'aria-modal="true"'
		$crudmgrNew | Should -Not -Match 'bg-black'
	}
}

Describe 'External controller loading' {
	It 'compiles src/crudmgr.ts through build-assets.ts' {
		Test-Path -LiteralPath (Join-Path $script:RepoRoot 'src/crudmgr.ts') | Should -Be $true

		$buildAssets = Get-FileContent 'scripts/build-assets.ts'
		$buildAssets | Should -Match "src/crudmgr\.ts.*public/js/crudmgr\.js"
	}

	It 'loads the controller script from views/layouts/main.pode' {
		$main = Get-FileContent 'views/layouts/main.pode'
		$main | Should -Match 'src="/public/js/crudmgr.js"'
	}

	It 'includes public/js/crudmgr.js in the release manifest' {
		$manifest = Get-FileContent 'release-manifest.json'
		$manifest | Should -Match '"public/js/crudmgr.js"'
	}

	It 'removes the inline window.showModal/window.closeModal script from crudmgr.pode' {
		$crudmgr = Get-FileContent 'views/components/crudmgr.pode'
		$crudmgr | Should -Not -Match 'function showModal'
		$crudmgr | Should -Not -Match 'function hideModal'
		$crudmgr | Should -Not -Match "addEventListener\('closeModal'"
	}

	It 'removes the _= hyperscript attribute from the Add Item button' {
		$crudmgr = Get-FileContent 'views/components/crudmgr.pode'
		$crudmgr | Should -Not -Match '_="'
	}
}

Describe 'Mutation success/failure event guards' {
	It 'listens for htmx:after:request on CRUD pages' {
		$controller = Get-FileContent 'src/crudmgr.ts'
		$controller | Should -Match "htmx:after:request"
		# The controller initializes only when #crud exists (page scope guard)
		$controller | Should -Match "getElementById\('crud'\)"
		$controller | Should -Match "document.body.addEventListener\('htmx:after:request'"
	}

	It 'closes the modal only after a successful create' {
		$controller = Get-FileContent 'src/crudmgr.ts'
		$controller | Should -Match 'closeModal'
		$controller | Should -Match 'isSuccessfulCreate'
		$controller | Should -Match "method\.toUpperCase\(\) === 'POST'"
		$controller | Should -Match 'status >= 200'
		$controller | Should -Match 'status < 300'
		$controller | Should -Not -Match 'dispatchItemChanged'
	}

	It 'removes inline hx-on::after:request triggers from Update/Delete buttons' {
		$crudmgr = Get-FileContent 'views/components/crud-list.pode'
		$crudmgr | Should -Not -Match "hx-on::after:request"
	}
}

Describe 'Failed POST error retention' {
	It 'routes renderable 4xx and 5xx fragments into #itemModalError' {
		$crudmgrNew = Get-RenderedComponent -ComponentName 'crudmgr-new'
		$crudStyles = Get-FileContent 'src/styles/crud.css'
		$crudmgrNew | Should -Match 'id="itemModalError"'
		$crudmgrNew | Should -Match 'role="alert"'
		$crudmgrNew | Should -Match 'hx-status:4xx="target:#itemModalError swap:innerHTML"'
		$crudmgrNew | Should -Match 'hx-status:5xx="target:#itemModalError swap:innerHTML"'
		$crudmgrNew | Should -Match 'class="alert"'
		$crudStyles | Should -Match '\.alert:empty'
	}
}

Describe 'Dialog accessibility attributes' {
	It 'gives #itemModal role=dialog, aria-modal, and aria-labelledby' {
		$crudmgr = Get-FileContent 'views/components/crudmgr.pode'
		$crudmgr | Should -Match 'role="dialog"'
		$crudmgr | Should -Match 'aria-modal="true"'
		$crudmgr | Should -Match 'aria-labelledby="itemModalTitle"'
	}

	It 'provides the itemModalTitle heading inside crudmgr-new' {
		$crudmgrNew = Get-RenderedComponent -ComponentName 'crudmgr-new'
		$crudmgrNew | Should -Match 'id="itemModalTitle"'
	}

	It 'implements initial focus on the item name field' {
		$controller = Get-FileContent 'src/crudmgr.ts'
		$controller | Should -Match 'input\[name="item"\]'
		$controller | Should -Match '\.focus\(\)'
	}

	It 'implements a Tab/Shift+Tab focus loop' {
		$controller = Get-FileContent 'src/crudmgr.ts'
		$controller | Should -Match 'function trapFocus'
		$controller | Should -Match "event.key !== 'Tab'"
		$controller | Should -Match 'event.shiftKey'
	}

	It 'implements Escape and backdrop close' {
		$controller = Get-FileContent 'src/crudmgr.ts'
		$controller | Should -Match "event.key === 'Escape'"
		$controller | Should -Match 'target === modal'
	}

	It 'returns focus to the Add Item button on close' {
		$controller = Get-FileContent 'src/crudmgr.ts'
		$controller | Should -Match 'lastFocused'
		$controller | Should -Match 'lastFocused.focus'
	}
}

Describe 'Close control labeling' {
	It 'gives the close button an aria-label' {
		$crudmgrNew = Get-RenderedComponent -ComponentName 'crudmgr-new'
		$crudmgrNew | Should -Match 'aria-label="Close add item dialog"'
	}

	It 'marks the close button SVG aria-hidden=true' {
		$crudmgrNew = Get-RenderedComponent -ComponentName 'crudmgr-new'
		# The close button SVG must carry aria-hidden
		$crudmgrNew | Should -Match 'aria-hidden="true"'
	}

	It 'marks the close button and Cancel with data-close-modal' {
		$crudmgrNew = Get-RenderedComponent -ComponentName 'crudmgr-new'
		$closeButtons = ([regex]::Matches($crudmgrNew, 'data-close-modal')).Count
		$closeButtons | Should -BeGreaterOrEqual 2
	}

	It 'accepts SVG descendants as delegated close-click targets' {
		$controller = Get-FileContent 'src/crudmgr.ts'
		$controller | Should -Match 'if \(!\(target instanceof Element\)\) return'
		$controller | Should -Not -Match 'if \(!\(target instanceof HTMLElement\)\) return'
	}
}

Describe 'Native CSS modal state' {
	It 'uses aria-hidden as the single modal visibility contract' {
		$crudmgr = Get-FileContent 'views/components/crudmgr.pode'
		$controller = Get-FileContent 'src/crudmgr.ts'
		$modalStyles = Get-FileContent 'src/styles/modal.css'

		$crudmgr | Should -Match 'class="modal-backdrop"'
		$controller | Should -Not -Match "classList\.(add|remove)\('(hidden|flex)'\)"
		$modalStyles | Should -Match "\.modal-backdrop\[aria-hidden='true'\]"
	}
}

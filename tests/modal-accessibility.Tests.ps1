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
	It 'adds src/crudmgr.js and ships it via build-assets.mjs' {
		Test-Path -LiteralPath (Join-Path $script:RepoRoot 'src/crudmgr.js') | Should -Be $true

		$buildAssets = Get-FileContent 'scripts/build-assets.mjs'
		$buildAssets | Should -Match "src/crudmgr\.js.*public/js/crudmgr\.js"
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
	It 'listens for htmx:after:request scoped to #crud in the controller' {
		$controller = Get-FileContent 'src/crudmgr.js'
		$controller | Should -Match "htmx:after:request"
		# The controller initializes only when #crud exists (page scope guard)
		$controller | Should -Match "getElementById\('crud'\)"
		# The listener is on document.body so events from both the modal form and
		# the inline table controls can reach it.
		$controller | Should -Match "document.body.addEventListener\('htmx:after:request'"
	}

	It 'guards close/reset/dispatch behind a success check' {
		$controller = Get-FileContent 'src/crudmgr.js'
		# Success path closes the modal and dispatches itemChanged
		$controller | Should -Match 'closeModal'
		$controller | Should -Match 'dispatchItemChanged'
		# The success predicate must exist
		$controller | Should -Match 'isSuccessfulMutation'
		# A 2xx status range check
		$controller | Should -Match 'status >= 200'
		$controller | Should -Match 'status < 300'
	}

	It 'removes inline hx-on::after:request triggers from Update/Delete buttons' {
		$crudmgr = Get-FileContent 'views/components/crudmgr.pode'
		$crudmgr | Should -Not -Match "hx-on::after:request"
	}
}

Describe 'Failed POST error retention' {
	It 'renders the response message into #itemModalError role=alert' {
		$crudmgrNew = Get-RenderedComponent -ComponentName 'crudmgr-new'
		$crudmgrNew | Should -Match 'id="itemModalError"'
		$crudmgrNew | Should -Match 'role="alert"'
	}

	It 'extracts { message } from the response body in the controller' {
		$controller = Get-FileContent 'src/crudmgr.js'
		$controller | Should -Match 'function extractMessage'
		$controller | Should -Match "\.message"
	}

	It 'keeps the modal open and calls showError on a failed POST' {
		$controller = Get-FileContent 'src/crudmgr.js'
		$controller | Should -Match 'function showError'
		$controller | Should -Match 'Keep the modal open'
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
		$controller = Get-FileContent 'src/crudmgr.js'
		$controller | Should -Match 'input\[name="item"\]'
		$controller | Should -Match '\.focus\(\)'
	}

	It 'implements a Tab/Shift+Tab focus loop' {
		$controller = Get-FileContent 'src/crudmgr.js'
		$controller | Should -Match 'function trapFocus'
		$controller | Should -Match "event.key !== 'Tab'"
		$controller | Should -Match 'event.shiftKey'
	}

	It 'implements Escape and backdrop close' {
		$controller = Get-FileContent 'src/crudmgr.js'
		$controller | Should -Match "event.key === 'Escape'"
		$controller | Should -Match 'target === modal'
	}

	It 'returns focus to the Add Item button on close' {
		$controller = Get-FileContent 'src/crudmgr.js'
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
}

Describe 'Tailwind 4 overlay class' {
	It 'uses bg-black/50 instead of bg-opacity-50 on the modal overlay' {
		$crudmgr = Get-FileContent 'views/components/crudmgr.pode'
		$crudmgr | Should -Match 'bg-black/50'
		$crudmgr | Should -Not -Match 'bg-opacity-50'
	}
}

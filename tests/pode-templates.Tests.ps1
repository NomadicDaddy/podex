# Regression gate for Pode (.pode) template compilation.
#
# Pode's view engine renders .pode files by escaping double-quotes and wrapping
# the content in `return "..."`, then compiling the result with
# [scriptblock]::Create. A template that breaks that escaping shape (an
# unbalanced sub-expression, a stray backtick, an unterminated string) fails to
# compile only at request time, producing a 500. This suite compiles every
# checked-in .pode template through the same escaping shape so malformed
# templates fail at test time instead.

BeforeAll {
	$script:RepoRoot = (Resolve-Path "$PSScriptRoot/..").Path

	# Reproduce Pode 2.13's ConvertFrom-PodeFile escaping shape locally so the
	# test does not depend on a private function. The shape is:
	#   param($data)`nreturn "<content with " replaced by `">"
	# (the no-data branch omits the param clause).
	function ConvertTo-PodeScriptBlock {
		param(
			[Parameter(Mandatory = $true)]
			[string]$Content,

			[switch]$WithData
		)

		if ($WithData) {
			$wrapped = "param(`$data)`nreturn `"$($Content -replace '"', '``"')`""
		} else {
			$wrapped = "return `"$($Content -replace '"', '``"')`""
		}

		return [scriptblock]::Create($wrapped)
	}
}

Describe 'Pode template compilation' {
	It 'discovers every views/**/*.pode and errors/**/*.pode template' {
		$viewRoot = Join-Path $script:RepoRoot 'views'
		$errorRoot = Join-Path $script:RepoRoot 'errors'
		$viewTemplates = @(Get-ChildItem -LiteralPath $viewRoot -Recurse -File -Filter '*.pode')
		$errorTemplates = @(Get-ChildItem -LiteralPath $errorRoot -Recurse -File -Filter '*.pode')
		$templates = @($viewTemplates + $errorTemplates)
		$templates.Count | Should -BeGreaterThan 0
	}

	It 'compiles each checked-in template with the Pode escaping shape' {
		$viewRoot = Join-Path $script:RepoRoot 'views'
		$errorRoot = Join-Path $script:RepoRoot 'errors'
		$viewTemplates = @(Get-ChildItem -LiteralPath $viewRoot -Recurse -File -Filter '*.pode')
		$errorTemplates = @(Get-ChildItem -LiteralPath $errorRoot -Recurse -File -Filter '*.pode')
		$templates = @($viewTemplates + $errorTemplates) | Sort-Object -Property FullName
		$failed = @()
		foreach ($tpl in $templates) {
			$content = Get-Content -Raw -LiteralPath $tpl.FullName
			try {
				ConvertTo-PodeScriptBlock -Content $content -WithData -ErrorAction Stop | Out-Null
			} catch {
				$failed += "$($tpl.Name): $($_.Exception.Message.Split([Environment]::NewLine)[0])"
			}
		}
		if ($failed.Count -gt 0) {
			Write-Output ($failed -join "`n")
		}
		$failed.Count | Should -Be 0 -Because 'every template must compile via the Pode escaping shape'
	}
}

Describe 'Pode template escaping shape rejects malformed templates' {
	It 'fails to compile a template with an unterminated sub-expression' {
		$malformed = '<div>$($data.Title</div>'
		{ ConvertTo-PodeScriptBlock -Content $malformed -WithData } |
			Should -Throw
	}

	It 'compiles a valid minimal template' {
		$valid = '<p>$($data.Title ;)</p>'
		{ ConvertTo-PodeScriptBlock -Content $valid -WithData } |
			Should -Not -Throw
	}
}

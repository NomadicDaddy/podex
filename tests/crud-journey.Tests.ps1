BeforeAll {
	Import-Module -Name PSSQLite -MaximumVersion 1.99.99 -Force

	$script:RepoRoot = (Resolve-Path "$PSScriptRoot/..").Path
	$script:Port = 9800 + ([Math]::Abs($PID) % 100)
	$script:BaseUrl = "http://localhost:$($script:Port)"
	$script:Database = Join-Path $TestDrive 'crud-journey.db'
	$initSql = Get-Content -LiteralPath (
		Join-Path $script:RepoRoot 'api/debug/init.sql'
	) -Raw
	Invoke-SqliteQuery -DataSource $script:Database -Query $initSql -ErrorAction Stop

	$script:Process = Start-Process -FilePath 'pwsh' `
		-ArgumentList @(
		'-NoLogo'
		'-NoProfile'
		'-ExecutionPolicy'
		'Bypass'
		'-File'
		(Join-Path $script:RepoRoot 'podex.ps1')
	) `
		-WorkingDirectory $script:RepoRoot `
		-Environment @{
		PODEX_DB_FILE = $script:Database
		PODEX_HTTP_PORT = [string]$script:Port
	} `
		-WindowStyle Hidden `
		-PassThru

	$ready = $false
	for ($attempt = 0; $attempt -lt 60; $attempt++) {
		if ($script:Process.HasExited) {
			break
		}
		try {
			Invoke-WebRequest -Uri "$($script:BaseUrl)/health" -UseBasicParsing -TimeoutSec 2 |
				Out-Null
			$ready = $true
			break
		} catch {
			Start-Sleep -Milliseconds 500
		}
	}
	if (-not $ready) {
		throw "Podex CRUD journey server did not start on port $($script:Port)."
	}

	function Invoke-CrudRequest {
		param(
			[Parameter(Mandatory)]
			[string]$Path,
			[ValidateSet('Get', 'Post', 'Put', 'Delete')]
			[string]$Method = 'Get',
			[string]$Body = ''
		)

		$request = @{
			Headers = @{ 'HX-Request' = 'true' }
			Method = $Method
			SkipHttpErrorCheck = $true
			TimeoutSec = 10
			Uri = "$($script:BaseUrl)$Path"
			UseBasicParsing = $true
		}
		if ($Body) {
			$request.Body = $Body
			$request.ContentType = 'application/x-www-form-urlencoded'
		}
		return Invoke-WebRequest @request
	}
}

AfterAll {
	if ($script:Process -and -not $script:Process.HasExited) {
		Stop-Process -Id $script:Process.Id -Force -ErrorAction SilentlyContinue
	}
}

Describe 'Server-rendered CRUD HTTP journey' {
	It 'renders the initial item list without browser templates or htmx extensions' {
		$response = Invoke-WebRequest `
			-Uri "$($script:BaseUrl)/crudmgr" `
			-UseBasicParsing `
			-TimeoutSec 10

		$response.StatusCode | Should -Be 200
		$response.Content | Should -Match 'id="crud"'
		$response.Content | Should -Match 'name="item"'
		$response.Content | Should -Not -Match 'mustache-template'
		$response.Content | Should -Not -Match '\bhx-ext='
		$response.Content | Should -Not -Match 'client-side-templates\.js'
		$response.Content | Should -Not -Match 'json-enc\.js'
		$response.Content | Should -Not -Match 'mustache\.js'
	}

	It 'preserves the JSON response contract for ordinary API clients' {
		$response = Invoke-WebRequest `
			-Uri "$($script:BaseUrl)/api/crud?page=1&pageSize=5" `
			-UseBasicParsing `
			-TimeoutSec 10
		$body = $response.Content | ConvertFrom-Json

		$response.StatusCode | Should -Be 200
		$response.Headers['Content-Type'] | Should -Match 'application/json'
		$body.rows.Count | Should -Be 5
		$body.totalItems | Should -BeGreaterThan 10

		$created = Invoke-WebRequest `
			-Uri "$($script:BaseUrl)/api/crud" `
			-Method Post `
			-ContentType 'application/json' `
			-Body '{"item":"JSON client item","description":"Created through JSON"}' `
			-SkipHttpErrorCheck `
			-UseBasicParsing `
			-TimeoutSec 10
		$createdBody = $created.Content | ConvertFrom-Json

		$created.StatusCode | Should -Be 201
		$created.Headers['Content-Type'] | Should -Match 'application/json'
		$createdBody.message | Should -Be 'Item created successfully'
		$createdBody.item.item | Should -Be 'JSON client item'

		$deleted = Invoke-WebRequest `
			-Uri "$($script:BaseUrl)/api/crud?id=$($createdBody.item.id)" `
			-Method Delete `
			-SkipHttpErrorCheck `
			-UseBasicParsing `
			-TimeoutSec 10
		$deleted.StatusCode | Should -Be 200
		($deleted.Content | ConvertFrom-Json).id | Should -Be $createdBody.item.id
	}

	It 'returns an HTML list fragment for an htmx GET request' {
		$response = Invoke-CrudRequest -Path '/api/crud?page=1&pageSize=5'

		$response.StatusCode | Should -Be 200
		$response.Headers['Content-Type'] | Should -Match 'text/html'
		$response.Content | Should -Match '^\s*<div id="crud">'
		$response.Content | Should -Match 'hx-swap="outerMorph"'
	}

	It 'creates, updates, searches, and deletes through form-encoded htmx requests' {
		$invalid = Invoke-CrudRequest `
			-Path '/api/crud' `
			-Method Post `
			-Body 'item=+++&description=Valid'
		$invalid.StatusCode | Should -Be 422
		$invalid.Content | Should -Match 'Missing required field: item'

		$created = Invoke-CrudRequest `
			-Path '/api/crud' `
			-Method Post `
			-Body 'item=Journey+item&description=Created+from+a+form&page=1'
		$created.StatusCode | Should -Be 200
		$created.Content | Should -Match 'Journey item'
		$idMatch = [regex]::Match(
			$created.Content,
			'(?s)<tr data-id="(\d+)".*?value="Journey item"'
		)
		$idMatch.Success | Should -BeTrue
		$itemId = [int]$idMatch.Groups[1].Value

		$updated = Invoke-CrudRequest `
			-Path '/api/crud' `
			-Method Put `
			-Body "id=$itemId&item=Journey+updated&description=Updated+from+a+form&page=1"
		$updated.StatusCode | Should -Be 200
		$updated.Content | Should -Match 'Journey updated'
		$updated.Content | Should -Not -Match 'Journey item'

		$searched = Invoke-CrudRequest -Path '/api/crud?search=Journey%20updated'
		$searched.StatusCode | Should -Be 200
		$searched.Content | Should -Match 'Journey updated'
		$searched.Content | Should -Match 'Showing\s+<strong>1-1</strong>'

		$deleted = Invoke-CrudRequest `
			-Path "/api/crud?id=$itemId" `
			-Method Delete `
			-Body 'search=Journey+updated&page=1'
		$deleted.StatusCode | Should -Be 200
		$deleted.Content | Should -Match 'No items found'
		$deleted.Content | Should -Not -Match 'Updated from a form'
	}

	It 'HTML-encodes stored values before rendering them into attributes' {
		$response = Invoke-CrudRequest `
			-Path '/api/crud' `
			-Method Post `
			-Body 'item=%3Cscript%3Ealert%281%29%3C%2Fscript%3E&description=%22quoted%22'

		$response.StatusCode | Should -Be 200
		$response.Content | Should -Match '&lt;script&gt;alert\(1\)&lt;/script&gt;'
		$response.Content | Should -Match '&quot;quoted&quot;'
		$response.Content | Should -Not -Match '<script>alert'
	}
}

BeforeAll {
	Import-Module -Name PSSQLite -MaximumVersion 1.99.99 -Force

	$script:DatabasePath = Join-Path $TestDrive 'podex-test.db'
	$script:Response = $null

	function Get-PodeConfig {
		return @{
			Podex = @{
				DBFile = $script:DatabasePath
			}
		}
	}

	function Write-FormattedLog {
		param([string]$tag, [string]$log)
	}

	function Write-PodeJsonResponse {
		param(
			[Parameter(ValueFromPipeline)]$Value,
			[int]$StatusCode
		)

		$script:Response = @{
			StatusCode = $StatusCode
			Value = $Value
		}
	}

	function Invoke-CrudHandler {
		param(
			[ValidateSet('GET', 'POST', 'PUT', 'DELETE')]
			[string]$Method,
			[hashtable]$Data = @{},
			[hashtable]$Query = @{}
		)

		$script:Response = $null
		$script:WebEvent = @{
			Data = $Data
			Method = $Method
			Path = '/api/crud'
			Query = $Query
			Request = @{
				Headers = @{}
			}
		}

		$handlerPath = Join-Path $PSScriptRoot "../api/crud/$($Method.ToLower()).ps1"
		$handler = . $handlerPath
		& $handler

		return $script:Response
	}
}

Describe 'Canonical CRUD item model' {
	BeforeEach {
		if (Test-Path -LiteralPath $script:DatabasePath) {
			Remove-Item -LiteralPath $script:DatabasePath -Force
		}

		$initSql = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../api/debug/init.sql') -Raw
		Invoke-SqliteQuery -DataSource $script:DatabasePath -Query $initSql
	}

	It 'supports GET, POST, PUT, and DELETE against a freshly initialized database' {
		$postResponse = Invoke-CrudHandler -Method POST -Data @{
			item = ' Test item '
			description = ' Test description '
		}

		$postResponse.StatusCode | Should -Be 201
		$created = Invoke-SqliteQuery -DataSource $script:DatabasePath -Query "SELECT * FROM [items] WHERE [item] = 'Test item';" -As PSObject
		$created.item | Should -Be 'Test item'
		$created.description | Should -Be 'Test description'

		$getResponse = Invoke-CrudHandler -Method GET -Query @{ search = 'Test item' }
		$getResponse.StatusCode | Should -Be 200
		$getResponse.Value.rows.Count | Should -Be 1
		$getResponse.Value.rows[0].item | Should -Be 'Test item'
		$getResponse.Value.rows[0].description | Should -Be 'Test description'

		$putResponse = Invoke-CrudHandler -Method PUT -Data @{
			id = $created.id
			item = 'Updated item'
			description = 'Updated description'
		}

		$putResponse.StatusCode | Should -Be 200
		$updated = Invoke-SqliteQuery -DataSource $script:DatabasePath -Query 'SELECT * FROM [items] WHERE [id] = @id;' -SqlParameters @{ id = $created.id } -As PSObject
		$updated.item | Should -Be 'Updated item'
		$updated.description | Should -Be 'Updated description'

		$deleteResponse = Invoke-CrudHandler -Method DELETE -Query @{ id = $created.id }
		$deleteResponse.StatusCode | Should -Be 200
		$remaining = Invoke-SqliteQuery -DataSource $script:DatabasePath -Query 'SELECT COUNT(*) AS [count] FROM [items] WHERE [id] = @id;' -SqlParameters @{ id = $created.id } -As PSObject
		$remaining.count | Should -Be 0
	}
}

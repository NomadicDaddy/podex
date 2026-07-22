BeforeAll {
	Import-Module -Name PSSQLite -MaximumVersion 1.99.99 -Force

	$script:DatabasePath = Join-Path $TestDrive 'podex-test.db'
	$script:Response = $null
	$script:DebugEnabled = $false

	function Get-PodeConfig {
		return @{
			Podex = @{
				DBFile = $script:DatabasePath
				Debug = $script:DebugEnabled
			}
		}
	}

	function Write-FormattedLog {
		param([string]$Tag, [string]$Log)

		$null = $Tag
		$null = $Log
	}

	function Write-PodeJsonResponse {
		param(
			[Parameter(ValueFromPipeline)]$Value,
			[int]$StatusCode
		)

		process {
			$script:Response = @{
				StatusCode = $StatusCode
				Value = $Value
			}
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

	It 'reports the full matching total and navigation metadata on page 1' {
		$seeded = Invoke-SqliteQuery -DataSource $script:DatabasePath -Query 'SELECT COUNT(*) AS [count] FROM [items];' -As PSObject
		$seeded.count | Should -BeGreaterThan 10

		$response = Invoke-CrudHandler -Method GET -Query @{ page = '1'; pageSize = '10' }

		$response.StatusCode | Should -Be 200
		$response.Value.totalItems | Should -Be $seeded.count
		$response.Value.rows.Count | Should -Be 10
		$response.Value.startIndex | Should -Be 1
		$response.Value.endIndex | Should -Be 10
		$response.Value.currentPage | Should -Be 1
		$response.Value.hasPreviousPage | Should -BeFalse
		$response.Value.hasNextPage | Should -BeTrue
		$response.Value.previousPage | Should -BeNullOrEmpty
		$response.Value.nextPage | Should -Be 2
		$response.Value.pages.Count | Should -Be ([Math]::Ceiling($seeded.count / 10))
		$response.Value.pages[0].isActive | Should -BeTrue
		$response.Value.pages[1].isActive | Should -BeFalse
	}

	It 'reports the full matching total and navigation metadata on page 2' {
		$seeded = Invoke-SqliteQuery -DataSource $script:DatabasePath -Query 'SELECT COUNT(*) AS [count] FROM [items];' -As PSObject
		$seeded.count | Should -BeGreaterThan 10

		$response = Invoke-CrudHandler -Method GET -Query @{ page = '2'; pageSize = '10' }

		$response.StatusCode | Should -Be 200
		$response.Value.totalItems | Should -Be $seeded.count
		$response.Value.rows.Count | Should -Be 10
		$response.Value.startIndex | Should -Be 11
		$response.Value.endIndex | Should -Be 20
		$response.Value.currentPage | Should -Be 2
		$response.Value.hasPreviousPage | Should -BeTrue
		$response.Value.hasNextPage | Should -BeTrue
		$response.Value.previousPage | Should -Be 1
		$response.Value.nextPage | Should -Be 3
		$response.Value.pages[1].isActive | Should -BeTrue
	}

	It 'reports the filtered matching total rather than the page length for a search' {
		$search = 'Item 3'
		$matching = Invoke-SqliteQuery -DataSource $script:DatabasePath -Query 'SELECT COUNT(*) AS [count] FROM [items] WHERE ([item] LIKE @search OR [description] LIKE @search);' -SqlParameters @{ search = "%$search%" } -As PSObject
		$matching.count | Should -BeGreaterThan 1

		$response = Invoke-CrudHandler -Method GET -Query @{ search = $search; page = '1'; pageSize = '5' }

		$response.StatusCode | Should -Be 200
		$response.Value.totalItems | Should -Be $matching.count
		$response.Value.rows.Count | Should -Be 5
		$response.Value.totalItems | Should -BeGreaterThan $response.Value.rows.Count
		$response.Value.hasNextPage | Should -BeTrue
		$response.Value.nextPage | Should -Be 2
		$response.Value.pages.Count | Should -Be ([Math]::Ceiling($matching.count / 5))
	}

	It 'normalizes missing paging inputs to page 1 / pageSize 10' {
		$seeded = Invoke-SqliteQuery -DataSource $script:DatabasePath -Query 'SELECT COUNT(*) AS [count] FROM [items];' -As PSObject
		$seeded.count | Should -BeGreaterThan 10

		$response = Invoke-CrudHandler -Method GET -Query @{}

		$response.StatusCode | Should -Be 200
		$response.Value.currentPage | Should -Be 1
		$response.Value.rows.Count | Should -Be 10
		$response.Value.totalItems | Should -Be $seeded.count
	}

	It 'normalizes non-numeric paging inputs to page 1 / pageSize 10' {
		$seeded = Invoke-SqliteQuery -DataSource $script:DatabasePath -Query 'SELECT COUNT(*) AS [count] FROM [items];' -As PSObject
		$seeded.count | Should -BeGreaterThan 10

		$response = Invoke-CrudHandler -Method GET -Query @{ page = 'abc'; pageSize = 'xyz' }

		$response.StatusCode | Should -Be 200
		$response.Value.currentPage | Should -Be 1
		$response.Value.rows.Count | Should -Be 10
		$response.Value.totalItems | Should -Be $seeded.count
	}

	It 'normalizes zero paging inputs to page 1 / pageSize 10' {
		$seeded = Invoke-SqliteQuery -DataSource $script:DatabasePath -Query 'SELECT COUNT(*) AS [count] FROM [items];' -As PSObject
		$seeded.count | Should -BeGreaterThan 10

		$response = Invoke-CrudHandler -Method GET -Query @{ page = '0'; pageSize = '0' }

		$response.StatusCode | Should -Be 200
		$response.Value.currentPage | Should -Be 1
		$response.Value.rows.Count | Should -Be 10
		$response.Value.totalItems | Should -Be $seeded.count
	}

	It 'normalizes negative paging inputs to page 1 / pageSize 10' {
		$seeded = Invoke-SqliteQuery -DataSource $script:DatabasePath -Query 'SELECT COUNT(*) AS [count] FROM [items];' -As PSObject
		$seeded.count | Should -BeGreaterThan 10

		$response = Invoke-CrudHandler -Method GET -Query @{ page = '-1'; pageSize = '-5' }

		$response.StatusCode | Should -Be 200
		$response.Value.currentPage | Should -Be 1
		$response.Value.rows.Count | Should -Be 10
		$response.Value.totalItems | Should -Be $seeded.count
	}

	It 'caps pageSize greater than 100 at 100 and returns HTTP 200' {
		$seeded = Invoke-SqliteQuery -DataSource $script:DatabasePath -Query 'SELECT COUNT(*) AS [count] FROM [items];' -As PSObject
		$seeded.count | Should -BeGreaterThan 10

		$response = Invoke-CrudHandler -Method GET -Query @{ page = '1'; pageSize = '500' }

		$response.StatusCode | Should -Be 200
		$response.Value.currentPage | Should -Be 1
		# pageSize is capped at 100; the seed has 35 rows so all fit on one page
		$response.Value.rows.Count | Should -Be $seeded.count
		$response.Value.totalItems | Should -Be $seeded.count
	}

	It 'does not write a response snapshot into the source tree when debug mode is enabled' {
		$handlerDir = Join-Path $PSScriptRoot '../api/crud'
		$snapshotPath = Join-Path $handlerDir 'get.json'

		$script:DebugEnabled = $true
		try {
			$response = Invoke-CrudHandler -Method GET -Query @{ page = '1'; pageSize = '10' }

			$response.StatusCode | Should -Be 200
			$response.Value.rows.Count | Should -BeGreaterThan 0

			# No snapshot file is created beneath api/crud
			$snapshotPath | Should -Not -Exist

			# No *.json file is created beneath the test working directory either
			$newJson = @(Get-ChildItem -Path $TestDrive -Filter '*.json' -Recurse -ErrorAction SilentlyContinue)
			$newJson.Count | Should -Be 0
		} finally {
			$script:DebugEnabled = $false
		}
	}
}

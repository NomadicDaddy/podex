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
		$postResponse.Value.message | Should -Be 'Item created successfully'
		# POST must return the created record with the canonical fields and trimmed values
		$postResponse.Value.item.id | Should -BeGreaterThan 0
		$postResponse.Value.item.item | Should -Be 'Test item'
		$postResponse.Value.item.description | Should -Be 'Test description'
		$postResponse.Value.item.created_at | Should -Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$'
		$postResponse.Value.item.updated_at | Should -Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$'

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
		$putResponse.Value.message | Should -Be 'Item updated successfully'
		$putResponse.Value.id | Should -Be $created.id
		$updated = Invoke-SqliteQuery -DataSource $script:DatabasePath -Query 'SELECT * FROM [items] WHERE [id] = @id;' -SqlParameters @{ id = $created.id } -As PSObject
		$updated.item | Should -Be 'Updated item'
		$updated.description | Should -Be 'Updated description'

		$deleteResponse = Invoke-CrudHandler -Method DELETE -Query @{ id = $created.id }
		$deleteResponse.StatusCode | Should -Be 200
		$deleteResponse.Value.message | Should -Be 'Item deleted successfully'
		$deleteResponse.Value.id | Should -Be $created.id
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

	It 'returns rows as an empty array when no items match the search' {
		$response = Invoke-CrudHandler -Method GET -Query @{ search = 'ZZZZNOTFOUNDZZZZ' }

		$response.StatusCode | Should -Be 200
		$response.Value.rows.Count | Should -Be 0
		$response.Value.totalItems | Should -Be 0
		$response.Value.startIndex | Should -Be 0
		$response.Value.endIndex | Should -Be 0
		$response.Value.hasPreviousPage | Should -BeFalse
		$response.Value.hasNextPage | Should -BeFalse
		$response.Value.previousPage | Should -BeNullOrEmpty
		$response.Value.nextPage | Should -BeNullOrEmpty
		$response.Value.pages.Count | Should -Be 0
	}

	It 'returns rows as an empty array when the database has no items' {
		Invoke-SqliteQuery -DataSource $script:DatabasePath -Query 'DELETE FROM [items];'

		$response = Invoke-CrudHandler -Method GET -Query @{}

		$response.StatusCode | Should -Be 200
		$response.Value.rows.Count | Should -Be 0
		$response.Value.totalItems | Should -Be 0
	}

	It 'returns created_at and updated_at as UTC RFC 3339 strings and created_at_display for views' {
		$postResponse = Invoke-CrudHandler -Method POST -Data @{
			item = 'Timestamp item'
			description = 'For timestamp verification'
		}

		$postResponse.StatusCode | Should -Be 201
		$postResponse.Value.item.created_at | Should -Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$'
		$postResponse.Value.item.updated_at | Should -Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$'

		$response = Invoke-CrudHandler -Method GET -Query @{ search = 'Timestamp item' }

		$response.StatusCode | Should -Be 200
		$response.Value.rows.Count | Should -Be 1
		$response.Value.rows[0].created_at | Should -Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$'
		$response.Value.rows[0].updated_at | Should -Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$'
		$response.Value.rows[0].created_at_display | Should -Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2} UTC$'
	}

	It 'returns 404 when updating a non-existent item' {
		$putResponse = Invoke-CrudHandler -Method PUT -Data @{
			id = 999999
			item = 'Non-existent'
			description = 'Should not be found'
		}

		$putResponse.StatusCode | Should -Be 404
		$putResponse.Value.message | Should -Be 'Item not found'
	}

	It 'returns 404 when deleting a non-existent item' {
		$deleteResponse = Invoke-CrudHandler -Method DELETE -Query @{ id = 999999 }

		$deleteResponse.StatusCode | Should -Be 404
		$deleteResponse.Value.message | Should -Be 'Item not found'
	}

	It 'returns 400 when deleting with a missing id' {
		$deleteResponse = Invoke-CrudHandler -Method DELETE -Query @{}

		$deleteResponse.StatusCode | Should -Be 400
		$deleteResponse.Value.message | Should -Be 'Invalid or missing id'
	}

	It 'returns 400 when deleting with a non-positive id' {
		$deleteResponse = Invoke-CrudHandler -Method DELETE -Query @{ id = '0' }

		$deleteResponse.StatusCode | Should -Be 400
		$deleteResponse.Value.message | Should -Be 'Invalid or missing id'
	}

	It 'returns 400 when deleting with a non-numeric id' {
		$deleteResponse = Invoke-CrudHandler -Method DELETE -Query @{ id = 'abc' }

		$deleteResponse.StatusCode | Should -Be 400
		$deleteResponse.Value.message | Should -Be 'Invalid or missing id'
	}

	It 'returns 400 when updating with an invalid id' {
		$putResponse = Invoke-CrudHandler -Method PUT -Data @{
			id = 'abc'
			item = 'Valid item'
			description = 'Valid description'
		}

		$putResponse.StatusCode | Should -Be 400
		$putResponse.Value.message | Should -Be 'Invalid id value'
	}

	It 'returns 400 when updating with a non-positive id' {
		$putResponse = Invoke-CrudHandler -Method PUT -Data @{
			id = '-1'
			item = 'Valid item'
			description = 'Valid description'
		}

		$putResponse.StatusCode | Should -Be 400
		$putResponse.Value.message | Should -Be 'Invalid id value'
	}

	It 'accepts item and description at the 200 and 2000 character boundaries on POST' {
		$item200 = 'x' * 200
		$desc2000 = 'y' * 2000

		$postResponse = Invoke-CrudHandler -Method POST -Data @{
			item = $item200
			description = $desc2000
		}

		$postResponse.StatusCode | Should -Be 201
		$postResponse.Value.item.item | Should -Be $item200
		$postResponse.Value.item.description | Should -Be $desc2000
	}

	It 'accepts item and description at the 200 and 2000 character boundaries on PUT' {
		$postResponse = Invoke-CrudHandler -Method POST -Data @{
			item = 'Boundary put test'
			description = 'Initial description'
		}
		$postResponse.StatusCode | Should -Be 201

		$item200 = 'x' * 200
		$desc2000 = 'y' * 2000

		$putResponse = Invoke-CrudHandler -Method PUT -Data @{
			id = $postResponse.Value.item.id
			item = $item200
			description = $desc2000
		}

		$putResponse.StatusCode | Should -Be 200
		$putResponse.Value.message | Should -Be 'Item updated successfully'
	}

	It 'rejects item over 200 characters on POST' {
		$postResponse = Invoke-CrudHandler -Method POST -Data @{
			item = ('x' * 201)
			description = 'Valid description'
		}

		$postResponse.StatusCode | Should -Be 400
		$postResponse.Value.message | Should -Be 'Item must be between 1 and 200 characters'
	}

	It 'rejects description over 2000 characters on POST' {
		$postResponse = Invoke-CrudHandler -Method POST -Data @{
			item = 'Valid item'
			description = ('y' * 2001)
		}

		$postResponse.StatusCode | Should -Be 400
		$postResponse.Value.message | Should -Be 'Description must be between 1 and 2000 characters'
	}

	It 'rejects item over 200 characters on PUT' {
		$postResponse = Invoke-CrudHandler -Method POST -Data @{
			item = 'Item to update'
			description = 'Valid description'
		}
		$postResponse.StatusCode | Should -Be 201

		$putResponse = Invoke-CrudHandler -Method PUT -Data @{
			id = $postResponse.Value.item.id
			item = ('x' * 201)
			description = 'Valid description'
		}

		$putResponse.StatusCode | Should -Be 400
		$putResponse.Value.message | Should -Be 'Item must be between 1 and 200 characters'
	}

	It 'rejects description over 2000 characters on PUT' {
		$postResponse = Invoke-CrudHandler -Method POST -Data @{
			item = 'Item to update'
			description = 'Valid description'
		}
		$postResponse.StatusCode | Should -Be 201

		$putResponse = Invoke-CrudHandler -Method PUT -Data @{
			id = $postResponse.Value.item.id
			item = 'Valid item'
			description = ('y' * 2001)
		}

		$putResponse.StatusCode | Should -Be 400
		$putResponse.Value.message | Should -Be 'Description must be between 1 and 2000 characters'
	}

	It 'rejects empty item on POST' {
		$postResponse = Invoke-CrudHandler -Method POST -Data @{
			item = '   '
			description = 'Valid description'
		}

		$postResponse.StatusCode | Should -Be 400
		$postResponse.Value.message | Should -Be 'Missing required field: item'
	}

	It 'rejects empty description on POST' {
		$postResponse = Invoke-CrudHandler -Method POST -Data @{
			item = 'Valid item'
			description = '   '
		}

		$postResponse.StatusCode | Should -Be 400
		$postResponse.Value.message | Should -Be 'Missing required field: description'
	}

	It 'preserves punctuation and Unicode characters through POST and GET round trip' {
		$specialItem = 'Quote "Test'' & <tag> _under %percent'
		$specialDescription = 'Unicode: café ☕ naïve — "smart quotes"'

		$postResponse = Invoke-CrudHandler -Method POST -Data @{
			item = $specialItem
			description = $specialDescription
		}

		$postResponse.StatusCode | Should -Be 201
		$postResponse.Value.item.item | Should -Be $specialItem
		$postResponse.Value.item.description | Should -Be $specialDescription

		$response = Invoke-CrudHandler -Method GET -Query @{ search = 'Quote "Test' }

		$response.StatusCode | Should -Be 200
		$response.Value.rows.Count | Should -Be 1
		$response.Value.rows[0].item | Should -Be $specialItem
		$response.Value.rows[0].description | Should -Be $specialDescription
	}

	It 'preserves punctuation and Unicode characters through PUT round trip' {
		$postResponse = Invoke-CrudHandler -Method POST -Data @{
			item = 'Original item'
			description = 'Original description'
		}
		$postResponse.StatusCode | Should -Be 201

		$specialItem = 'Updated "Quote'' & <tag> _under %percent'
		$specialDescription = 'Updated Unicode: café ☕ naïve — "smart quotes"'

		$putResponse = Invoke-CrudHandler -Method PUT -Data @{
			id = $postResponse.Value.item.id
			item = $specialItem
			description = $specialDescription
		}

		$putResponse.StatusCode | Should -Be 200

		$response = Invoke-CrudHandler -Method GET -Query @{ search = 'Updated "Quote' }
		$response.StatusCode | Should -Be 200
		$response.Value.rows.Count | Should -Be 1
		$response.Value.rows[0].item | Should -Be $specialItem
		$response.Value.rows[0].description | Should -Be $specialDescription
	}

	It 'echoes the search value in the GET response envelope' {
		$searchTerm = 'Item 3'
		$response = Invoke-CrudHandler -Method GET -Query @{ search = $searchTerm }

		$response.StatusCode | Should -Be 200
		$response.Value.search | Should -Be $searchTerm
	}

	It 'returns search as null when no search parameter is provided' {
		$response = Invoke-CrudHandler -Method GET -Query @{}

		$response.StatusCode | Should -Be 200
		$response.Value.search | Should -BeNullOrEmpty
	}

	It 'treats a percent sign in search input as a literal character' {
		# Insert an item containing a literal percent sign. The seed data has none,
		# so only an escaped LIKE should match it.
		Invoke-SqliteQuery -DataSource $script:DatabasePath -Query "INSERT INTO [items] ([item], [description]) VALUES (@item, @description);" -SqlParameters @{ item = 'Discount 50%'; description = 'Literal percent test' }

		$response = Invoke-CrudHandler -Method GET -Query @{ search = '50%' }

		$response.StatusCode | Should -Be 200
		$response.Value.totalItems | Should -Be 1
		$response.Value.rows[0].item | Should -Be 'Discount 50%'
	}

	It 'treats an underscore in search input as a literal character' {
		Invoke-SqliteQuery -DataSource $script:DatabasePath -Query "INSERT INTO [items] ([item], [description]) VALUES (@item, @description);" -SqlParameters @{ item = 'snake_case_item'; description = 'Literal underscore test' }

		$response = Invoke-CrudHandler -Method GET -Query @{ search = 'snake_case_item' }

		$response.StatusCode | Should -Be 200
		$response.Value.totalItems | Should -Be 1
		$response.Value.rows[0].item | Should -Be 'snake_case_item'
	}

	It 'treats a backslash in search input as a literal character' {
		Invoke-SqliteQuery -DataSource $script:DatabasePath -Query "INSERT INTO [items] ([item], [description]) VALUES (@item, @description);" -SqlParameters @{ item = 'path\to\file'; description = 'Literal backslash test' }

		$response = Invoke-CrudHandler -Method GET -Query @{ search = 'path\to\file' }

		$response.StatusCode | Should -Be 200
		$response.Value.totalItems | Should -Be 1
		$response.Value.rows[0].item | Should -Be 'path\to\file'
	}

	It 'does not treat an unescaped percent as a wildcard that matches every item' {
		# A naive LIKE with no escaping would treat % as "match zero or more chars"
		# and return every row. The escaped predicate must return only rows that
		# literally contain the search term.
		Invoke-SqliteQuery -DataSource $script:DatabasePath -Query "INSERT INTO [items] ([item], [description]) VALUES (@item, @description);" -SqlParameters @{ item = 'LiteralPercent%'; description = 'Has percent' }

		$response = Invoke-CrudHandler -Method GET -Query @{ search = '%' }

		$response.StatusCode | Should -Be 200
		$response.Value.totalItems | Should -Be 1
		$response.Value.rows[0].item | Should -Be 'LiteralPercent%'
	}

	It 'clamps an out-of-range page to the last available page' {
		$seeded = Invoke-SqliteQuery -DataSource $script:DatabasePath -Query 'SELECT COUNT(*) AS [count] FROM [items];' -As PSObject
		$totalPages = [Math]::Ceiling($seeded.count / 10)

		$response = Invoke-CrudHandler -Method GET -Query @{ page = '9999'; pageSize = '10' }

		$response.StatusCode | Should -Be 200
		# currentPage is clamped to the last page, not 9999
		$response.Value.currentPage | Should -Be $totalPages
		$response.Value.hasNextPage | Should -BeFalse
		$response.Value.nextPage | Should -BeNullOrEmpty
		$response.Value.hasPreviousPage | Should -BeTrue
		# The last page's rows must be present and consistent with the clamped page
		$response.Value.rows.Count | Should -Be ($seeded.count - (($totalPages - 1) * 10))
		$response.Value.totalItems | Should -Be $seeded.count
	}

	It 'clamps an out-of-range page with a search filter to the last matching page' {
		# Seed items that match a search so there is a small number of pages
		for ($i = 1; $i -le 15; $i++) {
			Invoke-SqliteQuery -DataSource $script:DatabasePath -Query "INSERT INTO [items] ([item], [description]) VALUES (@item, @description);" -SqlParameters @{ item = "Searchable $i"; description = 'Filter test' }
		}

		$response = Invoke-CrudHandler -Method GET -Query @{ search = 'Searchable'; page = '9999'; pageSize = '5' }

		$totalItems = (Invoke-SqliteQuery -DataSource $script:DatabasePath -Query "SELECT COUNT(*) AS [count] FROM [items] WHERE [item] LIKE '%Searchable%';" -As SingleValue)
		$expectedLastPage = [Math]::Ceiling($totalItems / 5)

		$response.StatusCode | Should -Be 200
		$response.Value.currentPage | Should -Be $expectedLastPage
		$response.Value.hasNextPage | Should -BeFalse
		$response.Value.totalItems | Should -Be $totalItems
	}

	It 'echoes the currentPage in the response so the template can bind it' {
		$response = Invoke-CrudHandler -Method GET -Query @{ page = '2'; pageSize = '10' }

		$response.StatusCode | Should -Be 200
		$response.Value.currentPage | Should -Be 2
	}

	It 'preserves the search value in the response for a filtered page-2 request' {
		$searchTerm = 'Item'
		$response = Invoke-CrudHandler -Method GET -Query @{ search = $searchTerm; page = '2'; pageSize = '5' }

		$response.StatusCode | Should -Be 200
		$response.Value.search | Should -Be $searchTerm
		$response.Value.currentPage | Should -Be 2
	}

	It 'returns 500 with { message } envelope when the database is unavailable' {
		$corruptDb = Join-Path $TestDrive 'corrupt.db'
		[System.IO.File]::WriteAllBytes($corruptDb, [byte[]](1, 2, 3, 4, 5, 6, 7, 8))

		$savedDb = $script:DatabasePath
		$script:DatabasePath = $corruptDb
		try {
			$response = Invoke-CrudHandler -Method GET -Query @{}

			$response.StatusCode | Should -Be 500
			$response.Value.message | Should -Be 'Internal server error'
		} finally {
			$script:DatabasePath = $savedDb
		}
	}
}

Describe 'Search and pagination template contract' {
	BeforeAll {
		$script:RepoRoot = (Resolve-Path "$PSScriptRoot/..").Path
		$script:Crudmgr = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'views/components/crudmgr.pode') -Raw
	}

	It 'uses type=search on the search input (not type=text)' {
		$script:Crudmgr | Should -Match 'type="search"'
	}

	It 'binds the search value from the response envelope' {
		$script:Crudmgr | Should -Match 'value="\{\{search\}\}"'
	}

	It 'does not mark the search input as required' {
		# Extract just the search input block and assert it has no required attr
		$searchInputPattern = '(?s)<input[^>]*id="simple-search"[^>]*>'
		$searchInput = ([regex]::Match($script:Crudmgr, $searchInputPattern)).Value
		$searchInput | Should -Not -Match '\brequired\b'
	}

	It 'removes every hx-params attribute from the template' {
		$script:Crudmgr | Should -Not -Match 'hx-params'
	}

	It 'renders a hidden current-page input bound to currentPage' {
		$script:Crudmgr | Should -Match 'id="current-page"'
		$script:Crudmgr | Should -Match 'name="page"'
		$script:Crudmgr | Should -Match 'value="\{\{currentPage\}\}"'
	}

	It 'declares hx-include on the #crud container for search and page' {
		$script:Crudmgr | Should -Match 'hx-include="#simple-search, #current-page"'
	}

	It 'renders pagination controls as buttons, not anchor links' {
		# Page links must be <button> elements with type=button, not <a href="#">
		$pageLinkPattern = 'class="page-link'
		$pageLinkMatches = ([regex]::Matches($script:Crudmgr, $pageLinkPattern)).Count
		$pageLinkMatches | Should -BeGreaterOrEqual 3
		# No page-link should be on an <a> tag
		$anchorPageLinks = ([regex]::Matches($script:Crudmgr, '<a[^>]*class="page-link')).Count
		$anchorPageLinks | Should -Be 0
	}

	It 'omits htmx actions from disabled controls' {
		# The disabled guard wraps the entire button including hx-get, so a disabled
		# control cannot issue a request. Assert the Mustache disabled guard exists.
		$script:Crudmgr | Should -Match '\{\{\^hasPreviousPage\}\}disabled'
		$script:Crudmgr | Should -Match '\{\{\^hasNextPage\}\}disabled'
		$script:Crudmgr | Should -Match 'aria-disabled="true"'
	}

	It 'sets aria-current=page only on the active page button' {
		$script:Crudmgr | Should -Match '\{\{#isActive\}\}aria-current="page"\{\{/isActive\}\}'
	}

	It 'includes the search input in pagination button requests' {
		# Each pagination button carries hx-include for the search + current page
		$paginationIncludes = ([regex]::Matches($script:Crudmgr, 'hx-include="#simple-search, #current-page"')).Count
		$paginationIncludes | Should -BeGreaterOrEqual 3
	}
}

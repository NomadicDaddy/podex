Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

function Assert-ItemInput {
	[CmdletBinding()]
	[OutputType([hashtable])]
	param(
		[AllowNull()]
		[object]$Item,
		[AllowNull()]
		[object]$Description
	)

	$itemValue = ([string]$Item).Trim()
	$descriptionValue = ([string]$Description).Trim()

	if ([string]::IsNullOrWhiteSpace($itemValue)) {
		throw [System.ArgumentException]::new('Missing required field: item')
	}
	if ([string]::IsNullOrWhiteSpace($descriptionValue)) {
		throw [System.ArgumentException]::new('Missing required field: description')
	}
	if ($itemValue.Length -gt 200) {
		throw [System.ArgumentException]::new('Item must be between 1 and 200 characters')
	}
	if ($descriptionValue.Length -gt 2000) {
		throw [System.ArgumentException]::new(
			'Description must be between 1 and 2000 characters'
		)
	}

	return @{
		Description = $descriptionValue
		Item = $itemValue
	}
}

function Get-ItemPage {
	[CmdletBinding()]
	[OutputType([hashtable])]
	param(
		[Parameter(Mandatory)]
		[string]$DataSource,
		[AllowEmptyString()]
		[string]$Search = '',
		[AllowEmptyString()]
		[string]$Page = '',
		[AllowEmptyString()]
		[string]$PageSize = ''
	)

	$pageNumber = 1
	if (-not [int]::TryParse($Page, [ref]$pageNumber) -or $pageNumber -lt 1) {
		$pageNumber = 1
	}

	$pageSizeNumber = 10
	if (-not [int]::TryParse($PageSize, [ref]$pageSizeNumber) -or $pageSizeNumber -lt 1) {
		$pageSizeNumber = 10
	}
	$pageSizeNumber = [Math]::Min($pageSizeNumber, 100)

	$escapedSearch = ''
	if ($Search) {
		$escapedSearch = $Search -replace '\\', '\\' -replace '%', '\%' -replace '_', '\_'
	}

	$countSql = 'SELECT COUNT(*) AS totalItems FROM [items]'
	$countParameters = @{}
	if ($escapedSearch) {
		$countSql += " WHERE ([item] LIKE @search ESCAPE '\' OR [description] LIKE @search ESCAPE '\')"
		$countParameters['search'] = "%$escapedSearch%"
	}
	$totalItems = [int](Invoke-SqliteQuery `
			-DataSource $DataSource `
			-Query $countSql `
			-SqlParameters $countParameters `
			-As SingleValue `
			-ErrorAction Stop)

	$totalPages = if ($totalItems -gt 0) {
		[int][Math]::Ceiling($totalItems / $pageSizeNumber)
	} else {
		0
	}
	if ($totalItems -gt 0 -and $pageNumber -gt $totalPages) {
		$pageNumber = $totalPages
	}
	$offset = ($pageNumber - 1) * $pageSizeNumber

	$query = @"
SELECT [id], [item], [description],
	strftime('%Y-%m-%dT%H:%M:%SZ', [created_at]) AS [created_at],
	strftime('%Y-%m-%dT%H:%M:%SZ', [updated_at]) AS [updated_at],
	strftime('%Y-%m-%d %H:%M UTC', [created_at]) AS [created_at_display]
FROM [items]
"@
	$queryParameters = @{}
	if ($escapedSearch) {
		$query += "`n	WHERE ([item] LIKE @search ESCAPE '\' OR [description] LIKE @search ESCAPE '\')"
		$queryParameters['search'] = "%$escapedSearch%"
	}
	$query += "`n	ORDER BY [created_at] DESC, [id] DESC LIMIT @pageSize OFFSET @offset;"
	$queryParameters['pageSize'] = $pageSizeNumber
	$queryParameters['offset'] = $offset

	$rows = [System.Collections.ArrayList]@()
	$result = Invoke-SqliteQuery `
		-DataSource $DataSource `
		-Query $query `
		-SqlParameters $queryParameters `
		-As PSObject `
		-ErrorAction Stop
	if ($null -ne $result) {
		foreach ($row in $result) {
			$null = $rows.Add($row)
		}
	}

	$pages = @(
		for ($number = 1; $number -le $totalPages; $number++) {
			@{
				isActive = $number -eq $pageNumber
				number = $number
			}
		}
	)
	$hasPreviousPage = $pageNumber -gt 1
	$hasNextPage = $pageNumber -lt $totalPages

	return @{
		currentPage = $pageNumber
		endIndex = [Math]::Min($offset + $pageSizeNumber, $totalItems)
		hasNextPage = $hasNextPage
		hasPreviousPage = $hasPreviousPage
		nextPage = if ($hasNextPage) { $pageNumber + 1 } else { $null }
		pages = $pages
		previousPage = if ($hasPreviousPage) { $pageNumber - 1 } else { $null }
		rows = $rows
		search = if ($Search) { $Search } else { $null }
		startIndex = if ($totalItems -gt 0) { $offset + 1 } else { 0 }
		totalItems = $totalItems
	}
}

function Add-CrudItem {
	[CmdletBinding(SupportsShouldProcess)]
	[OutputType([object])]
	param(
		[Parameter(Mandatory)]
		[string]$DataSource,
		[Parameter(Mandatory)]
		[string]$Item,
		[Parameter(Mandatory)]
		[string]$Description
	)

	if (-not $PSCmdlet.ShouldProcess($DataSource, "Add item '$Item'")) {
		return $null
	}

	$query = @'
INSERT INTO [items] ([item], [description]) VALUES (@item, @description);
SELECT [id], [item], [description],
	strftime('%Y-%m-%dT%H:%M:%SZ', [created_at]) AS [created_at],
	strftime('%Y-%m-%dT%H:%M:%SZ', [updated_at]) AS [updated_at]
FROM [items] WHERE [id] = last_insert_rowid();
'@
	return Invoke-SqliteQuery `
		-DataSource $DataSource `
		-Query $query `
		-SqlParameters @{ description = $Description; item = $Item } `
		-As PSObject `
		-ErrorAction Stop
}

function Set-CrudItem {
	[CmdletBinding(SupportsShouldProcess)]
	[OutputType([bool])]
	param(
		[Parameter(Mandatory)]
		[string]$DataSource,
		[Parameter(Mandatory)]
		[int]$Id,
		[Parameter(Mandatory)]
		[string]$Item,
		[Parameter(Mandatory)]
		[string]$Description
	)

	if (-not $PSCmdlet.ShouldProcess($DataSource, "Update item $Id")) {
		return $false
	}

	$query = @'
UPDATE [items]
SET [item] = @item, [description] = @description, [updated_at] = CURRENT_TIMESTAMP
WHERE [id] = @id;
SELECT changes() AS [affected];
'@
	$affected = Invoke-SqliteQuery `
		-DataSource $DataSource `
		-Query $query `
		-SqlParameters @{ description = $Description; id = $Id; item = $Item } `
		-As SingleValue `
		-ErrorAction Stop
	return [int]$affected -gt 0
}

function Remove-CrudItem {
	[CmdletBinding(SupportsShouldProcess)]
	[OutputType([bool])]
	param(
		[Parameter(Mandatory)]
		[string]$DataSource,
		[Parameter(Mandatory)]
		[int]$Id
	)

	if (-not $PSCmdlet.ShouldProcess($DataSource, "Remove item $Id")) {
		return $false
	}

	$query = @'
DELETE FROM [items] WHERE [id] = @id;
SELECT changes() AS [affected];
'@
	$affected = Invoke-SqliteQuery `
		-DataSource $DataSource `
		-Query $query `
		-SqlParameters @{ id = $Id } `
		-As SingleValue `
		-ErrorAction Stop
	return [int]$affected -gt 0
}

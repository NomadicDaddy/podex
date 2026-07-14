{

	$isHTMX = $($WebEvent.Request.Headers.'HX-Request')
	$db = (Get-PodeConfig).Podex.DBFile

	Write-FormattedLog -tag 'api' -log "Items API: $($WebEvent.Method.ToUpper()) $($WebEvent.Path) `$isHTMX:$($isHTMX) Q: $($WebEvent.Query | ConvertTo-Json -Compress)"

	try {
		$search = $WebEvent.Query['search']

		# Parse paging inputs safely: reject non-numeric values, clamp out-of-range
		# values, and fall back to the documented defaults of page 1 / pageSize 10.
		$page = 1
		if ([int]::TryParse($WebEvent.Query['page'], [ref]$page) -and $page -ge 1) {
			# $page is already a valid positive integer
		} else {
			$page = 1
		}

		$pageSize = 10
		if ([int]::TryParse($WebEvent.Query['pageSize'], [ref]$pageSize) -and $pageSize -ge 1) {
			$pageSize = [Math]::Min($pageSize, 100)
		} else {
			$pageSize = 10
		}

		$offset = ($page - 1) * $pageSize

		$sqlx = "SELECT [id], [item], [description], date([created_at]) as [created_at], [updated_at] FROM [items]"
		$params = @{}

		if ($search) {
			$sqlx += " WHERE ([item] LIKE @search OR [description] LIKE @search)"
			$params['search'] = "%$search%"
		}

		$sqlx += " ORDER BY [created_at] DESC, [id] DESC LIMIT @pageSize OFFSET @offset;"

		$params['pageSize'] = $pageSize
		$params['offset'] = $offset

		# Total matching rows (independent of pagination) for accurate page metadata
		$countSql = "SELECT COUNT(*) AS totalItems FROM [items]"
		$countParams = @{}
		if ($search) {
			$countSql += " WHERE ([item] LIKE @search OR [description] LIKE @search)"
			$countParams['search'] = "%$search%"
		}
		$countResult = (Invoke-SqliteQuery -DataSource $db -Query $countSql -SqlParameters $countParams -As SingleValue -ErrorAction Stop)
		$totalItems = [int]$countResult

		# Write-FormattedLog -tag 'database' -log "db: $($db); sqlx: $($sqlx); search: $search; params: $($params | ConvertTo-Json -Compress)"
		$rs = (Invoke-SqliteQuery -DataSource $db -Query $sqlx -SqlParameters $params -As PSObject -ErrorAction Stop)

		$startIndex = if ($totalItems -gt 0) { $offset + 1 } else { 0 }
		$endIndex = [Math]::Min($offset + $pageSize, $totalItems)
		$totalPages = [Math]::Ceiling($totalItems / $pageSize)
		$hasPreviousPage = $page -gt 1
		$hasNextPage = $page -lt $totalPages
		$pages = @()
		for ($i = 1; $i -le $totalPages; $i++) {
			$pages += @{
				number = $i
				isActive = $i -eq $page
			}
		}

		$response = @{
			rows = $rs
			startIndex = $startIndex
			endIndex = $endIndex
			totalItems = $totalItems
			hasPreviousPage = $hasPreviousPage
			hasNextPage = $hasNextPage
			previousPage = if ($hasPreviousPage) { $page - 1 } else { $null }
			nextPage = if ($hasNextPage) { $page + 1 } else { $null }
			pages = $pages
			currentPage = $page
		}

		Write-FormattedLog -tag 'debug' -log "Items found: $($totalItems)"
		Write-PodeJsonResponse -StatusCode 200 -Value $response

	} catch {
		Write-FormattedLog -tag 'error' -log "Error retrieving items: $($_.Exception.Message)"
		Write-PodeJsonResponse -StatusCode 500 -Value @{ message = "Internal server error" }
	}

}

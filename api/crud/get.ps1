{

	$isHTMX = $($WebEvent.Request.Headers.'HX-Request')
	$db = (Get-PodeConfig).Podex.DBFile

	Write-FormattedLog -tag 'api' -log "Items API: $($WebEvent.Method.ToUpper()) $($WebEvent.Path) `$isHTMX:$($isHTMX) Q: $($WebEvent.Query | ConvertTo-Json -Compress)"

	try {
		$search = $WebEvent.Query['search']

		# Parse paging inputs safely: reject non-numeric values, clamp out-of-range
		# values, and fall back to the documented defaults of page 1 / pageSize 10.
		$page = 1
		if (-not [int]::TryParse($WebEvent.Query['page'], [ref]$page) -or $page -lt 1) {
			$page = 1
		}

		$pageSize = 10
		if (-not [int]::TryParse($WebEvent.Query['pageSize'], [ref]$pageSize) -or $pageSize -lt 1) {
			$pageSize = 10
		}
		$pageSize = [Math]::Min($pageSize, 100)

		$offset = ($page - 1) * $pageSize

		# Format timestamps as UTC RFC 3339 (YYYY-MM-DDTHH:mm:ssZ) and a display
		# variant (YYYY-MM-DD HH:mm UTC) for human-readable views.
		$sqlx = @"
SELECT [id], [item], [description],
	strftime('%Y-%m-%dT%H:%M:%SZ', [created_at]) AS [created_at],
	strftime('%Y-%m-%dT%H:%M:%SZ', [updated_at]) AS [updated_at],
	strftime('%Y-%m-%d %H:%M UTC', [created_at]) AS [created_at_display]
FROM [items]
"@
		$params = @{}

		if ($search) {
			$sqlx += "`n	WHERE ([item] LIKE @search OR [description] LIKE @search)"
			$params['search'] = "%$search%"
		}

		$sqlx += "`n	ORDER BY [created_at] DESC, [id] DESC LIMIT @pageSize OFFSET @offset;"

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

		$rs = (Invoke-SqliteQuery -DataSource $db -Query $sqlx -SqlParameters $params -As PSObject -ErrorAction Stop)

		# Always normalize rows to a collection so the JSON envelope has a stable
		# array shape even when PSSQLite returns $null for an empty result set.
		# PowerShell unwraps an empty @() from an if-expression to $null, so use
		# an ArrayList which survives assignment.
		$rowList = [System.Collections.ArrayList]@()
		if ($null -ne $rs) {
			foreach ($row in $rs) {
				$null = $rowList.Add($row)
			}
		}

		$startIndex = if ($totalItems -gt 0) { $offset + 1 } else { 0 }
		$endIndex = [Math]::Min($offset + $pageSize, $totalItems)
		$totalPages = if ($pageSize -gt 0 -and $totalItems -gt 0) { [Math]::Ceiling($totalItems / $pageSize) } else { 0 }
		$hasPreviousPage = $page -gt 1
		$hasNextPage = $page -lt $totalPages
		$pageNumbers = @()
		for ($i = 1; $i -le $totalPages; $i++) {
			$pageNumbers += @{
				number = $i
				isActive = $i -eq $page
			}
		}

		$response = @{
			rows = $rowList
			search = $search
			startIndex = $startIndex
			endIndex = $endIndex
			totalItems = $totalItems
			hasPreviousPage = $hasPreviousPage
			hasNextPage = $hasNextPage
			previousPage = if ($hasPreviousPage) { $page - 1 } else { $null }
			nextPage = if ($hasNextPage) { $page + 1 } else { $null }
			pages = $pageNumbers
			currentPage = $page
		}

		Write-FormattedLog -tag 'debug' -log "Items found: $($totalItems)"
		Write-PodeJsonResponse -StatusCode 200 -Value $response

	} catch {
		Write-FormattedLog -tag 'error' -log "Error retrieving items: $($_.Exception.Message)"
		Write-PodeJsonResponse -StatusCode 500 -Value @{ message = "Internal server error" }
	}

}

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

		# Escape LIKE metacharacters (backslash, percent, underscore) so user input
		# matches literally instead of being treated as SQL wildcards. Each LIKE
		# predicate includes ESCAPE '\' so SQLite treats backslash as the escape
		# character. Backslash is doubled first so it does not consume a later
		# escape sequence introduced for % or _.
		$escapedSearch = $null
		if ($search) {
			$escapedSearch = $search -replace '\\', '\\' -replace '%', '\%' -replace '_', '\_'
		}

		# Total matching rows (independent of pagination) for accurate page metadata.
		# The count runs first so the requested page can be clamped before fetching.
		$countSql = "SELECT COUNT(*) AS totalItems FROM [items]"
		$countParams = @{}
		if ($escapedSearch) {
			$countSql += " WHERE ([item] LIKE @search ESCAPE '\' OR [description] LIKE @search ESCAPE '\')"
			$countParams['search'] = "%$escapedSearch%"
		}
		$countResult = (Invoke-SqliteQuery -DataSource $db -Query $countSql -SqlParameters $countParams -As SingleValue -ErrorAction Stop)
		$totalItems = [int]$countResult

		# Clamp the requested page to the valid range so out-of-range pages return
		# the last available page rather than contradicting their own metadata.
		# When totalItems is 0 the page stays at 1 and the response carries an
		# empty rows array with zeroed pagination metadata.
		$totalPages = if ($pageSize -gt 0 -and $totalItems -gt 0) { [Math]::Ceiling($totalItems / $pageSize) } else { 0 }
		if ($totalItems -gt 0 -and $page -gt $totalPages) {
			$page = $totalPages
		}

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

		if ($escapedSearch) {
			$sqlx += "`n	WHERE ([item] LIKE @search ESCAPE '\' OR [description] LIKE @search ESCAPE '\')"
			$params['search'] = "%$escapedSearch%"
		}

		$sqlx += "`n	ORDER BY [created_at] DESC, [id] DESC LIMIT @pageSize OFFSET @offset;"

		$params['pageSize'] = $pageSize
		$params['offset'] = $offset

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

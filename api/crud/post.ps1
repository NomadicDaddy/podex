{

	$isHTMX = $($WebEvent.Request.Headers.'HX-Request')
	$db = (Get-PodeConfig).Podex.DBFile

	Write-FormattedLog -tag 'api' -log "CRUD API: $($WebEvent.Method.ToUpper()) $($WebEvent.Path) `$isHTMX:$($isHTMX) Q: $($WebEvent.Query | ConvertTo-Json -Compress)"

	try {
		$data = $WebEvent.Data

		if (-not $data) {
			Write-FormattedLog -tag 'error' -log "No data received in POST request"
			Write-PodeJsonResponse -StatusCode 400 -Value @{ message = "No data received in request" }
			return
		}

		Write-FormattedLog -tag 'debug' -log "Parsed POST data: $($data | ConvertTo-Json -Compress)"

		$item = ([string]$data.item).Trim()
		$description = ([string]$data.description).Trim()

		if ([string]::IsNullOrWhiteSpace($item)) {
			Write-FormattedLog -tag 'error' -log "Missing required field: item"
			Write-PodeJsonResponse -StatusCode 400 -Value @{ message = "Missing required field: item" }
			return
		}

		if ([string]::IsNullOrWhiteSpace($description)) {
			Write-FormattedLog -tag 'error' -log "Missing required field: description"
			Write-PodeJsonResponse -StatusCode 400 -Value @{ message = "Missing required field: description" }
			return
		}

		if ($item.Length -lt 1 -or $item.Length -gt 200) {
			Write-FormattedLog -tag 'error' -log "Invalid item length: $($item.Length)"
			Write-PodeJsonResponse -StatusCode 400 -Value @{ message = "Item must be between 1 and 200 characters" }
			return
		}

		if ($description.Length -lt 1 -or $description.Length -gt 2000) {
			Write-FormattedLog -tag 'error' -log "Invalid description length: $($description.Length)"
			Write-PodeJsonResponse -StatusCode 400 -Value @{ message = "Description must be between 1 and 2000 characters" }
			return
		}

		$sqlx = @"
INSERT INTO [items] ([item], [description]) VALUES (@item, @description);
SELECT [id], [item], [description],
	strftime('%Y-%m-%dT%H:%M:%SZ', [created_at]) AS [created_at],
	strftime('%Y-%m-%dT%H:%M:%SZ', [updated_at]) AS [updated_at]
FROM [items] WHERE [id] = last_insert_rowid();
"@
		$params = @{
			item = $item
			description = $description
		}
		Write-FormattedLog -tag 'database' -log "db: $($db); sqlx: $($sqlx); params: $($params | ConvertTo-Json -Compress)"
		$created = (Invoke-SqliteQuery -DataSource $db -Query $sqlx -SqlParameters $params -As PSObject -ErrorAction Stop)

		Write-PodeJsonResponse -StatusCode 201 -Value @{
			message = "Item created successfully"
			item = $created
		}

	} catch {
		Write-FormattedLog -tag 'error' -log "Error in POST method: $($_.Exception.Message)"
		Write-PodeJsonResponse -StatusCode 500 -Value @{ message = "Internal server error" }
	}

}

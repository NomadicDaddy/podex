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

		$sqlx = "INSERT INTO [items] ([item], [description]) VALUES (@item, @description);"
		$params = @{
			item = $item
			description = $description
		}
		Write-FormattedLog -tag 'database' -log "db: $($db); sqlx: $($sqlx); params: $($params | ConvertTo-Json -Compress)"
		Invoke-SqliteQuery -DataSource $db -Query $sqlx -SqlParameters $params -ErrorAction Stop
		Write-PodeJsonResponse -StatusCode 201 -Value @{ message = "Item created successfully" }

	} catch {
		Write-FormattedLog -tag 'error' -log "Error in POST method: $($_.Exception.Message)"
		Write-PodeJsonResponse -StatusCode 500 -Value @{ message = "Internal server error" }
	}

}

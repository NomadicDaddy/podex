{

	$isHTMX = $($WebEvent.Request.Headers.'HX-Request')
	$db = (Get-PodeConfig).Podex.DBFile

	Write-FormattedLog -tag 'api' -log "CRUD API: $($WebEvent.Method.ToUpper()) $($WebEvent.Path) `$isHTMX:$($isHTMX) Q: $($WebEvent.Query | ConvertTo-Json -Compress)"

	try {
		$data = $WebEvent.Data

		if (-not $data) {
			Write-FormattedLog -tag 'error' -log "No data received in PUT request"
			Write-PodeJsonResponse -StatusCode 400 -Value @{ message = "No data received in request" }
			return
		}

		Write-FormattedLog -tag 'debug' -log "Parsed PUT data: $($data | ConvertTo-Json -Compress)"

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

		$id = 0
		if (-not [int]::TryParse([string]$data.id, [ref]$id) -or $id -le 0) {
			Write-FormattedLog -tag 'error' -log "Invalid id value"
			Write-PodeJsonResponse -StatusCode 400 -Value @{ message = "Invalid id value" }
			return
		}

		$sqlx = "UPDATE [items] SET [item] = @item, [description] = @description, [updated_at] = CURRENT_TIMESTAMP WHERE [id] = @id;"
		$params = @{
			id = $id
			item = $item
			description = $description
		}
		Write-FormattedLog -tag 'database' -log "db: $($db); sqlx: $($sqlx); params: $($params | ConvertTo-Json -Compress)"
		Invoke-SqliteQuery -DataSource $db -Query $sqlx -SqlParameters $params
		Write-FormattedLog -tag 'debug' -log "Item updated successfully"
		Write-PodeJsonResponse -StatusCode 200 -Value @{ message = "Item updated successfully" }

	} catch {
		Write-FormattedLog -tag 'error' -log "Error updating item: $_"
		Write-PodeJsonResponse -StatusCode 500 -Value @{ message = "Internal server error" }
	}

}

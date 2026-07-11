{

	$isHTMX = $($WebEvent.Request.Headers.'HX-Request')
	$db = (Get-PodeConfig).Podex.DBFile

	Write-FormattedLog -tag 'api' -log "CRUD API: $($WebEvent.Method.ToUpper()) $($WebEvent.Path) `$isHTMX:$($isHTMX) Q: $($WebEvent.Query | ConvertTo-Json -Compress)"

	try {
		$id = $WebEvent.Query['id']

		if (-not $id -or -not [int]::TryParse($id, [ref]$null)) {
			Write-PodeJsonResponse -StatusCode 400 -Value @{ message = "Invalid or missing id" }
			return
		}

		$sqlx = "DELETE FROM [items] WHERE [id] = @id;"
		$params = @{
			id = [int]$id
		}
		Write-FormattedLog -tag 'database' -log "db: $($db); sqlx: $($sqlx); id: $id"
		Invoke-SqliteQuery -DataSource $db -Query $sqlx -SqlParameters $params
		Write-FormattedLog -tag 'debug' -log "Item deleted successfully"
		Write-PodeJsonResponse -StatusCode 200 -Value @{ message = "Item deleted successfully" }

	} catch {
		Write-FormattedLog -tag 'error' -log "Error deleting item: $_"
		Write-PodeJsonResponse -StatusCode 500 -Value @{ message = "Internal server error" }
	}

}

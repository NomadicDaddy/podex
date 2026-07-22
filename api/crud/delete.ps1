{

	$isHTMX = $($WebEvent.Request.Headers.'HX-Request')
	$db = (Get-PodeConfig).Podex.DBFile

	Write-FormattedLog -tag 'api' -log "CRUD API: $($WebEvent.Method.ToUpper()) $($WebEvent.Path) `$isHTMX:$($isHTMX) Q: $($WebEvent.Query | ConvertTo-Json -Compress)"

	try {
		$idRaw = $WebEvent.Query['id']

		$id = 0
		if (-not $idRaw -or -not [int]::TryParse([string]$idRaw, [ref]$id) -or $id -le 0) {
			Write-FormattedLog -tag 'error' -log "Invalid or missing id"
			Write-PodeJsonResponse -StatusCode 400 -Value @{ message = "Invalid or missing id" }
			return
		}

		$sqlx = @"
DELETE FROM [items] WHERE [id] = @id;
SELECT changes() AS [affected];
"@
		$params = @{
			id = $id
		}
		Write-FormattedLog -tag 'database' -log "db: $($db); sqlx: $($sqlx); id: $id"
		$affectedResult = (Invoke-SqliteQuery -DataSource $db -Query $sqlx -SqlParameters $params -As SingleValue -ErrorAction Stop)
		$affected = [int]$affectedResult

		if ($affected -eq 0) {
			Write-FormattedLog -tag 'error' -log "Item not found: id=$id"
			Write-PodeJsonResponse -StatusCode 404 -Value @{ message = "Item not found" }
			return
		}

		Write-FormattedLog -tag 'debug' -log "Item deleted successfully: id=$id"
		Write-PodeJsonResponse -StatusCode 200 -Value @{
			message = "Item deleted successfully"
			id = $id
		}

	} catch {
		Write-FormattedLog -tag 'error' -log "Error deleting item: $($_.Exception.Message)"
		Write-PodeJsonResponse -StatusCode 500 -Value @{ message = "Internal server error" }
	}

}

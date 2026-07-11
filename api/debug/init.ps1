{

	$db = (Get-PodeConfig).Podex.DBFile

	try {
		$sqlx = Get-Content -Path './api/debug/init.sql' -Raw
		Invoke-SqliteQuery -DataSource $db -Query $sqlx
		Write-FormattedLog -tag 'debug' -log "Database cleared successfully"
		Write-PodeJsonResponse -StatusCode 200 -Value @{ message = "Database cleared successfully" }
	} catch {
		Write-FormattedLog -tag 'error' -log "Error clearing database: $_"
		Write-PodeJsonResponse -StatusCode 500 -Value @{ message = "Internal server error" }
	}

}

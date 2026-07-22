{

	$db = (Get-PodeConfig).Podex.DBFile

	try {
		# Use clear.sql to drop and recreate the table, leaving a valid empty
		# schema. This is idempotent: if the table is absent or already empty the
		# operation still succeeds and returns 200. clear.sql uses
		# DROP TABLE IF EXISTS so it never errors on a missing table.
		$sqlx = Get-Content -Path "$PSScriptRoot/../../api/debug/clear.sql" -Raw
		Invoke-SqliteQuery -DataSource $db -Query $sqlx -ErrorAction Stop
		Write-FormattedLog -tag 'debug' -log "Database cleared"
		Write-PodeJsonResponse -StatusCode 200 -Value @{ message = "Database cleared" }
	} catch {
		Write-FormattedLog -tag 'error' -log "Error clearing database: $_"
		Write-PodeJsonResponse -StatusCode 500 -Value @{ message = "Internal server error" }
	}

}

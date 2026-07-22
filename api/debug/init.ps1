{

	$db = (Get-PodeConfig).Podex.DBFile

	try {
		$sqlx = Get-Content -Path "$PSScriptRoot/../../api/debug/init.sql" -Raw
		Invoke-SqliteQuery -DataSource $db -Query $sqlx -ErrorAction Stop
		Write-FormattedLog -tag 'debug' -log "Database initialized"
		Write-PodeJsonResponse -StatusCode 200 -Value @{ message = "Database initialized" }
	} catch {
		Write-FormattedLog -tag 'error' -log "Error initializing database: $_"
		Write-PodeJsonResponse -StatusCode 500 -Value @{ message = "Internal server error" }
	}

}

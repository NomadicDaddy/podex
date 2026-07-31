Add-PodeRoute -Path '/health' -Method Get -ScriptBlock {
	Write-PodeJsonResponse -StatusCode 200 -Value @{ status = 'ok' }
}

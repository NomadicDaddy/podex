{
	$isHTMX = $WebEvent.Request.Headers['HX-Request']
	$db = (Get-PodeConfig).Podex.DBFile

	Write-FormattedLog -tag 'api' -log "Items API: $($WebEvent.Method.ToUpper()) $($WebEvent.Path) `$isHTMX:$($isHTMX) Q: $($WebEvent.Query | ConvertTo-Json -Compress)"

	try {
		$response = Get-RequestedItemPage -DataSource $db -WebRequestEvent $WebEvent
		Write-FormattedLog -tag 'debug' -log "Items found: $($response.totalItems)"
		Write-ItemPageResponse -WebRequestEvent $WebEvent -PageData $response
	} catch {
		Write-FormattedLog -tag 'error' -log "Error retrieving items: $($_.Exception.Message)"
		Write-ItemErrorResponse `
			-WebRequestEvent $WebEvent `
			-StatusCode 500 `
			-Message 'Internal server error'
	}
}

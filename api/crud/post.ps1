{
	$isHTMX = $WebEvent.Request.Headers['HX-Request']
	$db = (Get-PodeConfig).Podex.DBFile

	Write-FormattedLog -tag 'api' -log "CRUD API: $($WebEvent.Method.ToUpper()) $($WebEvent.Path) `$isHTMX:$($isHTMX) Q: $($WebEvent.Query | ConvertTo-Json -Compress)"

	try {
		$data = $WebEvent.Data
		if (-not $data) {
			Write-ItemErrorResponse `
				-WebRequestEvent $WebEvent `
				-StatusCode 400 `
				-Message 'No data received in request'
			return
		}

		$fields = Assert-ItemInput -Item $data.item -Description $data.description
		$created = Add-CrudItem `
			-DataSource $db `
			-Item $fields.Item `
			-Description $fields.Description
		$page = Get-RequestedItemPage -DataSource $db -WebRequestEvent $WebEvent
		Write-ItemPageResponse `
			-WebRequestEvent $WebEvent `
			-PageData $page `
			-JsonStatusCode 201 `
			-JsonValue @{
			message = "Item created successfully"
			item = $created
		}
	} catch [System.ArgumentException] {
		Write-ItemErrorResponse `
			-WebRequestEvent $WebEvent `
			-StatusCode 422 `
			-Message $_.Exception.Message
	} catch {
		Write-FormattedLog -tag 'error' -log "Error in POST method: $($_.Exception.Message)"
		Write-ItemErrorResponse `
			-WebRequestEvent $WebEvent `
			-StatusCode 500 `
			-Message 'Internal server error'
	}
}

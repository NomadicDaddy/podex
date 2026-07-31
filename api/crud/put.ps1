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

		$id = 0
		if (-not [int]::TryParse([string]$data.id, [ref]$id) -or $id -le 0) {
			Write-ItemErrorResponse `
				-WebRequestEvent $WebEvent `
				-StatusCode 400 `
				-Message 'Invalid id value'
			return
		}

		$fields = Assert-ItemInput -Item $data.item -Description $data.description
		$updated = Set-CrudItem `
			-DataSource $db `
			-Id $id `
			-Item $fields.Item `
			-Description $fields.Description
		if (-not $updated) {
			Write-ItemErrorResponse `
				-WebRequestEvent $WebEvent `
				-StatusCode 404 `
				-Message 'Item not found'
			return
		}

		Write-FormattedLog -tag 'debug' -log "Item updated successfully: id=$id"
		$page = Get-RequestedItemPage -DataSource $db -WebRequestEvent $WebEvent
		Write-ItemPageResponse `
			-WebRequestEvent $WebEvent `
			-PageData $page `
			-JsonValue @{ id = $id; message = 'Item updated successfully' }
	} catch [System.ArgumentException] {
		Write-ItemErrorResponse `
			-WebRequestEvent $WebEvent `
			-StatusCode 422 `
			-Message $_.Exception.Message
	} catch {
		Write-FormattedLog -tag 'error' -log "Error updating item: $($_.Exception.Message)"
		Write-ItemErrorResponse `
			-WebRequestEvent $WebEvent `
			-StatusCode 500 `
			-Message 'Internal server error'
	}
}

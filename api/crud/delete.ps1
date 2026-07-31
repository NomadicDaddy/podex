{
	$isHTMX = $WebEvent.Request.Headers['HX-Request']
	$db = (Get-PodeConfig).Podex.DBFile

	Write-FormattedLog -tag 'api' -log "CRUD API: $($WebEvent.Method.ToUpper()) $($WebEvent.Path) `$isHTMX:$($isHTMX) Q: $($WebEvent.Query | ConvertTo-Json -Compress)"

	try {
		$idRaw = Get-ItemRequestValue -WebRequestEvent $WebEvent -Name 'id'
		$id = 0
		if (-not $idRaw -or -not [int]::TryParse([string]$idRaw, [ref]$id) -or $id -le 0) {
			Write-ItemErrorResponse `
				-WebRequestEvent $WebEvent `
				-StatusCode 400 `
				-Message 'Invalid or missing id'
			return
		}

		if (-not (Remove-CrudItem -DataSource $db -Id $id)) {
			Write-ItemErrorResponse `
				-WebRequestEvent $WebEvent `
				-StatusCode 404 `
				-Message 'Item not found'
			return
		}

		Write-FormattedLog -tag 'debug' -log "Item deleted successfully: id=$id"
		$page = Get-RequestedItemPage -DataSource $db -WebRequestEvent $WebEvent
		Write-ItemPageResponse `
			-WebRequestEvent $WebEvent `
			-PageData $page `
			-JsonValue @{ id = $id; message = 'Item deleted successfully' }
	} catch {
		Write-FormattedLog -tag 'error' -log "Error deleting item: $($_.Exception.Message)"
		Write-ItemErrorResponse `
			-WebRequestEvent $WebEvent `
			-StatusCode 500 `
			-Message 'Internal server error'
	}
}

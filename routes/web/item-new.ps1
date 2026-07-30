# HTML-only fragment consumed by the CRUD Manager add-item dialog.
Add-PodeRoute -Path '/htmx/item-new' -Method Get -ScriptBlock {
	Write-PodeViewResponse -Path 'layouts/bare' -Data @{
		Components = @('crudmgr-new')
	}
}

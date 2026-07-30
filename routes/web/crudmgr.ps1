# Pages only render views; nothing POSTs to them (the only form targets
# /api/crud), so this route is GET-only.
Add-PodeRoute -Path '/crudmgr' -Method Get -ScriptBlock {
	Write-PodeViewResponse -Path 'layouts/main' -Data @{
		PageName = 'CRUDMgr'
		Title = 'CRUD Manager'
		Components = @('crudmgr')
	}
}

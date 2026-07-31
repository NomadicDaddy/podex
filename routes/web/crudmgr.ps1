# Pages only render views; nothing POSTs to them (the only form targets
# /api/crud), so this route is GET-only.
Add-PodeRoute -Path '/crudmgr' -Method Get -ScriptBlock {
	$database = (Get-PodeConfig).Podex.DBFile
	$page = Get-RequestedItemPage -DataSource $database -WebRequestEvent $WebEvent
	$data = Get-ItemViewData -PageData $page
	$data.Components = @('crudmgr')
	$data.PageName = 'CRUDMgr'
	$data.Title = 'CRUD Manager'
	Write-PodeViewResponse -Path 'layouts/main' -Data $data
}

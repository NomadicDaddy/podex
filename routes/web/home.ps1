# Pages only render views; nothing POSTs to them, so this route is GET-only.
Add-PodeRoute -Path '/' -Method Get -ScriptBlock {
	Write-PodeViewResponse -Path 'layouts/main' -Data @{
		PageName = 'Home'
		Title = 'Home'
		Components = @('about')
	}
}

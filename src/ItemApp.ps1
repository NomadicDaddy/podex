Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

function Test-HtmxRequest {
	[CmdletBinding()]
	[OutputType([bool])]
	param(
		[Parameter(Mandatory)]
		[System.Collections.IDictionary]$WebRequestEvent
	)

	return [string]$WebRequestEvent.Request.Headers['HX-Request'] -eq 'true'
}

function Get-ItemRequestValue {
	[CmdletBinding()]
	[OutputType([string])]
	param(
		[Parameter(Mandatory)]
		[System.Collections.IDictionary]$WebRequestEvent,
		[Parameter(Mandatory)]
		[string]$Name
	)

	foreach ($sourceName in @('Data', 'Query')) {
		$source = $WebRequestEvent[$sourceName]
		if ($source) {
			$value = $source[$Name]
			if ($null -ne $value) {
				return [string]$value
			}
		}
	}
	return ''
}

function Get-RequestedItemPage {
	[CmdletBinding()]
	[OutputType([hashtable])]
	param(
		[Parameter(Mandatory)]
		[string]$DataSource,
		[Parameter(Mandatory)]
		[System.Collections.IDictionary]$WebRequestEvent
	)

	return Get-ItemPage `
		-DataSource $DataSource `
		-Search (Get-ItemRequestValue -WebRequestEvent $WebRequestEvent -Name 'search') `
		-Page (Get-ItemRequestValue -WebRequestEvent $WebRequestEvent -Name 'page') `
		-PageSize (Get-ItemRequestValue -WebRequestEvent $WebRequestEvent -Name 'pageSize')
}

function Get-ItemViewData {
	[CmdletBinding()]
	[OutputType([hashtable])]
	param(
		[Parameter(Mandatory)]
		[hashtable]$PageData
	)

	$items = @(
		foreach ($row in $PageData.rows) {
			[PSCustomObject]@{
				CreatedAtDisplay = [System.Net.WebUtility]::HtmlEncode(
					[string]$row.created_at_display
				)
				Description = [System.Net.WebUtility]::HtmlEncode([string]$row.description)
				Id = [int]$row.id
				Item = [System.Net.WebUtility]::HtmlEncode([string]$row.item)
			}
		}
	)
	$pages = @(
		foreach ($page in $PageData.pages) {
			[PSCustomObject]@{
				IsActive = [bool]$page.isActive
				Number = [int]$page.number
			}
		}
	)

	return @{
		CurrentPage = [int]$PageData.currentPage
		EndIndex = [int]$PageData.endIndex
		HasNextPage = [bool]$PageData.hasNextPage
		HasPreviousPage = [bool]$PageData.hasPreviousPage
		Items = $items
		NextPage = $PageData.nextPage
		Pages = $pages
		PreviousPage = $PageData.previousPage
		Search = [System.Net.WebUtility]::HtmlEncode([string]$PageData.search)
		StartIndex = [int]$PageData.startIndex
		TotalItems = [int]$PageData.totalItems
	}
}

function Write-ItemPageResponse {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)]
		[System.Collections.IDictionary]$WebRequestEvent,
		[Parameter(Mandatory)]
		[hashtable]$PageData,
		[int]$JsonStatusCode = 200,
		[hashtable]$JsonValue = $PageData
	)

	if (Test-HtmxRequest -WebRequestEvent $WebRequestEvent) {
		$viewData = Get-ItemViewData -PageData $PageData
		Write-PodeViewResponse -Path 'components/crud-list' -Data $viewData -StatusCode 200
		return
	}
	Write-PodeJsonResponse -StatusCode $JsonStatusCode -Value $JsonValue
}

function Write-ItemErrorResponse {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)]
		[System.Collections.IDictionary]$WebRequestEvent,
		[Parameter(Mandatory)]
		[int]$StatusCode,
		[Parameter(Mandatory)]
		[string]$Message
	)

	if (Test-HtmxRequest -WebRequestEvent $WebRequestEvent) {
		Write-PodeViewResponse -Path 'components/crud-message' `
			-Data @{ Message = [System.Net.WebUtility]::HtmlEncode($Message) } `
			-StatusCode $StatusCode
		return
	}
	Write-PodeJsonResponse -StatusCode $StatusCode -Value @{ message = $Message }
}

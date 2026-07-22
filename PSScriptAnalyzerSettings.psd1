@{
	IncludeRules = @(
		'PSUseConsistentIndentation',
		'PSUseConsistentWhitespace',
		'PSPlaceOpenBrace',
		'PSPlaceCloseBrace',
		'PSUseCorrectCasing'
	)
	Rules = @{
		PSUseConsistentIndentation = @{
			Enable = $true
			IndentationSize = 4
			PipelineIndentationStyle = 'IncreaseIndentationForFirstPipeline'
			Kind = 'tab'
		}
		PSUseConsistentWhitespace = @{
			Enable = $true
			CheckInnerBraces = $true
			CheckOpenBrace = $true
			CheckOpenParen = $true
			CheckOperator = $true
			CheckPipe = $true
			CheckSeparator = $true
			CheckOuterBraces = $true
		}
		PSPlaceOpenBrace = @{
			Enable = $true
			OnSameLine = $true
			NewLineAfter = $true
			IgnoreOneLineBlock = $true
		}
		PSPlaceCloseBrace = @{
			Enable = $true
			NewLineAfter = $false
			IgnoreOneLineBlock = $true
		}
		PSUseCorrectCasing = @{
			Enable = $true
		}
	}
}

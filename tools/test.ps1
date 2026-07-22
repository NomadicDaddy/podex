$ErrorActionPreference = 'Stop'

Import-Module -Name 'Pester'

# Gate on Result, not FailedCount: a test file that throws during discovery produces a failed
# container with zero failed tests, which FailedCount would report as a pass.
$result = Invoke-Pester -Path "$PSScriptRoot/../tests/*.Tests.ps1" -PassThru
if ($result.Result -ne 'Passed') {
	exit 1
}

exit 0

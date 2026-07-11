'# required powershell modules'
# Install-Module -Name PSSQLite -MinimumVersion 1.1.0 -MaximumVersion 1.99.99 -Verbose # MIT
Install-Module -Name Pode -MinimumVersion 2.11.1 -MaximumVersion 2.99.99 -Verbose # MIT

'# development powershell modules'
Install-Module -Name Pester -MinimumVersion 5.6.1 -MaximumVersion 5.99.99 -Verbose # Apache 2.0
Install-Module -Name PSScriptAnalyzer -MinimumVersion 1.23.0 -MaximumVersion 1.99.99 -Verbose # MIT

'# required bun packages'
bun add htmx.org@next mustache tailwindcss @tailwindcss/cli

'# development bun packages'
bun add -D eslint globals @eslint/js prettier prettier-plugin-tailwindcss prettier-plugin-sql

'# quality checks'
bun smoke:qc

'# copy distribution files'
Copy-Item -Path './src/vendor/client-side-templates.js' -Destination './public/js/client-side-templates.js' -Force -Verbose
Copy-Item -Path './src/vendor/debug.js' -Destination './public/js/debug.js' -Force -Verbose
Copy-Item -Path './src/vendor/json-enc.js' -Destination './public/js/json-enc.js' -Force -Verbose
Copy-Item -Path './node_modules/htmx.org/dist/htmx.js' -Destination './public/js/htmx.js' -Force -Verbose
Copy-Item -Path './node_modules/htmx.org/dist/htmx.min.js' -Destination './public/js/htmx.min.js' -Force -Verbose
Copy-Item -Path './node_modules/mustache/mustache.js' -Destination './public/js/mustache.js' -Force -Verbose
Copy-Item -Path './node_modules/mustache/mustache.min.js' -Destination './public/js/mustache.min.js' -Force -Verbose

'# initialize database'
$db = './data/podex.db'
if (-not (Test-Path -Path './data')) {
	New-Item -ItemType Directory -Path './data' -Force | Out-Null
}
if ((Test-Path -Path $db)) {
	$confirm = Read-Host 'Do you want to reinitialize the database? (y/N)'
	if ($confirm -eq 'y') {
		Invoke-SqliteQuery -DataSource $db -Query (Get-Content -Path './api/debug/init.sql' -Raw) -Verbose
	}
}

export const browserAssets = [
	{ name: 'htmx.org', role: 'Copied into `public/js/htmx*.js`' },
	{ name: 'mustache', role: 'Copied into `public/js/mustache*.js`' },
	{ name: 'tailwindcss', role: 'Compiled into `public/css/output.css`' },
	{
		name: '@tailwindcss/typography',
		role: 'Compiled into `public/css/output.css`',
	},
];

/**
 * License patterns that require manual review before license documents can be generated.
 *
 * These cover restrictive, source-available, non-commercial, proprietary, and ambiguous
 * markers that are not permissive SPDX licenses. A package whose license string matches
 * any of these is classified as RESTRICTIVE by normalizeLicense, and the license gate
 * fails closed until an operator resolves or excludes it.
 */
export const restrictiveLicensePatterns = [
	'UNLICENSED',
	'SEE LICENSE IN',
	'BSL',
	'BUSL',
	'ELASTIC',
	'COMMONS CLAUSE',
	'CC-BY-NC',
	'CC BY-NC',
	'PROPRIETARY',
];

/**
 * Returns true when a raw license string matches a restrictive, source-available,
 * non-commercial, proprietary, or ambiguous pattern.
 *
 * The comparison is case-insensitive substring matching against each entry in
 * restrictiveLicensePatterns. This intentionally errs toward flagging compound
 * SPDX expressions containing a restrictive term (e.g. "MIT AND BSL-1.1").
 */
export function isRestrictiveLicense(raw) {
	const upper = raw.toUpperCase();
	return restrictiveLicensePatterns.some((pattern) => upper.includes(pattern.toUpperCase()));
}

export const externalModules = [
	{
		license: 'MIT',
		name: 'Pode',
		role: 'Runtime PowerShell module',
		source: 'https://github.com/Badgerati/Pode',
		version: '>=2.11.1 <3.0.0',
	},
	{
		license: 'MIT',
		name: 'PSSQLite',
		role: 'Runtime PowerShell module',
		source: 'https://github.com/RamblingCookieMonster/PSSQLite',
		version: '>=1.1.0 <2.0.0',
	},
	{
		license: 'Apache-2.0',
		name: 'Pester',
		role: 'Development and test PowerShell module',
		source: 'https://github.com/pester/Pester',
		version: '>=5.6.1 <6.0.0',
	},
	{
		license: 'MIT',
		name: 'PSScriptAnalyzer',
		role: 'Development and lint PowerShell module',
		source: 'https://github.com/PowerShell/PSScriptAnalyzer',
		version: '>=1.23.0 <2.0.0',
	},
];

export const vendoredAssets = [
	{
		license: '0BSD',
		name: 'htmx client-side-templates extension',
		paths: '`src/vendor/client-side-templates.js`',
		source: 'https://github.com/bigskysoftware/htmx/tree/v1.9.12/src/ext',
	},
	{
		license: '0BSD',
		name: 'htmx debug extension',
		paths: '`src/vendor/debug.js`',
		source: 'https://github.com/bigskysoftware/htmx/tree/v1.9.12/src/ext',
	},
	{
		license: '0BSD',
		name: 'htmx json-enc extension',
		paths: '`src/vendor/json-enc.js`',
		source: 'https://github.com/bigskysoftware/htmx/tree/v1.9.12/src/ext',
	},
];

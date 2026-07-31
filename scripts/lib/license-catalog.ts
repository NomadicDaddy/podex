export interface BrowserAsset {
	name: string;
	role: string;
}

export interface ExternalModule {
	license: string;
	name: string;
	role: string;
	source: string;
	version: string;
}

export interface TextAssertion {
	message: string;
	path: string;
	text: string;
}

export const applicationName = 'Podex';

export const browserAssets: readonly BrowserAsset[] = [
	{ name: 'htmx.org', role: 'Copied into `public/js/htmx.js`' },
];

export const distributionNotes: readonly string[] = [];

export const releaseTextAssertions: readonly TextAssertion[] = [
	{
		message: 'Browser-delivered stylesheet omits the About page content styles.',
		path: 'public/css/podex.css',
		text: '.podex-content',
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

/** License families reviewed for Podex's installed npm tooling and emitted browser assets. */
export const reviewedLicenses = new Set([
	'0BSD',
	'Apache-2.0',
	'BlueOak-1.0.0',
	'BSD-2-Clause',
	'BSD-3-Clause',
	'CC0-1.0',
	'ISC',
	'LGPL-3.0-or-later',
	'MIT',
	'MPL-2.0',
	'Python-2.0',
	'Unlicense',
]);

export const licenseAliases = { 'BSD-0-Clause': '0BSD' };

/**
 * Returns true when a raw license string matches a restrictive, source-available,
 * non-commercial, proprietary, or ambiguous pattern.
 *
 * The comparison is case-insensitive substring matching against each entry in
 * restrictiveLicensePatterns. This intentionally errs toward flagging compound
 * SPDX expressions containing a restrictive term (e.g. "MIT AND BSL-1.1").
 */
export function isRestrictiveLicense(raw: string): boolean {
	const upper = raw.toUpperCase();
	return restrictiveLicensePatterns.some((pattern) => upper.includes(pattern.toUpperCase()));
}

export const externalModules: readonly ExternalModule[] = [
	{
		license: 'MIT',
		name: 'Pode',
		role: 'Runtime PowerShell module',
		source: 'https://github.com/Badgerati/Pode',
		version: '>=2.12.1 <3.0.0',
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
		version: '>=6.0.0 <7.0.0',
	},
	{
		license: 'MIT',
		name: 'PSScriptAnalyzer',
		role: 'Development and lint PowerShell module',
		source: 'https://github.com/PowerShell/PSScriptAnalyzer',
		version: '>=1.23.0 <2.0.0',
	},
];

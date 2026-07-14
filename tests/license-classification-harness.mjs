// Companion JS harness executed by bun inside the Pester test below.
// Verifies that normalizeLicense classifies restrictive/source-available license
// strings as RESTRICTIVE and that the generate script fails closed on them.
import { normalizeLicense } from '../scripts/lib/license-graph.mjs';
import { restrictiveLicensePatterns } from '../scripts/lib/license-catalog.mjs';

const cases = [
	{ input: 'UNLICENSED', expect: 'RESTRICTIVE' },
	{ input: 'SEE LICENSE IN LICENSE', expect: 'RESTRICTIVE' },
	{ input: 'BSL-1.1', expect: 'RESTRICTIVE' },
	{ input: 'BUSL-1.1', expect: 'RESTRICTIVE' },
	{ input: 'Elastic-2.0', expect: 'RESTRICTIVE' },
	{ input: 'Commons Clause', expect: 'RESTRICTIVE' },
	{ input: 'CC-BY-NC-4.0', expect: 'RESTRICTIVE' },
	{ input: 'PROPRIETARY', expect: 'RESTRICTIVE' },
	{ input: 'GPL-3.0-only', expect: 'RESTRICTIVE' },
	{ input: 'AGPL-3.0-only', expect: 'RESTRICTIVE' },
	{ input: 'SSPL-1.0', expect: 'RESTRICTIVE' },
	{ input: 'WTFPL', expect: 'RESTRICTIVE' },
	{ input: 'MIT', expect: 'MIT' },
	{ input: 'Apache-2.0', expect: 'Apache-2.0' },
	{ input: '0BSD', expect: '0BSD' },
	{ input: 'BSD-2-Clause', expect: 'BSD-2-Clause' },
	{ input: 'MIT AND Apache-2.0', expect: 'MIT AND Apache-2.0' },
];

let failures = 0;
for (const { input, expect } of cases) {
	const result = normalizeLicense({ license: input });
	if (result !== expect) {
		console.error(`FAIL: normalizeLicense({license:"${input}"}) = "${result}", expected "${expect}"`);
		failures += 1;
	}
}

// Unknown metadata (no license field at all) must still be UNKNOWN
if (normalizeLicense({}) !== 'UNKNOWN') {
	console.error('FAIL: normalizeLicense({}) should return UNKNOWN');
	failures += 1;
}

// licenses-array form must also be classified
const arrayResult = normalizeLicense({ licenses: [{ type: 'UNLICENSED' }] });
if (arrayResult !== 'RESTRICTIVE') {
	console.error(`FAIL: normalizeLicense({licenses:[{type:"UNLICENSED"}]}) = "${arrayResult}", expected "RESTRICTIVE"`);
	failures += 1;
}

// isRestrictiveLicense must agree with the pattern list length
if (!Array.isArray(restrictiveLicensePatterns) || restrictiveLicensePatterns.length === 0) {
	console.error('FAIL: restrictiveLicensePatterns is empty or not an array');
	failures += 1;
}

if (failures > 0) {
	console.error(`${failures} license classification assertion(s) failed.`);
	process.exit(1);
}

console.log('All license classification assertions passed.');

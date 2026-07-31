// Companion TypeScript harness executed by Bun inside the Pester test below.
// Verifies that normalizeLicense classifies restrictive/source-available license
// strings as RESTRICTIVE and that the generate script fails closed on them.
import { restrictiveLicensePatterns } from '../scripts/lib/license-catalog.ts';
import { normalizeLicense } from '../scripts/lib/license-graph.ts';

const cases = [
	{ expect: 'RESTRICTIVE', input: 'UNLICENSED' },
	{ expect: 'RESTRICTIVE', input: 'SEE LICENSE IN LICENSE' },
	{ expect: 'RESTRICTIVE', input: 'BSL-1.1' },
	{ expect: 'RESTRICTIVE', input: 'BUSL-1.1' },
	{ expect: 'RESTRICTIVE', input: 'Elastic-2.0' },
	{ expect: 'RESTRICTIVE', input: 'Commons Clause' },
	{ expect: 'RESTRICTIVE', input: 'CC-BY-NC-4.0' },
	{ expect: 'RESTRICTIVE', input: 'PROPRIETARY' },
	{ expect: 'RESTRICTIVE', input: 'GPL-3.0-only' },
	{ expect: 'RESTRICTIVE', input: 'AGPL-3.0-only' },
	{ expect: 'RESTRICTIVE', input: 'SSPL-1.0' },
	{ expect: 'RESTRICTIVE', input: 'WTFPL' },
	{ expect: 'MIT', input: 'MIT' },
	{ expect: 'Apache-2.0', input: 'Apache-2.0' },
	{ expect: '0BSD', input: '0BSD' },
	{ expect: 'BSD-2-Clause', input: 'BSD-2-Clause' },
	{ expect: 'MIT AND Apache-2.0', input: 'MIT AND Apache-2.0' },
];

let failures = 0;
for (const { expect, input } of cases) {
	const result = normalizeLicense({ license: input });
	if (result !== expect) {
		console.error(
			`FAIL: normalizeLicense({license:"${input}"}) = "${result}", expected "${expect}"`,
		);
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
	console.error(
		`FAIL: normalizeLicense({licenses:[{type:"UNLICENSED"}]}) = "${arrayResult}", expected "RESTRICTIVE"`,
	);
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

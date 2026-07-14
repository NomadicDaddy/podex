import { join, relative } from 'node:path';

import { reviewLicenseExpression } from './license-core/expression.ts';
import { collectInstalledPackages } from './license-core/installed.ts';
import { licenseOf, readJson } from './license-core/manifest.ts';
import { readLicenseText } from './license-core/resolve.ts';
import { isRestrictiveLicense, licenseAliases, reviewedLicenses } from './license-catalog.mjs';

export { readJson as readManifest } from './license-core/manifest.ts';

export function normalizeLicense(manifest) {
	const raw = licenseOf(manifest);
	if (raw === 'UNKNOWN') return raw;
	if (isRestrictiveLicense(raw)) return 'RESTRICTIVE';
	const review = reviewLicenseExpression(raw, {
		aliases: licenseAliases,
		reviewed: reviewedLicenses,
	});
	return review.ok ? raw : 'RESTRICTIVE';
}

export async function packageInfo(root, name) {
	const directory = join(root, 'node_modules', ...name.split('/'));
	const manifest = await readJson(join(directory, 'package.json'));
	if (manifest === null) throw new Error(`Unable to resolve installed package ${name}`);
	return {
		directory,
		license: normalizeLicense(manifest),
		manifest,
		manifestPath: join(directory, 'package.json'),
		name: manifest.name,
		version: manifest.version,
	};
}

export async function collectClosure(root) {
	return (await collectInstalledPackages(root, [])).map((entry) => ({
		...entry,
		license: normalizeLicense(entry.manifest),
		manifestPath: join(entry.directory, 'package.json'),
	}));
}

export async function findLicenseText(root, directory) {
	const text = await readLicenseText(directory);
	if (text === null) throw new Error(`No license file found in ${relative(root, directory)}`);
	return text;
}

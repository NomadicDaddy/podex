import { join, relative } from 'node:path';

import { isRestrictiveLicense, licenseAliases, reviewedLicenses } from './license-catalog.ts';
import { reviewLicenseExpression } from './license-core/expression.ts';
import { collectInstalledPackages, type InstalledPackage } from './license-core/installed.ts';
import { licenseOf, type PackageManifest, readJson } from './license-core/manifest.ts';
import { readLicenseText } from './license-core/resolve.ts';

export { readJson as readManifest } from './license-core/manifest.ts';

export interface LicensePackage extends InstalledPackage {
	manifestPath: string;
}

export function normalizeLicense(manifest: null | PackageManifest): string {
	const raw = licenseOf(manifest);
	if (raw === 'UNKNOWN') return raw;
	if (isRestrictiveLicense(raw)) return 'RESTRICTIVE';
	const review = reviewLicenseExpression(raw, {
		aliases: licenseAliases,
		reviewed: reviewedLicenses,
	});
	return review.ok ? raw : 'RESTRICTIVE';
}

export async function packageInfo(root: string, name: string): Promise<LicensePackage> {
	const directory = join(root, 'node_modules', ...name.split('/'));
	const manifest = await readJson(join(directory, 'package.json'));
	if (manifest === null) throw new Error(`Unable to resolve installed package ${name}`);
	if (typeof manifest.name !== 'string' || typeof manifest.version !== 'string') {
		throw new Error(`Installed package ${name} has no valid name or version.`);
	}
	return {
		directory,
		license: normalizeLicense(manifest),
		manifest,
		manifestPath: join(directory, 'package.json'),
		name: manifest.name,
		version: manifest.version,
	};
}

export async function collectClosure(root: string): Promise<LicensePackage[]> {
	return (await collectInstalledPackages(root, [])).map((entry) => ({
		...entry,
		license: normalizeLicense(entry.manifest),
		manifestPath: join(entry.directory, 'package.json'),
	}));
}

export async function findLicenseText(root: string, directory: string): Promise<string> {
	const text = await readLicenseText(directory);
	if (text === null) throw new Error(`No license file found in ${relative(root, directory)}`);
	return text;
}

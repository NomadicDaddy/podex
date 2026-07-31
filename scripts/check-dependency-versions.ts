import { readFile } from 'node:fs/promises';
import { join } from 'node:path';

const EXACT_SEMVER_PATTERN =
	/^\d+\.\d+\.\d+(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$/;
const EXPECTED_PACKAGE_MANAGER = 'bun@1.3.14';
const EXPECTED_BUN_ENGINE = '>=1.3.14';

interface PackageManifest {
	dependencies?: Record<string, string>;
	devDependencies?: Record<string, string>;
	engines?: Record<string, string>;
	optionalDependencies?: Record<string, string>;
	overrides?: Record<string, string>;
	packageManager?: string;
	peerDependencies?: Record<string, string>;
	resolutions?: Record<string, string>;
}

function dependencySpecs(manifest: PackageManifest): Record<string, string> {
	return Object.assign(
		{},
		manifest.dependencies,
		manifest.devDependencies,
		manifest.optionalDependencies,
		manifest.peerDependencies,
		manifest.overrides,
		manifest.resolutions,
	);
}

async function main(): Promise<void> {
	const manifestPath = join(process.cwd(), 'package.json');
	const manifest = JSON.parse(await readFile(manifestPath, 'utf8')) as PackageManifest;
	const invalidSpecs = Object.entries(dependencySpecs(manifest)).filter(
		([, spec]) => !EXACT_SEMVER_PATTERN.test(spec),
	);
	const errors: string[] = [];

	if (manifest.packageManager !== EXPECTED_PACKAGE_MANAGER) {
		errors.push(
			`packageManager must be "${EXPECTED_PACKAGE_MANAGER}", found "${manifest.packageManager ?? 'missing'}".`,
		);
	}
	if (manifest.engines?.['bun'] !== EXPECTED_BUN_ENGINE) {
		errors.push(
			`engines.bun must be "${EXPECTED_BUN_ENGINE}", found "${manifest.engines?.['bun'] ?? 'missing'}".`,
		);
	}
	for (const [name, spec] of invalidSpecs) {
		errors.push(`${name} must use an exact semantic version, found "${spec}".`);
	}

	if (errors.length > 0) {
		throw new Error(`Dependency contract failed:\n- ${errors.join('\n- ')}`);
	}

	console.log(
		`Dependency contract passed: Bun identity is declared and ${Object.keys(dependencySpecs(manifest)).length} dependencies are exactly pinned.`,
	);
}

main().catch((error: unknown) => {
	console.error(error instanceof Error ? error.message : String(error));
	process.exitCode = 1;
});

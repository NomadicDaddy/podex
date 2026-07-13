import { cp, mkdir, readFile, rm } from 'node:fs/promises';
import { dirname, join, relative, resolve } from 'node:path';

import { resolveContained } from './lib/release-paths.mjs';

const root = process.cwd();

async function readJson(path) {
	return JSON.parse(await readFile(path, 'utf8'));
}

function safeStagePath(version) {
	const dist = resolve(root, 'dist');
	const stage = resolve(dist, `podex-${version}`);
	if (dirname(stage) !== dist) throw new Error(`Unsafe release stage: ${stage}`);
	return stage;
}

async function copyEntry(stage, entry) {
	const source = resolveContained(root, entry);
	const destination = resolveContained(stage, entry);
	await mkdir(dirname(destination), { recursive: true });
	await cp(source, destination, { force: true, recursive: true });
}

async function main() {
	const manifest = await readJson(join(root, 'release-manifest.json'));
	const packageManifest = await readJson(join(root, 'package.json'));
	const stage = safeStagePath(packageManifest.version);

	await rm(stage, { force: true, recursive: true });
	await mkdir(stage, { recursive: true });

	for (const directory of manifest.directories) await copyEntry(stage, directory);
	for (const file of manifest.files) await copyEntry(stage, file);

	console.log(`Staged Podex ${packageManifest.version} at ${relative(root, stage)}.`);
}

main().catch((error) => {
	console.error(error instanceof Error ? error.message : String(error));
	process.exitCode = 1;
});

import { spawnSync } from 'node:child_process';
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

function safeArchivePath(version) {
	const dist = resolve(root, 'dist');
	const archive = resolve(dist, `podex-${version}.zip`);
	if (dirname(archive) !== dist) throw new Error(`Unsafe archive path: ${archive}`);
	return archive;
}

/**
 * Produce a zip archive from the staging directory CONTENTS so the archive root
 * matches the staging layout. Uses pwsh Compress-Archive (no new npm dependency).
 */
function createArchive(stage, archive) {
	const result = spawnSync(
		'pwsh',
		[
			'-NoLogo',
			'-NoProfile',
			'-ExecutionPolicy',
			'Bypass',
			'-Command',
			`Compress-Archive -Path '${stage.replace(/'/g, "''")}/*' -DestinationPath '${archive.replace(/'/g, "''")}' -Force`,
		],
		{ encoding: 'utf8' }
	);

	if (result.error) {
		const reason = result.error.code === 'ENOENT' ? 'pwsh not found' : result.error.message;
		throw new Error(`Unable to produce release archive: ${reason}`);
	}
	if (result.status !== 0) {
		const detail = result.stderr ? result.stderr.trim() : `exit code ${result.status}`;
		throw new Error(`Compress-Archive failed: ${detail}`);
	}
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
	const archive = safeArchivePath(packageManifest.version);

	await rm(stage, { force: true, recursive: true });
	await mkdir(stage, { recursive: true });

	for (const directory of manifest.directories) await copyEntry(stage, directory);
	for (const file of manifest.files) await copyEntry(stage, file);

	createArchive(stage, archive);

	console.log(
		`Staged Podex ${packageManifest.version} at ${relative(root, stage)} and archived to ${relative(root, archive)}.`
	);
}

main().catch((error) => {
	console.error(error instanceof Error ? error.message : String(error));
	process.exitCode = 1;
});

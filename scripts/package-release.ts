import { spawnSync } from 'node:child_process';
import { cp, mkdir, readFile, rm } from 'node:fs/promises';
import { dirname, join, relative, resolve } from 'node:path';

import { resolveContained } from './lib/release-paths.ts';

const root = process.cwd();

interface PackageIdentity {
	name: string;
	version: string;
}

interface ReleaseManifest {
	directories: string[];
	files: string[];
}

async function readJson<T>(path: string): Promise<T> {
	return JSON.parse(await readFile(path, 'utf8')) as T;
}

function safeArtifactName(name: string): string {
	if (!/^[a-z0-9][a-z0-9._-]*$/i.test(name)) {
		throw new Error(`Unsafe package name for release artifact: ${name}`);
	}
	return name;
}

function safeStagePath(name: string, version: string): string {
	const dist = resolve(root, 'dist');
	const stage = resolve(dist, `${safeArtifactName(name)}-${version}`);
	if (dirname(stage) !== dist) throw new Error(`Unsafe release stage: ${stage}`);
	return stage;
}

function safeArchivePath(name: string, version: string): string {
	const dist = resolve(root, 'dist');
	const archive = resolve(dist, `${safeArtifactName(name)}-${version}.zip`);
	if (dirname(archive) !== dist) throw new Error(`Unsafe archive path: ${archive}`);
	return archive;
}

/**
 * Produce a zip archive from the staging directory CONTENTS so the archive root
 * matches the staging layout. Uses pwsh Compress-Archive (no new npm dependency).
 */
function createArchive(stage: string, archive: string): void {
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
		{ encoding: 'utf8' },
	);

	if (result.error) {
		const reason =
			'code' in result.error && result.error.code === 'ENOENT'
				? 'pwsh not found'
				: result.error.message;
		throw new Error(`Unable to produce release archive: ${reason}`);
	}
	if (result.status !== 0) {
		const detail = result.stderr ? result.stderr.trim() : `exit code ${result.status}`;
		throw new Error(`Compress-Archive failed: ${detail}`);
	}
}

async function copyEntry(stage: string, entry: string): Promise<void> {
	const source = resolveContained(root, entry);
	const destination = resolveContained(stage, entry);
	await mkdir(dirname(destination), { recursive: true });
	await cp(source, destination, { force: true, recursive: true });
}

async function main(): Promise<void> {
	const manifest = await readJson<ReleaseManifest>(join(root, 'release-manifest.json'));
	const packageManifest = await readJson<PackageIdentity>(join(root, 'package.json'));
	const stage = safeStagePath(packageManifest.name, packageManifest.version);
	const archive = safeArchivePath(packageManifest.name, packageManifest.version);

	await rm(stage, { force: true, recursive: true });
	await mkdir(stage, { recursive: true });

	for (const directory of manifest.directories) await copyEntry(stage, directory);
	for (const file of manifest.files) await copyEntry(stage, file);

	createArchive(stage, archive);

	console.log(
		`Staged ${packageManifest.name} ${packageManifest.version} at ${relative(root, stage)} and archived to ${relative(root, archive)}.`,
	);
}

main().catch((error) => {
	console.error(error instanceof Error ? error.message : String(error));
	process.exitCode = 1;
});

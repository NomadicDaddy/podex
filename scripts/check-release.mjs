import { spawnSync } from 'node:child_process';
import { access, mkdir, readFile, readdir, rm } from 'node:fs/promises';
import { dirname, join, relative, resolve } from 'node:path';

import { resolveContained } from './lib/release-paths.mjs';

const root = process.cwd();

async function exists(path) {
	try {
		await access(path);
		return true;
	} catch {
		return false;
	}
}

async function readJson(path) {
	return JSON.parse(await readFile(path, 'utf8'));
}

function safeArchivePath(version) {
	const dist = resolve(root, 'dist');
	const archive = resolve(dist, `podex-${version}.zip`);
	if (dirname(archive) !== dist) throw new Error(`Unsafe archive path: ${archive}`);
	return archive;
}

/**
 * Run every content assertion against a tree root (the extracted archive).
 * Throws on the first violation so the gate fails closed.
 */
async function verifyTree(treeRoot) {
	const manifest = await readJson(join(root, 'release-manifest.json'));

	const missing = [];
	for (const entry of [...manifest.directories, ...manifest.files]) {
		if (!(await exists(resolveContained(treeRoot, entry)))) missing.push(entry);
	}
	if (missing.length > 0) {
		throw new Error(`Release is missing required entries:\n- ${missing.join('\n- ')}`);
	}

	const forbiddenEntries = [
		'node_modules',
		'.git',
		'data/podex.db',
		'public/js/debug.js',
		'public/js/htmx.min.js',
		'public/js/mustache.min.js',
	];
	for (const forbidden of forbiddenEntries) {
		if (await exists(join(treeRoot, forbidden))) {
			throw new Error(`Release contains forbidden entry: ${forbidden}`);
		}
	}

	const notices = await readFile(join(treeRoot, 'THIRD_PARTY_NOTICES.md'), 'utf8');
	const summary = await readFile(join(treeRoot, 'THIRD_PARTY_LICENSES.md'), 'utf8');
	const requiredNoticeText = ['Copyright (c) 2009 Chris Wanstrath', 'htmx.org@', 'mustache@'];
	for (const text of requiredNoticeText) {
		if (!notices.includes(text)) throw new Error(`Third-party notices omit: ${text}`);
	}
	if (!summary.includes('excludes `node_modules`')) {
		throw new Error('Third-party summary omits the node_modules distribution boundary.');
	}
	if (
		!summary.includes(
			'Platform-specific optional build packages are intentionally not serialized'
		)
	) {
		throw new Error('Third-party summary omits the platform-neutral generation policy.');
	}
	if (!summary.includes('## Copyleft and weak-copyleft build components')) {
		throw new Error('Third-party summary omits the copyleft build-component disclosure.');
	}
	if (!summary.includes('Lightning CSS')) {
		throw new Error('Third-party summary omits the Lightning CSS distribution boundary.');
	}
	const mustacheAsset = await readFile(join(treeRoot, 'public/js/mustache.js'), 'utf8');
	const stylesheet = await readFile(join(treeRoot, 'public/css/output.css'), 'utf8');
	if (!mustacheAsset.includes('Copyright (c) 2009 Chris Wanstrath')) {
		throw new Error('Browser-delivered Mustache asset omits its copyright notice.');
	}
	if (!stylesheet.includes('Copyright (c) Tailwind Labs, Inc.')) {
		throw new Error('Browser-delivered stylesheet omits the Tailwind copyright notice.');
	}
	if (!stylesheet.includes('.podex-content')) {
		throw new Error('Browser-delivered stylesheet omits the About page content styles.');
	}

	const stagedNoticeFiles = ['LICENSE', 'THIRD_PARTY_LICENSES.md', 'THIRD_PARTY_NOTICES.md'];
	for (const file of stagedNoticeFiles) {
		const source = await readFile(join(root, file));
		const staged = await readFile(join(treeRoot, file));
		if (!source.equals(staged)) throw new Error(`Staged notice differs from source: ${file}`);
	}
}

/**
 * Extract the release archive into a scratch directory under dist/ using pwsh
 * Expand-Archive (same spawn pattern as package-release.mjs). Returns the
 * scratch path; the caller MUST remove it afterward.
 */
function extractArchive(archive, scratch) {
	const result = spawnSync(
		'pwsh',
		[
			'-NoLogo',
			'-NoProfile',
			'-ExecutionPolicy',
			'Bypass',
			'-Command',
			`Expand-Archive -Path '${archive.replace(/'/g, "''")}' -DestinationPath '${scratch.replace(/'/g, "''")}' -Force`,
		],
		{ encoding: 'utf8' }
	);

	if (result.error) {
		const reason = result.error.code === 'ENOENT' ? 'pwsh not found' : result.error.message;
		throw new Error(`Unable to extract release archive: ${reason}`);
	}
	if (result.status !== 0) {
		const detail = result.stderr ? result.stderr.trim() : `exit code ${result.status}`;
		throw new Error(`Expand-Archive failed: ${detail}`);
	}
}

async function main() {
	const packageManifest = await readJson(join(root, 'package.json'));
	const version = packageManifest.version;
	const archive = safeArchivePath(version);

	if (!(await exists(archive))) {
		throw new Error(
			`Release archive not found: ${relative(root, archive)}\nRun 'bun run release:package' first.`
		);
	}

	const dist = resolve(root, 'dist');
	const scratch = join(dist, '.podex-release-verify');

	await rm(scratch, { force: true, recursive: true });
	try {
		await mkdir(scratch, { recursive: true });
		extractArchive(archive, scratch);

		const entries = await readdir(scratch);
		if (entries.length === 0) {
			throw new Error(`Extracted archive is empty: ${relative(root, archive)}`);
		}

		await verifyTree(scratch);

		console.log(
			`Verified ${relative(root, archive)}: ${entries.length} top-level entries and all notices present.`
		);
	} finally {
		await rm(scratch, { force: true, recursive: true });
	}
}

main().catch((error) => {
	console.error(error instanceof Error ? error.message : String(error));
	process.exitCode = 1;
});

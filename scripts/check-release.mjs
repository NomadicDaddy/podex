import { access, readFile, readdir } from 'node:fs/promises';
import { join, relative } from 'node:path';

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

async function main() {
	const manifest = await readJson(join(root, 'release-manifest.json'));
	const packageManifest = await readJson(join(root, 'package.json'));
	const stage = join(root, 'dist', `podex-${packageManifest.version}`);
	const missing = [];

	for (const entry of [...manifest.directories, ...manifest.files]) {
		if (!(await exists(resolveContained(stage, entry)))) missing.push(entry);
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
		if (await exists(join(stage, forbidden))) {
			throw new Error(`Release contains forbidden entry: ${forbidden}`);
		}
	}

	const notices = await readFile(join(stage, 'THIRD_PARTY_NOTICES.md'), 'utf8');
	const summary = await readFile(join(stage, 'THIRD_PARTY_LICENSES.md'), 'utf8');
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
	const mustacheAsset = await readFile(join(stage, 'public/js/mustache.js'), 'utf8');
	const stylesheet = await readFile(join(stage, 'public/css/output.css'), 'utf8');
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
		const staged = await readFile(join(stage, file));
		if (!source.equals(staged)) throw new Error(`Staged notice differs from source: ${file}`);
	}

	const entries = await readdir(stage);
	console.log(
		`Verified ${relative(root, stage)}: ${entries.length} top-level entries and all notices present.`
	);
}

main().catch((error) => {
	console.error(error instanceof Error ? error.message : String(error));
	process.exitCode = 1;
});

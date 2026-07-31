import { spawnSync } from 'node:child_process';
import { access, mkdir, readdir, readFile, rm, stat } from 'node:fs/promises';
import { dirname, extname, join, relative, resolve } from 'node:path';

import { browserAssets, releaseTextAssertions } from './lib/license-catalog.ts';
import { resolveContained } from './lib/release-paths.ts';

const root = process.cwd();
const publicAssetPattern = /\/public\/[A-Za-z0-9_./-]+\.(?:css|ico|js|png|svg|woff2?)/g;
const runtimeSourceExtensions = new Set(['.css', '.pode', '.ps1', '.psm1', '.ts']);
const runtimeSourcePaths = ['errors', 'podex.ps1', 'routes', 'src', 'views'];

interface PackageIdentity {
	name: string;
	version: string;
}

interface ReleaseManifest {
	directories: string[];
	files: string[];
}

async function exists(path: string): Promise<boolean> {
	try {
		await access(path);
		return true;
	} catch {
		return false;
	}
}

async function readJson<T>(path: string): Promise<T> {
	return JSON.parse(await readFile(path, 'utf8')) as T;
}

async function collectRuntimeFiles(path: string): Promise<string[]> {
	const info = await stat(path);
	if (info.isFile())
		return runtimeSourceExtensions.has(extname(path).toLowerCase()) ? [path] : [];

	const files: string[] = [];
	for (const entry of await readdir(path, { withFileTypes: true })) {
		const child = join(path, entry.name);
		if (entry.isDirectory()) files.push(...(await collectRuntimeFiles(child)));
		else if (entry.isFile() && runtimeSourceExtensions.has(extname(child).toLowerCase())) {
			files.push(child);
		}
	}
	return files;
}

async function referencedPublicAssets(): Promise<string[]> {
	const references = new Set<string>();
	for (const sourcePath of runtimeSourcePaths) {
		for (const file of await collectRuntimeFiles(join(root, sourcePath))) {
			const content = await readFile(file, 'utf8');
			for (const match of content.matchAll(publicAssetPattern)) {
				const reference = match[0];
				if (reference !== undefined) references.add(reference.slice(1));
			}
		}
	}
	return [...references].sort();
}

function manifestIncludes(manifest: ReleaseManifest, path: string): boolean {
	return (
		manifest.files.includes(path) ||
		manifest.directories.some((directory) => path.startsWith(`${directory}/`))
	);
}

function safeArtifactName(name: string): string {
	if (!/^[a-z0-9][a-z0-9._-]*$/i.test(name)) {
		throw new Error(`Unsafe package name for release artifact: ${name}`);
	}
	return name;
}

function safeArchivePath(name: string, version: string): string {
	const dist = resolve(root, 'dist');
	const archive = resolve(dist, `${safeArtifactName(name)}-${version}.zip`);
	if (dirname(archive) !== dist) throw new Error(`Unsafe archive path: ${archive}`);
	return archive;
}

/**
 * Run every content assertion against a tree root (the extracted archive).
 * Throws on the first violation so the gate fails closed.
 */
async function verifyTree(treeRoot: string): Promise<void> {
	const manifest = await readJson<ReleaseManifest>(join(root, 'release-manifest.json'));
	const undeclaredAssets = (await referencedPublicAssets()).filter(
		(asset) => !manifestIncludes(manifest, asset),
	);
	if (undeclaredAssets.length > 0) {
		throw new Error(
			`Release manifest omits runtime-referenced public assets:\n- ${undeclaredAssets.join('\n- ')}`,
		);
	}

	const missing = [];
	for (const entry of [...manifest.directories, ...manifest.files]) {
		if (!(await exists(resolveContained(treeRoot, entry)))) missing.push(entry);
	}
	if (missing.length > 0) {
		throw new Error(`Release is missing required entries:\n- ${missing.join('\n- ')}`);
	}

	const forbiddenEntries = ['node_modules', '.git', 'data', 'public/js/debug.js'];
	for (const forbidden of forbiddenEntries) {
		if (await exists(join(treeRoot, forbidden))) {
			throw new Error(`Release contains forbidden entry: ${forbidden}`);
		}
	}

	const notices = await readFile(join(treeRoot, 'THIRD_PARTY_NOTICES.md'), 'utf8');
	const summary = await readFile(join(treeRoot, 'THIRD_PARTY_LICENSES.md'), 'utf8');
	const requiredNoticeText = browserAssets.map((asset) => `${asset.name}@`);
	for (const text of requiredNoticeText) {
		if (!notices.includes(text)) throw new Error(`Third-party notices omit: ${text}`);
	}
	if (!summary.includes('excludes `node_modules`')) {
		throw new Error('Third-party summary omits the node_modules distribution boundary.');
	}
	if (
		!summary.includes(
			'Platform-specific optional build packages are intentionally not serialized',
		)
	) {
		throw new Error('Third-party summary omits the platform-neutral generation policy.');
	}
	if (!summary.includes('## Copyleft and weak-copyleft build components')) {
		throw new Error('Third-party summary omits the copyleft build-component disclosure.');
	}
	for (const assertion of releaseTextAssertions) {
		const content = await readFile(join(treeRoot, assertion.path), 'utf8');
		if (!content.includes(assertion.text)) {
			throw new Error(assertion.message);
		}
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
 * Expand-Archive (same spawn pattern as package-release.ts). Returns the
 * scratch path; the caller MUST remove it afterward.
 */
function extractArchive(archive: string, scratch: string): void {
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
		{ encoding: 'utf8' },
	);

	if (result.error) {
		const reason =
			'code' in result.error && result.error.code === 'ENOENT'
				? 'pwsh not found'
				: result.error.message;
		throw new Error(`Unable to extract release archive: ${reason}`);
	}
	if (result.status !== 0) {
		const detail = result.stderr ? result.stderr.trim() : `exit code ${result.status}`;
		throw new Error(`Expand-Archive failed: ${detail}`);
	}
}

async function main(): Promise<void> {
	const packageManifest = await readJson<PackageIdentity>(join(root, 'package.json'));
	const version = packageManifest.version;
	const archive = safeArchivePath(packageManifest.name, version);

	if (!(await exists(archive))) {
		throw new Error(
			`Release archive not found: ${relative(root, archive)}\nRun 'bun run release:package' first.`,
		);
	}

	const dist = resolve(root, 'dist');
	const scratch = join(dist, `.${safeArtifactName(packageManifest.name)}-release-verify`);

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
			`Verified ${relative(root, archive)}: ${entries.length} top-level entries and all notices present.`,
		);
	} finally {
		await rm(scratch, { force: true, recursive: true });
	}
}

main().catch((error) => {
	console.error(error instanceof Error ? error.message : String(error));
	process.exitCode = 1;
});

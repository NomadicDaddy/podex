import { access, readFile, realpath, readdir } from 'node:fs/promises';
import { dirname, join, relative } from 'node:path';

function normalizeLicense(manifest) {
	if (typeof manifest.license === 'string') return manifest.license;
	if (Array.isArray(manifest.licenses)) {
		return manifest.licenses
			.map((entry) => (typeof entry === 'string' ? entry : entry?.type))
			.filter(Boolean)
			.join(' OR ');
	}
	return 'UNKNOWN';
}

async function exists(path) {
	try {
		await access(path);
		return true;
	} catch {
		return false;
	}
}

async function resolveManifest(name, fromDirectory) {
	if (!/^(@[a-z\d][a-z\d._-]*\/)?[a-z\d][a-z\d._-]*$/i.test(name)) {
		throw new Error(`Invalid npm package name in dependency graph: ${name}`);
	}
	let directory = fromDirectory;
	while (true) {
		const candidate = join(directory, 'node_modules', ...name.split('/'), 'package.json');
		if (await exists(candidate)) return realpath(candidate);
		const parent = dirname(directory);
		if (parent === directory) break;
		directory = parent;
	}
	throw new Error(`Unable to resolve installed package ${name} from ${fromDirectory}`);
}

export async function readManifest(path) {
	return JSON.parse(await readFile(path, 'utf8'));
}

export async function packageInfo(root, name, fromDirectory = root) {
	const manifestPath = await resolveManifest(name, fromDirectory);
	const manifest = await readManifest(manifestPath);
	return {
		directory: dirname(manifestPath),
		license: normalizeLicense(manifest),
		manifest,
		manifestPath,
		name: manifest.name,
		version: manifest.version,
	};
}

export async function collectClosure(root, rootNames) {
	const packages = new Map();
	const queue = rootNames.map((name) => ({ fromDirectory: root, name, optional: false }));

	while (queue.length > 0) {
		const entry = queue.shift();
		let info;
		try {
			info = await packageInfo(root, entry.name, entry.fromDirectory);
		} catch (error) {
			if (entry.optional) continue;
			throw error;
		}

		if (packages.has(info.manifestPath)) continue;
		packages.set(info.manifestPath, info);
		for (const name of Object.keys(info.manifest.dependencies ?? {})) {
			queue.push({ fromDirectory: info.directory, name, optional: false });
		}
		for (const name of Object.keys(info.manifest.optionalDependencies ?? {})) {
			queue.push({ fromDirectory: info.directory, name, optional: true });
		}
	}

	return [...packages.values()].sort(
		(a, b) => a.name.localeCompare(b.name) || a.version.localeCompare(b.version)
	);
}

export async function findLicenseText(root, directory) {
	const names = await readdir(directory);
	const licenseName = names
		.filter((name) => /^(licen[cs]e|copying)(\..*)?$/i.test(name))
		.sort((a, b) => a.length - b.length || a.localeCompare(b))[0];
	if (!licenseName) throw new Error(`No license file found in ${relative(root, directory)}`);
	return readFile(join(directory, licenseName), 'utf8');
}

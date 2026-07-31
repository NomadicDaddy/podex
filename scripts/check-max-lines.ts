import { readdir, readFile, stat } from 'node:fs/promises';
import { join, relative, sep } from 'node:path';

const MAX_LINES = 300;
const scannedPaths = [
	'.build.ps1',
	'PSScriptAnalyzerSettings.psd1',
	'api',
	'errors',
	'eslint.config.ts',
	'podex.ps1',
	'routes',
	'scripts',
	'server.psd1',
	'src',
	'tools',
	'views',
];
const scannedExtensions = new Set(['.css', '.pode', '.ps1', '.psd1', '.psm1', '.ts']);
const skippedDirectories = new Set(['dist', 'node_modules', 'public']);

interface Finding {
	file: string;
	lines: number;
}

function extension(path: string): string {
	const index = path.lastIndexOf('.');
	return index === -1 ? '' : path.slice(index).toLowerCase();
}

async function collectFiles(path: string): Promise<string[]> {
	const info = await stat(path);
	if (info.isFile()) return scannedExtensions.has(extension(path)) ? [path] : [];

	const files: string[] = [];
	for (const entry of await readdir(path, { withFileTypes: true })) {
		if (entry.isDirectory() && skippedDirectories.has(entry.name)) continue;
		const child = join(path, entry.name);
		if (entry.isDirectory()) files.push(...(await collectFiles(child)));
		else if (entry.isFile() && scannedExtensions.has(extension(child))) files.push(child);
	}
	return files;
}

function countLines(content: string): number {
	if (content.length === 0) return 0;
	const normalized = content.endsWith('\n') ? content.slice(0, -1) : content;
	return normalized.split(/\r?\n/).length;
}

async function main(): Promise<void> {
	const root = process.cwd();
	const findings: Finding[] = [];

	for (const scannedPath of scannedPaths) {
		const absolutePath = join(root, scannedPath);
		try {
			for (const file of await collectFiles(absolutePath)) {
				const lines = countLines(await readFile(file, 'utf8'));
				if (lines > MAX_LINES) {
					findings.push({
						file: relative(root, file).split(sep).join('/'),
						lines,
					});
				}
			}
		} catch (error: unknown) {
			if ((error as NodeJS.ErrnoException).code !== 'ENOENT') throw error;
		}
	}

	if (findings.length > 0) {
		findings.sort((left, right) => right.lines - left.lines);
		const detail = findings.map(({ file, lines }) => `${file}: ${lines}`).join('\n- ');
		throw new Error(`${findings.length} file(s) exceed ${MAX_LINES} lines:\n- ${detail}`);
	}

	console.log(
		`Max-lines contract passed: runtime and tooling files are at most ${MAX_LINES} lines.`,
	);
}

main().catch((error: unknown) => {
	console.error(error instanceof Error ? error.message : String(error));
	process.exitCode = 1;
});

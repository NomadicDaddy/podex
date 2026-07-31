import { copyFile, mkdir } from 'node:fs/promises';
import { basename, dirname, join } from 'node:path';

const root = process.cwd();
type AssetPath = readonly [source: string, destination: string];

const copiedAssets: readonly AssetPath[] = [
	['node_modules/htmx.org/dist/htmx.js', 'public/js/htmx.js'],
];
const bundledAssets: readonly AssetPath[] = [
	['src/crudmgr.ts', 'public/js/crudmgr.js'],
	['src/podex.css', 'public/css/podex.css'],
];

async function copyAssets(): Promise<void> {
	for (const [source, destination] of copiedAssets) {
		const target = join(root, destination);
		await mkdir(dirname(target), { recursive: true });
		await copyFile(join(root, source), target);
	}
}

async function bundleAssets(): Promise<void> {
	for (const [source, destination] of bundledAssets) {
		const target = join(root, destination);
		await mkdir(dirname(target), { recursive: true });
		const result = await Bun.build({
			entrypoints: [join(root, source)],
			naming: basename(target),
			outdir: dirname(target),
			target: 'browser',
		});
		if (!result.success) {
			throw new AggregateError(result.logs, `Unable to bundle ${source}.`);
		}
	}
}

async function main(): Promise<void> {
	await copyAssets();
	await bundleAssets();
	console.log(`Built ${copiedAssets.length + bundledAssets.length} browser assets.`);
}

main().catch((error) => {
	console.error(error instanceof Error ? error.message : String(error));
	process.exitCode = 1;
});

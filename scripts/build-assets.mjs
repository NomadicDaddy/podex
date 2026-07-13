import { copyFile, mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';

const root = process.cwd();

const assets = [
	['src/vendor/client-side-templates.js', 'public/js/client-side-templates.js'],
	['src/vendor/debug.js', 'public/js/debug.js'],
	['src/vendor/json-enc.js', 'public/js/json-enc.js'],
	['node_modules/htmx.org/dist/htmx.js', 'public/js/htmx.js'],
	['node_modules/htmx.org/dist/htmx.min.js', 'public/js/htmx.min.js'],
];

const licensedAssets = [
	['node_modules/mustache/mustache.js', 'public/js/mustache.js'],
	['node_modules/mustache/mustache.min.js', 'public/js/mustache.min.js'],
];

function commentBlock(title, licenseText) {
	const lines = licenseText
		.trim()
		.replaceAll('*/', '* /')
		.split(/\r?\n/)
		.map((line) => (line ? ` * ${line}` : ' *'))
		.join('\n');
	return `/*!\n * ${title}\n *\n${lines}\n */\n`;
}

async function writeLicensedAssets() {
	const license = await readFile(join(root, 'node_modules/mustache/LICENSE'), 'utf8');
	const banner = commentBlock('mustache.js third-party license', license);

	for (const [source, destination] of licensedAssets) {
		const target = join(root, destination);
		await mkdir(dirname(target), { recursive: true });
		await writeFile(target, banner + (await readFile(join(root, source), 'utf8')), 'utf8');
	}
}

async function addStylesheetNotices() {
	const outputPath = join(root, 'public/css/output.css');
	const packages = [
		['Tailwind CSS', 'node_modules/tailwindcss/LICENSE'],
		['Tailwind CSS Typography', 'node_modules/@tailwindcss/typography/LICENSE'],
	];
	const banners = [];

	for (const [name, licensePath] of packages) {
		const license = await readFile(join(root, licensePath), 'utf8');
		banners.push(commentBlock(`${name} third-party license`, license));
	}

	await writeFile(outputPath, banners.join('') + (await readFile(outputPath, 'utf8')), 'utf8');
}

async function main() {
	for (const [source, destination] of assets) {
		const target = join(root, destination);
		await mkdir(dirname(target), { recursive: true });
		await copyFile(join(root, source), target);
	}
	await writeLicensedAssets();
	await addStylesheetNotices();

	console.log(`Built ${assets.length + licensedAssets.length} browser JavaScript assets.`);
}

main().catch((error) => {
	console.error(error instanceof Error ? error.message : String(error));
	process.exitCode = 1;
});

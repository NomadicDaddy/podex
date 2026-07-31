export {};

const ignoredDirectories = new Set([
	'.git',
	'.vscode',
	'data',
	'dist',
	'logs',
	'node_modules',
	'public',
]);
const javascript = new Bun.Glob('**/*.{cjs,js,jsx,mjs}');
const violations: string[] = [];

for await (const path of javascript.scan({ cwd: process.cwd(), onlyFiles: true })) {
	const [topLevel] = path.replaceAll('\\', '/').split('/');
	if (topLevel && ignoredDirectories.has(topLevel)) continue;
	violations.push(path);
}

if (violations.length > 0) {
	console.error('Project-owned JavaScript source is forbidden; use TypeScript:');
	for (const path of violations.sort()) console.error(`  - ${path}`);
	process.exit(1);
}

console.log('TypeScript-only source check passed.');

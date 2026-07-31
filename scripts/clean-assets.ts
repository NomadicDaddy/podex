import { rm } from 'node:fs/promises';
import { isAbsolute, relative, resolve, sep } from 'node:path';

const root = resolve(import.meta.dir, '..');
const generatedDirectories = [resolve(root, 'public/css'), resolve(root, 'public/js')];

function assertGeneratedDirectory(target: string): void {
	const relativePath = relative(root, target);
	if (
		relativePath.length === 0 ||
		isAbsolute(relativePath) ||
		relativePath === '..' ||
		relativePath.startsWith(`..${sep}`)
	) {
		throw new Error(`Refusing to remove generated assets outside the repository: ${target}`);
	}
}

for (const directory of generatedDirectories) {
	assertGeneratedDirectory(directory);
	await rm(directory, { force: true, recursive: true });
}

console.log('Removed generated browser assets.');

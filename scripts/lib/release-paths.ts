import { resolve, sep } from 'node:path';

export function resolveContained(base: string, entry: string): string {
	if (typeof entry !== 'string' || entry.trim() === '') {
		throw new Error('Release manifest entries must be non-empty strings.');
	}

	const resolvedBase = resolve(base);
	const target = resolve(resolvedBase, entry);
	if (!target.startsWith(`${resolvedBase}${sep}`)) {
		throw new Error(`Release manifest entry escapes its root: ${entry}`);
	}
	return target;
}

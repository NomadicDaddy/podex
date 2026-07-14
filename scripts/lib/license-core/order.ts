/** Locale-independent ordering for deterministic generated compliance documents. */
export function byCodepoint(a: string, b: string): number {
	if (a < b) return -1;
	return a > b ? 1 : 0;
}

import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const run = promisify(execFile);

const ASSET_PATH = 'public/js/mustache.js';
const REQUIRED_NOTICE = 'Copyright (c) 2009 Chris Wanstrath';

async function main() {
	const tag = process.argv[2];
	if (!tag) {
		throw new Error('Usage: bun scripts/check-tag-compliance.mjs <git-tag>');
	}

	let asset;
	try {
		const { stdout } = await run('git', ['show', `${tag}:${ASSET_PATH}`], {
			maxBuffer: 16 * 1024 * 1024,
		});
		asset = stdout;
	} catch (error) {
		const detail = error instanceof Error ? error.message : String(error);
		throw new Error(`Unable to read ${ASSET_PATH} from tag ${tag}: ${detail}`, {
			cause: error,
		});
	}

	if (!asset.includes(REQUIRED_NOTICE)) {
		throw new Error(
			`Tag ${tag} distributes ${ASSET_PATH} without its MIT notice ("${REQUIRED_NOTICE}").`
		);
	}
	console.log(`Tag ${tag} includes the required Mustache notice in ${ASSET_PATH}.`);
}

main().catch((error) => {
	console.error(error instanceof Error ? error.message : String(error));
	process.exitCode = 1;
});

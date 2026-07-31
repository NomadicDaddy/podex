// Preinstall guard: fail any install not driven by Bun. Package managers advertise themselves
// through npm_config_user_agent; Bun's value starts with "bun/".
const userAgent = process.env['npm_config_user_agent'] ?? '';

if (!userAgent.startsWith('bun/')) {
	console.error('Use "bun install" for installation in this project.');
	console.error("If you don't have Bun, see https://bun.sh/docs/installation");
	process.exit(1);
}

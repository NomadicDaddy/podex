#!/usr/bin/env bun
// Runs a POSIX shell script through a real bash, without trusting PATH to supply one.
//
// On Windows, C:\Windows\System32\bash.exe is the WSL launcher, and it shadows Git's bash for
// every process whose PATH does not already prepend Git's usr/bin — which is every PowerShell
// and cmd session. With no WSL distro installed it fails with
//   <3>WSL (12 - Relay) ERROR: CreateProcessCommon:818: execvpe(/bin/bash) failed
// so `bash scripts/check-leak-guard.sh` passes from Git Bash and fails from PowerShell on the
// same machine, and the failure lands in `bun install` (the prepare script) and in smoke:qc,
// where it reads as a broken repository rather than a shell that was never there. Resolution is
// therefore explicit: Git's own bash, found the way git itself reports where it lives, and the
// System32 launcher never.
//
// The shell scripts this runs (.githooks/leak-guard-setup.sh, scripts/check-leak-guard.sh) are
// kept byte-identical across the aidd, spernakit, and starsync repositories, so the portability
// fix cannot live inside them. It lives here, in the repository-local script that invokes them.
import { spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { argv, env, exit, platform } from 'node:process';

// .../Git/mingw64/libexec/git-core -> .../Git/bin/bash.exe
function bashBesideGit(): string | undefined {
	const located = spawnSync('git', ['--exec-path'], { encoding: 'utf8', windowsHide: true });
	if (located.status !== 0) return undefined;

	let directory = path.resolve(located.stdout.trim());
	for (let hop = 0; hop < 4; hop += 1) {
		directory = path.dirname(directory);
		const candidate = path.join(directory, 'bin', 'bash.exe');
		if (existsSync(candidate)) return candidate;
	}
	return undefined;
}

function installedGitBash(): string | undefined {
	const localPrograms = env['LOCALAPPDATA'];
	const roots = [
		env['ProgramFiles'],
		env['ProgramW6432'],
		env['ProgramFiles(x86)'],
		localPrograms === undefined ? undefined : path.join(localPrograms, 'Programs'),
	];
	return roots
		.filter((root): root is string => root !== undefined)
		.map((root) => path.join(root, 'Git', 'bin', 'bash.exe'))
		.find((candidate) => existsSync(candidate));
}

function resolveBash(): string {
	if (platform !== 'win32') return 'bash';

	const found = bashBesideGit() ?? installedGitBash();
	if (found !== undefined) return found;

	console.error('run-bash: no Git Bash found on this machine.');
	console.error(
		'run-bash: install Git for Windows, or put a POSIX bash ahead of System32 on PATH.',
	);
	console.error('run-bash: the System32 bash.exe is the WSL launcher and is never used here.');
	exit(1);
}

const [script, ...forwarded] = argv.slice(2);
if (script === undefined) {
	console.error('run-bash: usage: bun ./scripts/run-bash.ts <script.sh> [args...]');
	exit(1);
}

const run = spawnSync(resolveBash(), [script, ...forwarded], { stdio: 'inherit' });
exit(run.status ?? 1);

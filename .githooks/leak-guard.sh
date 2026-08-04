#!/usr/bin/env bash
# Re-leak guard for the public repository (two tiers).
#
# Tier 1 (tracked, below): generic high-signal secret formats and
# home-directory path shapes. Nothing machine- or fleet-specific.
# Tier 2 (untracked): private literals loaded from
#   ${LEAK_GUARD_PATTERNS:-$HOME/.config/leak-guard/patterns}
# (extended regexes, one per line; blank lines and # comments ignored).
# Seeded by .githooks/leak-guard-setup.sh (runs via the `prepare` script).
# If the file is absent the guard warns and runs tier 1 only.
#
# Scans staged ADDITIONS only. Bypass with `git commit --no-verify` for a
# confirmed false positive.
#
# Keep this file byte-identical between the aidd, spernakit, and starsync
# repos, and in sync with scripts/check-leak-guard.sh.
set -euo pipefail

added="$(git diff --cached --unified=0 --no-color -- . ':(exclude).githooks/leak-guard.sh' | grep -E '^\+' | grep -vE '^\+\+\+' || true)"
[ -z "$added" ] && exit 0

# Tier 1a: secret formats (case-insensitive like the rest of the scan).
secret_pattern='-----BEGIN [A-Z ]*PRIVATE KEY-----|AKIA[0-9A-Z]{16}|xox[baprs]-[0-9A-Za-z-]{10,}|gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{22,}|\bsk-[A-Za-z0-9_-]{20,}'

# Tier 1b: home-directory paths. Case-SENSITIVE so lowercase route-style
# paths (/users/:id) don't trip it.
path_pattern='[A-Za-z]:[\\/]+Users[\\/]+[A-Za-z0-9._-]+|/Users/[A-Za-z0-9._-]+/|/home/[a-z0-9._-]+/'

# -e keeps the leading '-----BEGIN …' from being parsed as a grep option.
secret_hits="$(printf '%s\n' "$added" | grep -nEi -e "$secret_pattern" || true)"
path_hits="$(printf '%s\n' "$added" | grep -nE -e "$path_pattern" || true)"

# Tier 2: private literals from the user-level pattern file.
#
# The pattern file is per-machine, not per-repo, so it names every private sibling — including
# whichever one is being committed to right now. A repository cannot leak its own identity to
# itself: the name is already its directory, its remote URL, and its package name, and it says it
# constantly in its own prose. Drop the patterns that fire on this repo's own name and keep the
# rest, so a private app still guards its siblings' names while being free to write its own.
# Without this the guard is unusable in a private app, which is why it was confined to the public
# repos before. A pattern that grep cannot compile is kept rather than dropped: fail closed.
patterns_file="${LEAK_GUARD_PATTERNS:-$HOME/.config/leak-guard/patterns}"
self_name="$(basename "$(git rev-parse --show-toplevel)")"
local_hits=''
if [ -f "$patterns_file" ]; then
	active="$(grep -vE '^[[:space:]]*(#|$)' "$patterns_file" || true)"
	active="$(printf '%s\n' "$active" | while IFS= read -r pattern; do
		[ -z "$pattern" ] && continue
		printf '%s\n' "$self_name" | grep -qEi -e "$pattern" 2>/dev/null || printf '%s\n' "$pattern"
	done)"
	if [ -n "$active" ]; then
		local_hits="$(printf '%s\n' "$added" | grep -nEi -f <(printf '%s\n' "$active") || true)"
	fi
else
	echo "leak-guard: no local pattern file ($patterns_file); generic checks only" >&2
fi

hits="$(printf '%s\n%s\n%s\n' "$secret_hits" "$path_hits" "$local_hits" | sed '/^$/d')"
if [ -n "$hits" ]; then
	echo "" >&2
	echo "x re-leak guard: staged changes contain forbidden private/secret patterns:" >&2
	printf '%s\n' "$hits" | head -20 >&2
	echo "" >&2
	echo "  Scrub these before committing. If genuinely a false positive," >&2
	echo "  bypass with: git commit --no-verify" >&2
	exit 1
fi
exit 0

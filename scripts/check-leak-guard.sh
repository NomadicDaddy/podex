#!/usr/bin/env bash
# Self-test for .githooks/leak-guard.sh.
#
# All leaky fixtures are assembled at RUNTIME by concatenation so this file
# never contains a string the guard would flag. Runs against a scratch git
# repo under a temp dir; the real user-level pattern file is never read
# (LEAK_GUARD_PATTERNS is always set explicitly).
#
# Keep this file byte-identical between the aidd, spernakit, and starsync repos.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
hook="$repo_root/.githooks/leak-guard.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

failures=0
fail() {
	echo "check-leak-guard: FAIL - $1" >&2
	failures=$((failures + 1))
}

synthetic="$tmp/patterns"
printf '%s\n' '# synthetic private patterns for the self-test' '' '\bzzz-synthetic-app\b' >"$synthetic"

# Scratch repo names are load-bearing for cases 9 and 10: the guard drops tier-2 patterns that
# match the repository's own directory name, so the two repos differ only in what they are called.
make_repo() {
	mkdir -p "$tmp/$1/.githooks"
	git -C "$tmp/$1" init -q
	git -C "$tmp/$1" -c user.email=t@test -c user.name=t commit -q --allow-empty -m init
	cp "$hook" "$tmp/$1/.githooks/leak-guard.sh"
}
make_repo repo
make_repo zzz-synthetic-app

# The repo the next run_guard call runs in. Cases 1-8 use the neutrally named one.
guard_repo="$tmp/repo"

# Stages $2 as file content and runs the guard with pattern file $1.
# Prints the guard's exit code; guard stderr lands in $tmp/stderr.
run_guard() {
	printf '%s\n' "$2" >"$guard_repo/staged.txt"
	git -C "$guard_repo" add staged.txt
	local code=0
	(cd "$guard_repo" && LEAK_GUARD_PATTERNS="$1" bash .githooks/leak-guard.sh) 2>"$tmp/stderr" || code=$?
	echo "$code"
}

# 1. Clean content passes.
[ "$(run_guard "$synthetic" 'plain harmless content')" = 0 ] || fail 'clean content was blocked'

# 2. Generic secret shape: runtime-built AWS access key id is blocked.
aws_key="AKIA$(printf 'A%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16)"
[ "$(run_guard "$synthetic" "key=$aws_key")" = 1 ] || fail 'synthetic AWS key was not blocked'

# 3. Generic secret shape: runtime-built PEM header is blocked.
pem_header="-----BEGIN RSA $(printf 'PRIVATE') KEY-----"
[ "$(run_guard "$synthetic" "$pem_header")" = 1 ] || fail 'synthetic PEM header was not blocked'

# 4. Home-directory path (runtime-built backslashes) is blocked.
bs="$(printf '\\')"
win_path="C:${bs}Users${bs}someone${bs}project"
[ "$(run_guard "$synthetic" "path=$win_path")" = 1 ] || fail 'home-directory path was not blocked'

# 5. Private literal from the pattern file is blocked.
[ "$(run_guard "$synthetic" 'mentions zzz-synthetic-app somewhere')" = 1 ] || fail 'local pattern was not blocked'

# 6. Lowercase route-style path is NOT blocked (path tier is case-sensitive).
[ "$(run_guard "$synthetic" 'GET /users/42/profile')" = 0 ] || fail 'route-style /users/ path was wrongly blocked'

# 7. Comment lines in the pattern file are inert: stage the comment's own
# text - it only gets blocked if the # line were treated as a pattern.
[ "$(run_guard "$synthetic" '# synthetic private patterns for the self-test')" = 0 ] || fail 'pattern-file comment line leaked into matching'

# 8. Missing pattern file: warns on stderr but passes clean content.
[ "$(run_guard "$tmp/does-not-exist" 'plain harmless content')" = 0 ] || fail 'missing pattern file blocked a clean commit'
grep -q 'no local pattern file' "$tmp/stderr" || fail 'missing pattern file did not warn'

# 9. A repository may write its own name. The pattern file is per-machine and names every private
# sibling, so in the repo that IS zzz-synthetic-app the pattern for it must be dropped - otherwise
# the guard blocks ordinary prose and the only workable answer is not installing it at all.
guard_repo="$tmp/zzz-synthetic-app"
[ "$(run_guard "$synthetic" 'mentions zzz-synthetic-app somewhere')" = 0 ] || fail 'repo was blocked by a pattern matching its own name'

# 10. Dropping the self-pattern must not disarm the rest: a sibling's name is still blocked in the
# same repo, which is the whole reason tier 2 exists.
printf '%s\n' '\bzzz-synthetic-app\b' '\bzzz-sibling-app\b' >"$tmp/patterns-pair"
[ "$(run_guard "$tmp/patterns-pair" 'mentions zzz-sibling-app somewhere')" = 1 ] || fail 'sibling pattern was dropped along with the self pattern'
[ "$(run_guard "$tmp/patterns-pair" 'mentions zzz-synthetic-app somewhere')" = 0 ] || fail 'self pattern survived alongside a sibling pattern'
guard_repo="$tmp/repo"

if [ "$failures" -gt 0 ]; then
	echo "check-leak-guard: $failures failure(s)" >&2
	exit 1
fi
echo 'check-leak-guard: all checks passed'

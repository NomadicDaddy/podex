#!/usr/bin/env bash
# Blocks a push that would publish .aidd/ metadata.
#
# A repository with its own push remote is "local-only": its .aidd/ blueprint must never be
# published, because Git history is retroactive and a public repo cannot be un-published. This
# guard is the enforcement point. Everything else (scaffolding, the ignore profiles) only covers
# repositories that were set up correctly; nothing else catches a repository that acquires a remote
# later, or a branch whose tip is clean while its history is not.
#
# Reads the pre-push stdin protocol: <local-ref> <local-sha> <remote-ref> <remote-sha> per line.
#
# Three checks, in cost order:
#   1. /.aidd/ is ignored at all.
#   2. Zero tracked .aidd paths.
#   3. Zero commits touching .aidd IN THE RANGE BEING PUSHED.
#
# Check 3 must be a HISTORY query (rev-list), never a tree query (ls-tree). Untracking .aidd today
# leaves the tip clean while every historical commit still carries the files, and a push publishes
# history — not the tip. This is not theoretical: an app in this fleet had its .aidd untracked,
# read clean at the tip, and still had 170 unpushed commits carrying the files.
#
# Keep this file byte-identical between the aidd and spernakit repos.
set -euo pipefail

ZERO=0000000000000000000000000000000000000000
remote_name="${1:-origin}"
problems=0

note() { echo "  $*" >&2; }

# A repository with no push remote is "managed": .aidd/ is tracked on purpose. Nothing to guard.
if ! git remote -v 2>/dev/null | grep -q '(push)'; then
	exit 0
fi

# --- Check 1: the blanket rule exists at all -------------------------------------------------
# --no-index because a TRACKED file is never reported as ignored, which would make this pass
# vacuously on exactly the repositories that most need it.
if ! git check-ignore -q --no-index .aidd/probe 2>/dev/null; then
	note "no ignore rule covers .aidd/ — add a root-anchored /.aidd/ rule"
	problems=1
fi

# --- Check 2: nothing tracked ------------------------------------------------------------------
tracked=$(git ls-files .aidd | head -5)
if [ -n "$tracked" ]; then
	note "$(git ls-files .aidd | wc -l | tr -d ' ') tracked .aidd path(s); index-only removal required:"
	note "  git rm --cached -r .aidd"
	problems=1
fi

# --- Check 3: no .aidd history in the push range ------------------------------------------------
#
# A FAILED query is not an empty result. An unreachable SHA (shallow clone, pruned object, corrupt
# or truncated ref) makes rev-list exit 128 and print nothing; swallowing that with `|| true` reads
# as "no .aidd commits" and lets the push through — the exact history this guard exists to stop.
# Every rev-list here is therefore status-checked and fails CLOSED.
REV_OUT=''
rev_list_checked() {
	local rc=0
	# Deliberately not a subshell: `problems` and REV_OUT must survive into the caller.
	set +e
	REV_OUT=$(git rev-list "$@" -- .aidd 2>&1)
	rc=$?
	set -e
	return "$rc"
}

while read -r _local_ref local_sha _remote_ref remote_sha; do
	[ -z "${local_sha:-}" ] && continue
	# Branch deletion: nothing is being published. Never treat the zero SHA as a revision.
	[ "$local_sha" = "$ZERO" ] && continue

	if [ "$remote_sha" != "$ZERO" ]; then
		# Existing remote branch: exactly what this push adds.
		query=("$remote_sha..$local_sha")
	elif git fetch --quiet "$remote_name" 2>/dev/null; then
		# New branch: no range exists. Exclude what is already published ON THIS DESTINATION — but
		# only against refs just refreshed, never against whatever the cache happened to hold.
		# Repositories whose .aidd history is already on this remote would otherwise be blocked
		# forever over commits the push cannot expose twice.
		#
		# --remotes=<name>, never a bare --remotes: the bare form excludes anything reachable from
		# ANY remote, so .aidd history sitting on a private backup would mask itself and let a push
		# to a clean PUBLIC remote through. Exclusions must be scoped to where we are pushing.
		query=("$local_sha" --not "--remotes=$remote_name")
	else
		# Fetch failed (offline, auth). Nothing is known about the remote, so fail closed.
		query=("$local_sha")
	fi

	if ! rev_list_checked "${query[@]}"; then
		note "cannot inspect .aidd history — git rev-list failed:"
		note "  ${REV_OUT%%$'\n'*}"
		note "  a failed query is not an empty result; refusing to guess"
		problems=1
		continue
	fi
	commits="$REV_OUT"

	if [ -n "$commits" ]; then
		n=$(printf '%s\n' "$commits" | grep -c .)
		note "$n commit(s) in this push touch .aidd — pushing publishes them irreversibly:"
		printf '%s\n' "$commits" | head -3 | while read -r c; do
			note "  $(git log -1 --format='%h %s' "$c" 2>/dev/null || echo "$c")"
		done
		[ "$n" -gt 3 ] && note "  ... and $((n - 3)) more"
		note "  strip them first (safe while unpushed):"
		note "    git filter-branch --index-filter 'git rm -r --cached --ignore-unmatch .aidd' \\"
		note "      --prune-empty <remote>/<branch>..HEAD"
		problems=1
	fi
done

if [ "$problems" -ne 0 ]; then
	echo "" >&2
	echo "PUSH BLOCKED: this repository has a push remote, so .aidd/ must never be published." >&2
	echo "Untracking does not clean history — only a rewrite does, and only while unpushed." >&2
	echo "Override with --no-verify ONLY if you intend to publish .aidd/ permanently." >&2
	exit 1
fi

exit 0

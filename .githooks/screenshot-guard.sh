#!/usr/bin/env bash
# Blocks pushing a version tag whose screenshot artifact is missing, incomplete, or failed.
#
# Every release captures the shipped UI into screenshots/v<version>/ (`bun run smoke:screenshots`,
# run AFTER the version bump so the directory name matches the tag). The directory is gitignored,
# so nothing downstream can recover it later: once a tag is public without its capture, the visual
# record of that version is gone for good. This is not theoretical — releases v3.25.0 through
# v3.28.2 of the template shipped without screenshots because nothing enforced the artifact.
#
# Reads the pre-push stdin protocol: <local-ref> <local-sha> <remote-ref> <remote-sha> per line.
# Only refs/tags/v* pushes are checked. The template names the directory v<version>; derived apps
# name it v<version>-sv<template-version>, so any directory starting with the tag version passes.
#
# A TRACKED .screenshot-capture file is what says whether a repo captures at all. A headless repo —
# a CLI, a library — never adds one, and this guard has nothing to enforce there, so its absence
# passes. Once the file exists the repo has opted in, and a tag with no directory under
# screenshots/ is the exact omission described above: that fails. Do not collapse these two cases
# into one "capture is absent" check — that reads an opted-in repo's forgotten capture as an
# opted-out repo.
#
# The declaration must be TRACKED, and screenshots/ itself cannot be it. That directory is
# gitignored in every repository this guard protects, so a predicate reading it answers from
# untracked local state: the same commit opted in on the machine that captured and opted out in a
# fresh clone, which is where a release is most likely to be cut by someone who has not captured.
# Four repositories also grew a screenshots/ root for something other than releases and were
# silently one tag away from a block they had never agreed to. A repository states what it is; the
# guard does not guess it from what happens to be on disk. Recorded as punchlist C7.
#
# A full-looking directory is not proof of a good crawl either: a run that fails on the last page
# still leaves 40 PNGs behind. The crawl stamps its own verdict into crawl-result.json (`started`
# before the first page loads, `passed`/`failed` when the report lands), and this guard refuses
# anything that does not say success. A capture with no such file predates the stamp — or comes
# from a repo whose crawler does not write one — so it falls back to the PNG count alone.
#
# Keep this file byte-identical between the aidd, spernakit, and starsync repos.
set -euo pipefail

ZERO=0000000000000000000000000000000000000000
CONTRACT_FILE=.screenshot-capture
ROOT_DIR=screenshots
MIN_PNGS=5
RESULT_FILE=crawl-result.json
problems=0

note() { echo "  $*" >&2; }

while read -r local_ref local_sha _remote_ref _remote_sha; do
	[ -z "${local_sha:-}" ] && continue
	# Tag deletion publishes nothing.
	[ "$local_sha" = "$ZERO" ] && continue
	case "$local_ref" in
	refs/tags/v[0-9]*) ;;
	*) continue ;;
	esac

	version="${local_ref#refs/tags/}"

	# Undeclared: this repo does not capture screenshots. Nothing to enforce. A root with no
	# declaration is called out rather than passed silently, because it is the one shape that is
	# either an unfinished opt-in or a directory that means something else here, and only someone
	# in this repository can say which.
	if [ ! -f "$CONTRACT_FILE" ]; then
		if [ -d "$ROOT_DIR" ]; then
			note "tag $version: $ROOT_DIR/ exists but $CONTRACT_FILE does not, so nothing is enforced"
			note "  add $CONTRACT_FILE if this repository's releases must carry a capture"
		else
			note "tag $version: no $CONTRACT_FILE in this repository, nothing to check"
		fi
		continue
	fi

	dir=""
	for candidate in "$ROOT_DIR/$version" "$ROOT_DIR/$version"-sv*; do
		if [ -d "$candidate" ]; then
			dir="$candidate"
			break
		fi
	done

	if [ -z "$dir" ]; then
		note "tag $version: $CONTRACT_FILE declares release capture, but $ROOT_DIR/ has no $version/"
		problems=1
		continue
	fi

	count=$(find "$dir" -maxdepth 1 -name '*.png' | wc -l | tr -d ' ')
	if [ "$count" -lt "$MIN_PNGS" ]; then
		note "tag $version: $dir has only $count PNG(s); a full capture produces at least $MIN_PNGS"
		problems=1
	fi

	result="$dir/$RESULT_FILE"
	if [ -f "$result" ] && ! grep -Eq '"success"[[:space:]]*:[[:space:]]*true' "$result"; then
		status=$(grep -Eo '"status"[[:space:]]*:[[:space:]]*"[^"]*"' "$result" | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
		note "tag $version: $dir/$RESULT_FILE records crawl status '${status:-unknown}', not a passing run"
		problems=1
	fi
done

if [ "$problems" -ne 0 ]; then
	echo "" >&2
	echo "PUSH BLOCKED: version tag(s) above have no usable screenshot artifact." >&2
	echo "With the bumped version in package.json, run: bun run smoke:screenshots" >&2
	echo "and fix any crawl failures it reports — a failed crawl is not a release capture." >&2
	echo "(single-instance rule: never start a second smoke run while one is active)." >&2
	echo "Override with --no-verify ONLY for historical tags that predate this guard." >&2
	exit 1
fi

exit 0

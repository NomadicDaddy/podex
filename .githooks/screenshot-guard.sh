#!/usr/bin/env bash
# Blocks pushing a version tag whose screenshot artifact is missing.
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
# A full-looking directory is not proof of a good crawl: a run that fails on the last page still
# leaves 40 PNGs behind. The crawl stamps its own verdict into crawl-result.json (`started` before
# the first page loads, `passed`/`failed` when the report lands), and this guard refuses anything
# that does not say success. A capture with no such file predates the stamp — or comes from a repo
# whose crawler does not write one — so it falls back to the PNG count alone.
#
# Keep this file byte-identical between the aidd and spernakit repos.
set -euo pipefail

ZERO=0000000000000000000000000000000000000000
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

	dir=""
	for candidate in "screenshots/$version" "screenshots/$version"-sv*; do
		if [ -d "$candidate" ]; then
			dir="$candidate"
			break
		fi
	done

	if [ -z "$dir" ]; then
		note "tag $version: no screenshots/$version/ directory exists"
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

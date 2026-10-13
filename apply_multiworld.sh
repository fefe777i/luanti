#!/bin/bash
# Applies all engine patches. Safe to run several times.
#   host_all_worlds.patch - one server per dimension for "Host game"
#   touch_panzoom.patch   - pan_zoom_container + fixed touch scrolling
set -e
cd "$(dirname "$0")"

for patch in host_all_worlds.patch touch_panzoom.patch; do
	[ -f "$patch" ] || continue
	if git apply --reverse --check "$patch" >/dev/null 2>&1; then
		echo "$patch: already applied."
	elif git apply --check "$patch" >/dev/null 2>&1; then
		git apply "$patch"
		echo "$patch: applied."
	else
		echo "$patch: cannot be applied (conflict)."
		exit 1
	fi
done

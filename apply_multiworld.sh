#!/bin/bash
# Applies all engine patches. Safe to run several times.
#   host_all_worlds.patch - one server per dimension for "Host game"
#   lazy_dimensions.patch - dimension servers start on demand and stop when empty
#   touch_panzoom.patch   - pan_zoom_container + fixed touch scrolling
set -e
cd "$(dirname "$0")"

for patch in host_all_worlds.patch lazy_dimensions.patch touch_panzoom.patch; do
	[ -f "$patch" ] || continue
	# lazy_dimensions.patch changes files of host_all_worlds.patch, so the
	# latter no longer applies in reverse once the former is in.
	if [ "$patch" = host_all_worlds.patch ] && [ -f lazy_dimensions.patch ] &&
			git apply --reverse --check lazy_dimensions.patch >/dev/null 2>&1; then
		echo "$patch: already applied (with lazy_dimensions.patch)."
		continue
	fi
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

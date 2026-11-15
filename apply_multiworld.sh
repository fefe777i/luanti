#!/bin/bash
# Applies all engine patches. Safe to run several times.
#   host_all_worlds.patch       - one server per dimension for "Host game"
#   lazy_dimensions.patch       - dimension servers start on demand and stop when empty
#   dimension_port_reuse.patch  - a stopped dimension gives its port back
#   touch_panzoom.patch         - pan_zoom_container + fixed touch scrolling
set -e
cd "$(dirname "$0")"

# Patches of the dimension chain change files of the earlier ones, so an earlier
# patch no longer applies in reverse once a later one is in.
applied() { [ -f "$1" ] && git apply --reverse --check "$1" >/dev/null 2>&1; }

for patch in host_all_worlds.patch lazy_dimensions.patch dimension_port_reuse.patch touch_panzoom.patch; do
	[ -f "$patch" ] || continue
	case "$patch" in
	host_all_worlds.patch)
		if applied lazy_dimensions.patch || applied dimension_port_reuse.patch; then
			echo "$patch: already applied (with a later patch)."
			continue
		fi ;;
	lazy_dimensions.patch)
		if applied dimension_port_reuse.patch; then
			echo "$patch: already applied (with a later patch)."
			continue
		fi ;;
	esac
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

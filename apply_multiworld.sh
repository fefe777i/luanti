#!/bin/bash
# Applies all engine patches. Safe to run several times, also on a tree where
# the patches were already applied and committed (then the patch files may be
# missing or not match any more, so the state is read from the code itself).
#   host_all_worlds.patch       - one server per dimension for "Host game"
#   lazy_dimensions.patch       - dimension servers start on demand and stop when empty
#   dimension_port_reuse.patch  - a stopped dimension gives its port back
#   dimension_single_port.patch - all dimensions behind ONE public port (router)
#   touch_panzoom.patch         - pan_zoom_container + fixed touch scrolling
set -e
cd "$(dirname "$0")"

# Is the patch already in the tree? (a marker that only the patch creates)
has_marker() {
	case "$1" in
	host_all_worlds.patch)       [ -f src/client/dimensionhost.cpp ] ;;
	lazy_dimensions.patch)       [ -f src/client/dimensionhost.h ] && grep -q "wake(" src/client/dimensionhost.h ;;
	dimension_port_reuse.patch)  [ -f src/client/dimensionhost.cpp ] && grep -q "The lowest free port above the main one" src/client/dimensionhost.cpp ;;
	dimension_single_port.patch) [ -f src/network/udprouter.cpp ] ;;
	touch_panzoom.patch)         [ -f src/gui/guiPanZoom.cpp ] ;;
	esac
}

for patch in host_all_worlds.patch lazy_dimensions.patch dimension_port_reuse.patch \
		dimension_single_port.patch touch_panzoom.patch; do
	if has_marker "$patch"; then
		echo "$patch: already applied."
		continue
	fi
	if [ ! -f "$patch" ]; then
		echo "$patch: not in the repository, skipped."
		continue
	fi
	if git apply --check "$patch" >/dev/null 2>&1; then
		git apply "$patch"
		echo "$patch: applied."
	else
		echo "$patch: cannot be applied (conflict)."
		exit 1
	fi
done

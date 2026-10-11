#!/bin/bash
# Applies host_all_worlds.patch (one server per dimension for "Host game").
# Safe to run several times.
set -e
cd "$(dirname "$0")"

if git apply --reverse --check host_all_worlds.patch >/dev/null 2>&1; then
	echo "host_all_worlds.patch: already applied."
elif git apply --check host_all_worlds.patch >/dev/null 2>&1; then
	git apply host_all_worlds.patch
	echo "host_all_worlds.patch: applied."
else
	echo "host_all_worlds.patch: cannot be applied (conflict)."
	exit 1
fi

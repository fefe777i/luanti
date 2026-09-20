#!/bin/bash
# Starts one server per dimension of the same world (see doc/dimensions.md).
#
#   util/run_multiworld_servers.sh <server-binary> <world-path> <base-port> <dimension>...
#
# Example (overworld on 30000, stone_world on 30001, nether on 30002):
#   util/run_multiworld_servers.sh ./bin/luantiserver ~/worlds/myworld 30000 overworld stone_world nether
#
# Optional environment:
#   BASE_CONF=/path/minetest.conf   settings shared by all servers (name, motd, ...)
#   START_DELAY=8                   seconds to wait after the first server
#   DRY_RUN=1                       only print the commands
#
# Start "overworld" first: the mods create the other dimensions when it loads.
# Players connect to the base port, the other ports are entered from there.

set -e

if [ "$#" -lt 4 ]; then
	sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
	exit 1
fi

BIN="$1"; WORLD="$2"; BASE_PORT="$3"; shift 3
DIMS=("$@")
START_DELAY="${START_DELAY:-8}"

# dimension_servers = overworld=30000, stone_world=30001, ...
MAP=""
i=0
for d in "${DIMS[@]}"; do
	MAP+="${MAP:+, }$d=$((BASE_PORT + i))"
	i=$((i + 1))
done

PIDS=()
cleanup() {
	for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null || true; done
}
trap cleanup EXIT INT TERM

i=0
for d in "${DIMS[@]}"; do
	PORT=$((BASE_PORT + i))
	CONF="$WORLD/multiworld_$d.conf"
	if [ -n "$BASE_CONF" ]; then cat "$BASE_CONF" > "$CONF"; else : > "$CONF"; fi
	{
		echo ""
		echo "dimension = $d"
		echo "dimension_servers = $MAP"
	} >> "$CONF"

	CMD=("$BIN" --world "$WORLD" --port "$PORT" --config "$CONF")
	echo "[$d] ${CMD[*]}"
	if [ -z "$DRY_RUN" ]; then
		"${CMD[@]}" &
		PIDS+=($!)
		[ "$i" -eq 0 ] && sleep "$START_DELAY"
	fi
	i=$((i + 1))
done

[ -n "$DRY_RUN" ] && exit 0
wait

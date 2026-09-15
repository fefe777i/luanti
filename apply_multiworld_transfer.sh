#!/bin/sh
set -e
sed -i '/if (subworld_name != "overworld" &&/a\	if (subworld_name != "overworld") pos.X += 12500 * MAP_BLOCKSIZE;' src/server.cpp

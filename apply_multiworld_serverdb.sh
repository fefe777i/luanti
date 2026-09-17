#!/bin/bash
set -e
cd "$(cd "$(dirname "$0")" && pwd)"

# Multiworld server database handling is now implemented directly by
# apply_multiworld.sh. Keep this script as an idempotent compatibility step
# for existing CI commands.
echo "=== Multiworld server DB patch already included in apply_multiworld.sh ==="

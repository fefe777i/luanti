#!/bin/bash
set -e
cd "$(cd "$(dirname "$0")" && pwd)"
python3 - <<'PY'
from pathlib import Path
p = Path('src/server.cpp')
s = p.read_text()
old = '\tsao->setBasePosition(pos);\n\treturn true;'
new = '\tsao->setBasePosition(pos);\n\tsao->setPos(pos);\n\treturn true;'
if old not in s:
    raise SystemExit('transferPlayer position anchor not found')
p.write_text(s.replace(old, new, 1))
print('OK: send actual player teleport position')
PY

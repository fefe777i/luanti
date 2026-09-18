#!/bin/bash
set -e
cd "$(cd "$(dirname "$0")" && pwd)"
python3 - <<'PY'
from pathlib import Path
p = Path('src/server.cpp')
s = p.read_text()
old = '\tsao->setBasePosition(pos);\n\treturn true;'
new = '\tsao->setBasePosition(pos);\n\tsao->setPos(pos);\n\tsao->setVelocity(v3f(0, 0, 0));\n\treturn true;'
if new in s:
    print('SKIP: actual player teleport already applied')
elif old in s:
    p.write_text(s.replace(old, new, 1))
    print('OK: send actual player teleport position and reset velocity')
else:
    raise SystemExit('transferPlayer position anchor not found')
PY

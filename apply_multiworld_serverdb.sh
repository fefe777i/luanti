#!/bin/bash
set -e
cd "$(cd "$(dirname "$0")" && pwd)"
python3 - <<'PY'
from pathlib import Path
p=Path('src/server.cpp')
s=p.read_text()
old='''\tconst std::string worldmt = path + DIR_DELIM + "world.mt";
\treturn fs::safeWriteToFile(worldmt, "gameid = minetest\\n");'''
new='''\tconst std::string worldmt = path + DIR_DELIM + "world.mt";
\tif (!fs::safeWriteToFile(worldmt,
\t\t"gameid = minetest\\nbackend = sqlite3\\nsubworld = true\\nsubworld_offset_x = 12500\\n"))
\t\treturn false;
\treturn m_env->getServerMap().createSubWorldDatabase(name, 12500);'''
if old not in s: raise SystemExit('createSubWorld anchor missing')
s=s.replace(old,new,1)
old='''\tstate.positions[subworld_name] = pos;
\tsao->setBasePosition(pos);'''
new='''\tif (subworld_name != "overworld")
\t\tpos.X += 12500.0f * MAP_BLOCKSIZE;
\tstate.positions[subworld_name] = pos;
\tsao->setBasePosition(pos);'''
if old not in s: raise SystemExit('transfer anchor missing')
s=s.replace(old,new,1)
p.write_text(s)
PY

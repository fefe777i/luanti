#!/bin/sh
set -e
python3 - <<'PY'
from pathlib import Path
p=Path('src/server.cpp')
s=p.read_text()
old='''\tconst std::string worldmt = path + DIR_DELIM + "world.mt";
\treturn fs::safeWriteToFile(worldmt, "gameid = minetest\\n");
'''
new='''\tconst std::string worldmt = path + DIR_DELIM + "world.mt";
\tconst std::string config = "gameid = minetest\\nbackend = sqlite3\\nsubworld = true\\nsubworld_offset_x = 12500\\n";
\tif (!fs::safeWriteToFile(worldmt, config))
\t\treturn false;
\treturn m_env->getServerMap().createSubWorldDatabase(name, 12500);
'''
if old not in s: raise SystemExit('server create anchor missing')
p.write_text(s.replace(old,new,1))
PY

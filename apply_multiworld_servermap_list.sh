#!/bin/sh
set -e
python3 - <<'PY'
from pathlib import Path
p=Path('src/servermap.cpp')
s=p.read_text()
old='''\tm_db.dbase->listAllLoadableBlocks(dst);
\tif (m_db.dbase_ro)
\t\tm_db.dbase_ro->listAllLoadableBlocks(dst);
'''
new='''\tm_db.dbase->listAllLoadableBlocks(dst);
\tif (m_db.dbase_ro)
\t\tm_db.dbase_ro->listAllLoadableBlocks(dst);
\tfor (auto &it : m_db.subworld_dbs)
\t\tit.second->listAllLoadableBlocks(dst);
'''
if old not in s: raise SystemExit('list anchor missing')
p.write_text(s.replace(old,new,1))
PY

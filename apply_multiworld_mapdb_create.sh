#!/bin/sh
set -e
python3 - <<'PY'
from pathlib import Path
p=Path('src/servermap.cpp')
s=p.read_text()
needle='MapDatabase *ServerMap::createDatabase(\n'
insert='''bool ServerMap::createSubWorldDatabase(const std::string &name, s16 offset_x)
{
\tif (name.empty() || offset_x == 0 || m_db.subworld_dbs.count(offset_x))
\t\treturn false;
\tstd::string subdir = m_savedir + DIR_DELIM + name;
\tif (!fs::PathExists(subdir) && !fs::CreateDir(subdir))
\t\treturn false;
\tSettings conf;
\tconf.set("backend", "sqlite3");
\tconf.setBool("subworld", true);
\tconf.setS32("subworld_offset_x", offset_x);
\tMapDatabase *db = createDatabase("sqlite3", subdir, conf);
\tm_db.subworld_dbs[offset_x] = db;
\treturn true;
}

'''
if needle not in s: raise SystemExit('create anchor missing')
s=s.replace(needle,insert+needle,1)
p.write_text(s)
PY

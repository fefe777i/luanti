#!/bin/sh
set -e
python3 - <<'PY'
from pathlib import Path
p=Path('src/servermap.cpp')
s=p.read_text()
s=s.replace('#include "config.h"\n','#include "config.h"\n#include <cstdlib>\n',1)
old='''void MapDatabaseAccessor::loadBlock(v3s16 blockpos, std::string &ret)
{
\tret.clear();
\tdbase->loadBlock(blockpos, &ret);
\tif (ret.empty() && dbase_ro)
\t\tdbase_ro->loadBlock(blockpos, &ret);
}
'''
new='''MapDatabase *MapDatabaseAccessor::getDatabase(v3s16 blockpos)
{
\tfor (const auto &it : subworld_dbs) {
\t\tif (std::abs((int)blockpos.X - (int)it.first) <= 6000)
\t\t\treturn it.second;
\t}
\treturn dbase;
}

void MapDatabaseAccessor::loadBlock(v3s16 blockpos, std::string &ret)
{
\tret.clear();
\tMapDatabase *db = getDatabase(blockpos);
\tif (db)
\t\tdb->loadBlock(blockpos, &ret);
\tif (ret.empty() && dbase_ro)
\t\tdbase_ro->loadBlock(blockpos, &ret);
}
'''
if old not in s: raise SystemExit('accessor anchor missing')
s=s.replace(old,new,1)
p.write_text(s)
PY

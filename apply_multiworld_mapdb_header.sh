#!/bin/sh
set -e
python3 - <<'PY'
from pathlib import Path
p=Path('src/servermap.h')
s=p.read_text()
s=s.replace('#include <memory>\n','#include <memory>\n#include <map>\n',1)
s=s.replace('\tMapDatabase *dbase_ro = nullptr;\n','\tMapDatabase *dbase_ro = nullptr;\n\tstd::map<s16, MapDatabase *> subworld_dbs;\n\n\tMapDatabase *getDatabase(v3s16 blockpos);\n',1)
s=s.replace('\tstatic MapDatabase *createDatabase(const std::string &name, const std::string &savedir, Settings &conf);\n','\tstatic MapDatabase *createDatabase(const std::string &name, const std::string &savedir, Settings &conf);\n\tbool createSubWorldDatabase(const std::string &name, s16 offset_x);\n',1)
p.write_text(s)
PY

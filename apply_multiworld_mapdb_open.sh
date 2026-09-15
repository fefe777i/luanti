#!/bin/sh
set -e
python3 - <<'PY'
from pathlib import Path
p=Path('src/servermap.cpp')
s=p.read_text()
old='''\tif (conf.exists("readonly_backend")) {
\t\tstd::string readonly_dir = savedir + DIR_DELIM + "readonly";
\t\tm_db.dbase_ro = createDatabase(conf.get("readonly_backend"), readonly_dir, conf);
\t}
'''
new='''\tif (conf.exists("readonly_backend")) {
\t\tstd::string readonly_dir = savedir + DIR_DELIM + "readonly";
\t\tm_db.dbase_ro = createDatabase(conf.get("readonly_backend"), readonly_dir, conf);
\t}

\tfor (const auto &entry : fs::GetDirListing(savedir)) {
\t\tif (!entry.dir || entry.name.empty() || entry.name[0] == '.')
\t\t\tcontinue;
\t\tstd::string subdir = savedir + DIR_DELIM + entry.name;
\t\tstd::string subconf_path = subdir + DIR_DELIM + "world.mt";
\t\tSettings subconf;
\t\tif (!subconf.readConfigFile(subconf_path.c_str()) ||
\t\t\t\t!subconf.exists("subworld") || !subconf.getBool("subworld") ||
\t\t\t\t!subconf.exists("subworld_offset_x"))
\t\t\tcontinue;
\t\ts16 offset_x = (s16)subconf.getS32("subworld_offset_x");
\t\tif (m_db.subworld_dbs.count(offset_x))
\t\t\tcontinue;
\t\tstd::string subbackend = subconf.exists("backend") ? subconf.get("backend") : "sqlite3";
\t\tm_db.subworld_dbs[offset_x] = createDatabase(subbackend, subdir, subconf);
\t}
'''
if old not in s: raise SystemExit('open anchor missing')
s=s.replace(old,new,1)
old='''\t\tdelete m_db.dbase_ro;
\t\tm_db.dbase_ro = nullptr;
\t}
'''
new='''\t\tdelete m_db.dbase_ro;
\t\tm_db.dbase_ro = nullptr;
\t\tfor (auto &it : m_db.subworld_dbs)
\t\t\tdelete it.second;
\t\tm_db.subworld_dbs.clear();
\t}
'''
if old not in s: raise SystemExit('close anchor missing')
s=s.replace(old,new,1)
p.write_text(s)
PY

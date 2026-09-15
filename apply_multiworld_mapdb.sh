#!/bin/bash
set -e
cd "$(cd "$(dirname "$0")" && pwd)"
python3 - <<'PY'
from pathlib import Path
p=Path('src/servermap.h')
s=p.read_text()
s=s.replace('#include <memory>\n', '#include <memory>\n#include <map>\n')
s=s.replace('class ServerEnvironment;\n', 'class ServerEnvironment;\n')
s=s.replace('\tMapDatabase *dbase_ro = nullptr;\n', '\tMapDatabase *dbase_ro = nullptr;\n\tstd::map<s16, MapDatabase *> subworld_dbs;\n\n\tMapDatabase *getDatabase(v3s16 blockpos);\n')
s=s.replace('\tvoid loadBlock(v3s16 blockpos, std::string &ret);\n', '\tvoid loadBlock(v3s16 blockpos, std::string &ret);\n\tvoid saveBlock(v3s16 blockpos, const std::string &data);\n\tvoid deleteBlock(v3s16 blockpos);\n\tvoid beginSave();\n\tvoid endSave();\n\tvoid listAllLoadableBlocks(std::vector<v3s16> &dst);\n')
s=s.replace('\tstatic MapDatabase *createDatabase(const std::string &name, const std::string &savedir, Settings &conf);\n', '\tstatic MapDatabase *createDatabase(const std::string &name, const std::string &savedir, Settings &conf);\n\tbool createSubWorldDatabase(const std::string &name, s16 offset_x);\n')
p.write_text(s)

p=Path('src/servermap.cpp')
s=p.read_text()
s=s.replace('#include "database/database-postgresql.h"\n#endif\n', '#include "database/database-postgresql.h"\n#endif\n#include <cstdlib>\n')
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
\tfor (auto &entry : subworld_dbs) {
\t\tif (std::abs((int)blockpos.X - (int)entry.first) <= 6000)
\t\t\treturn entry.second;
\t}
\treturn dbase;
}

void MapDatabaseAccessor::loadBlock(v3s16 blockpos, std::string &ret)
{
\tret.clear();
\tMapDatabase *db = getDatabase(blockpos);
\tdb->loadBlock(blockpos, &ret);
\tif (ret.empty() && db == dbase && dbase_ro)
\t\tdbase_ro->loadBlock(blockpos, &ret);
}

void MapDatabaseAccessor::saveBlock(v3s16 blockpos, const std::string &data)
{
\tgetDatabase(blockpos)->saveBlock(blockpos, data);
}

void MapDatabaseAccessor::deleteBlock(v3s16 blockpos)
{
\tgetDatabase(blockpos)->deleteBlock(blockpos);
}

void MapDatabaseAccessor::beginSave()
{
\tdbase->beginSave();
\tfor (auto &entry : subworld_dbs)
\t\tentry.second->beginSave();
}

void MapDatabaseAccessor::endSave()
{
\tfor (auto &entry : subworld_dbs)
\t\tentry.second->endSave();
\tdbase->endSave();
}

void MapDatabaseAccessor::listAllLoadableBlocks(std::vector<v3s16> &dst)
{
\tdbase->listAllLoadableBlocks(dst);
\tfor (auto &entry : subworld_dbs)
\t\tentry.second->listAllLoadableBlocks(dst);
\tif (dbase_ro)
\t\tdbase_ro->listAllLoadableBlocks(dst);
}
'''
if old not in s: raise SystemExit('accessor anchor missing')
s=s.replace(old,new,1)
old='''\tm_db.dbase = createDatabase(backend, savedir, conf);
\tif (conf.exists("readonly_backend")) {'''
new='''\tm_db.dbase = createDatabase(backend, savedir, conf);

\tfor (const auto &node : fs::GetDirListing(savedir)) {
\t\tif (!node.dir || node.name.empty() || node.name[0] == '.')
\t\t\tcontinue;
\t\tstd::string subpath = savedir + DIR_DELIM + node.name;
\t\tSettings subconf;
\t\tif (!subconf.readConfigFile((subpath + DIR_DELIM + "world.mt").c_str()))
\t\t\tcontinue;
\t\tif (!subconf.exists("subworld") || !subconf.getBool("subworld"))
\t\t\tcontinue;
\t\ts16 offset = 0;
\t\tif (!subconf.exists("subworld_offset_x"))
\t\t\tcontinue;
\t\toffset = subconf.getS16("subworld_offset_x");
\t\tm_db.subworld_dbs[offset] = createDatabase("sqlite3", subpath, subconf);
\t}
\n\tif (conf.exists("readonly_backend")) {'''
if old not in s: raise SystemExit('constructor anchor missing')
s=s.replace(old,new,1)
old='''\t\tdelete m_db.dbase;
\t\tm_db.dbase = nullptr;
\t\tdelete m_db.dbase_ro;'''
new='''\t\tfor (auto &entry : m_db.subworld_dbs)
\t\t\tdelete entry.second;
\t\tm_db.subworld_dbs.clear();
\t\tdelete m_db.dbase;
\t\tm_db.dbase = nullptr;
\t\tdelete m_db.dbase_ro;'''
if old not in s: raise SystemExit('destructor anchor missing')
s=s.replace(old,new,1)
old='''void ServerMap::listAllLoadableBlocks(std::vector<v3s16> &dst)
{
\tMutexAutoLock dblock(m_db.mutex);
\tm_db.dbase->listAllLoadableBlocks(dst);
\tif (m_db.dbase_ro)
\t\tm_db.dbase_ro->listAllLoadableBlocks(dst);
}'''
new='''void ServerMap::listAllLoadableBlocks(std::vector<v3s16> &dst)
{
\tMutexAutoLock dblock(m_db.mutex);
\tm_db.listAllLoadableBlocks(dst);
}'''
if old not in s: raise SystemExit('list anchor missing')
s=s.replace(old,new,1)
s=s.replace('''void ServerMap::beginSave()
{
\tMutexAutoLock dblock(m_db.mutex);
\tm_db.dbase->beginSave();
}

void ServerMap::endSave()
{
\tMutexAutoLock dblock(m_db.mutex);
\tm_db.dbase->endSave();
}
''','''void ServerMap::beginSave()
{
\tMutexAutoLock dblock(m_db.mutex);
\tm_db.beginSave();
}

void ServerMap::endSave()
{
\tMutexAutoLock dblock(m_db.mutex);
\tm_db.endSave();
}
''',1)
s=s.replace('return saveBlock(block, m_db.dbase, m_map_compression_level);','return saveBlock(block, m_db.getDatabase(block->getPos()), m_map_compression_level);',1)
s=s.replace('''\tif (!m_db.dbase->deleteBlock(blockpos))
\t\treturn false;''','''\tif (!m_db.getDatabase(blockpos)->deleteBlock(blockpos))
\t\treturn false;''',1)
old='''\treturn db;
}

void ServerMap::beginSave()'''
new='''\treturn db;
}

bool ServerMap::createSubWorldDatabase(const std::string &name, s16 offset_x)
{
\tstd::string path = m_savedir + DIR_DELIM + name;
\tSettings conf;
\tconf.set("backend", "sqlite3");
\tconf.set("subworld", "true");
\tconf.setS16("subworld_offset_x", offset_x);
\tMapDatabase *db = createDatabase("sqlite3", path, conf);
\tMutexAutoLock dblock(m_db.mutex);
\tif (m_db.subworld_dbs.count(offset_x)) {
\t\tdelete db;
\t\treturn false;
\t}
\tm_db.subworld_dbs[offset_x] = db;
\treturn true;
}

void ServerMap::beginSave()'''
if old not in s: raise SystemExit('create db anchor missing')
s=s.replace(old,new,1)
p.write_text(s)
PY

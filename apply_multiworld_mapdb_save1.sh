#!/bin/sh
set -e
python3 - <<'PY'
from pathlib import Path
p=Path('src/servermap.cpp')
s=p.read_text()
s=s.replace('''\tm_db.dbase->beginSave();
}

void ServerMap::endSave()
{
\tMutexAutoLock dblock(m_db.mutex);
\tm_db.dbase->endSave();
}
''','''\tm_db.dbase->beginSave();
\tfor (auto &it : m_db.subworld_dbs)
\t\tit.second->beginSave();
}

void ServerMap::endSave()
{
\tMutexAutoLock dblock(m_db.mutex);
\tm_db.dbase->endSave();
\tfor (auto &it : m_db.subworld_dbs)
\t\tit.second->endSave();
}
''',1)
p.write_text(s)
PY

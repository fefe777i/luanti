#!/bin/sh
set -e
sed -i 's/m_db\.dbase->deleteBlock(blockpos)/m_db.getDatabase(blockpos)->deleteBlock(blockpos)/' src/servermap.cpp

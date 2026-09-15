#!/bin/sh
set -e
sed -i 's/m_db\.dbase, m_map_compression_level/m_db.getDatabase(block->getPos()), m_map_compression_level/' src/servermap.cpp

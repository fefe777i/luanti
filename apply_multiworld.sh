#!/bin/bash
set -e

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_ROOT"

fail() { echo "ERROR: $1" >&2; exit 1; }

# 1. Create the SubWorld state header if it is missing.
if [ ! -f src/subworld.h ]; then
cat > src/subworld.h <<'SUBWORLD_H'
#pragma once

#include <string>
#include <unordered_map>
#include <vector>

#include "irr_v3d.h"
#include "filesys.h"

struct PlayerSubWorldState {
	std::string current_subworld = "overworld";
	std::unordered_map<std::string, v3f> positions;
};

static inline bool isSubWorldDir(const std::string &path)
{
	return fs::PathExists(path + DIR_DELIM + "world.mt");
}
SUBWORLD_H
fi

# 2. Add the server member and public API declarations.
python3 - <<'PY'
from pathlib import Path
p = Path('src/server.h')
s = p.read_text()

if '#include "subworld.h"' not in s:
    anchor = '#include "translation.h"'
    if anchor not in s:
        raise SystemExit('server.h: include anchor not found')
    s = s.replace(anchor, anchor + '\n#include "subworld.h"', 1)

if 'm_player_subworld_states' not in s:
    anchor = '\tstd::unique_ptr<ServerScripting> m_script;'
    if anchor not in s:
        raise SystemExit('server.h: member anchor not found')
    s = s.replace(anchor, anchor + '\n\n\tstd::unordered_map<std::string, PlayerSubWorldState> m_player_subworld_states;', 1)

if 'bool createSubWorld(const std::string &name);' not in s:
    anchor = '\tstd::string getWorldPath() const override { return m_path_world; }'
    if anchor not in s:
        raise SystemExit('server.h: public method anchor not found')
    add = '''\n\t// === Multiworld ===\n\tbool createSubWorld(const std::string &name);\n\tvoid transferPlayer(const std::string &playername, const std::string &subworld_name, v3f pos);\n\tstd::string getPlayerSubWorld(const std::string &playername);\n\tstd::vector<std::string> listSubWorlds();\n'''
    s = s.replace(anchor, anchor + add, 1)

p.write_text(s)
PY

# 3. Add the Lua API declarations.
python3 - <<'PY'
from pathlib import Path
p = Path('src/script/lua_api/l_server.h')
s = p.read_text()
if 'l_create_subworld' not in s:
    anchor = '    // serialize_roundtrip(obj)\n    static int l_serialize_roundtrip(lua_State *L);'
    if anchor not in s:
        anchor = '\t// serialize_roundtrip(obj)\n\tstatic int l_serialize_roundtrip(lua_State *L);'
    if anchor not in s:
        raise SystemExit('l_server.h: serialize_roundtrip anchor not found')
    add = '''\n\n\t// create_subworld(name)\n\tstatic int l_create_subworld(lua_State *L);\n\n\t// transfer_player(name, subworld_name, pos)\n\tstatic int l_transfer_player(lua_State *L);\n\n\t// get_player_subworld(name)\n\tstatic int l_get_player_subworld(lua_State *L);\n\n\t// list_subworlds()\n\tstatic int l_list_subworlds(lua_State *L);'''
    s = s.replace(anchor, anchor + add, 1)
p.write_text(s)
PY

# 4. Add the Server implementation and Lua API implementation.
python3 - <<'PY'
from pathlib import Path
p = Path('src/server.cpp')
s = p.read_text()
if 'bool Server::createSubWorld' not in s:
    code = r'''

// Multiworld — реалізація підсвітів
bool Server::createSubWorld(const std::string &name)
{
	if (name.empty() || name == "." || name == ".." || name == "overworld")
		return false;

	std::string path = m_path_world + DIR_DELIM + name;
	if (fs::PathExists(path))
		return false;

	if (!fs::CreateDir(path))
		return false;

	// A minimal world.mt makes the directory recognizable as a subworld.
	std::string worldmt = path + DIR_DELIM + "world.mt";
	if (!fs::safeWriteToFile(worldmt, "gameid = minetest\n"))
		return false;

	infostream << "createSubWorld: created '" << name << "' at " << path << std::endl;
	return true;
}

void Server::transferPlayer(const std::string &playername,
		const std::string &subworld_name, v3f pos)
{
	PlayerSAO *sao = getPlayerSAO(playername);
	if (!sao)
		return;

	std::string sw_path = m_path_world + DIR_DELIM + subworld_name;
	if (!isSubWorldDir(sw_path) && subworld_name != "overworld") {
		errorstream << "transferPlayer: subworld '" << subworld_name << "' not found" << std::endl;
		return;
	}

	auto &state = m_player_subworld_states[playername];
	state.positions[state.current_subworld] = sao->getBasePosition();
	state.current_subworld = subworld_name;
	state.positions[subworld_name] = pos;
	sao->setBasePosition(pos);
}

std::string Server::getPlayerSubWorld(const std::string &playername)
{
	auto it = m_player_subworld_states.find(playername);
	if (it == m_player_subworld_states.end())
		return "overworld";
	return it->second.current_subworld;
}

std::vector<std::string> Server::listSubWorlds()
{
	std::vector<std::string> result;
	result.push_back("overworld");

	auto nodes = fs::GetDirListing(m_path_world);
	for (const auto &node : nodes) {
		if (!node.dir)
			continue;
		if (node.name == "." || node.name == ".." || node.name == "overworld")
			continue;
		if (isSubWorldDir(m_path_world + DIR_DELIM + node.name))
			result.push_back(node.name);
	}
	return result;
}
'''
    # Append near the end; definitions do not need to be adjacent to other Server methods.
    s += code
p.write_text(s)
PY

python3 - <<'PY'
from pathlib import Path
p = Path('src/script/lua_api/l_server.cpp')
s = p.read_text()
if 'int ModApiServer::l_create_subworld' not in s:
    code = r'''

// Multiworld Lua API
int ModApiServer::l_create_subworld(lua_State *L)
{
	NO_MAP_LOCK_REQUIRED;
	std::string name = luaL_checkstring(L, 1);
	bool ok = getServer(L)->createSubWorld(name);
	lua_pushboolean(L, ok);
	return 1;
}

int ModApiServer::l_transfer_player(lua_State *L)
{
	NO_MAP_LOCK_REQUIRED;
	std::string pname = luaL_checkstring(L, 1);
	std::string swname = luaL_checkstring(L, 2);
	v3f pos = check_v3f(L, 3);
	getServer(L)->transferPlayer(pname, swname, pos);
	return 0;
}

int ModApiServer::l_get_player_subworld(lua_State *L)
{
	NO_MAP_LOCK_REQUIRED;
	std::string pname = luaL_checkstring(L, 1);
	std::string sw = getServer(L)->getPlayerSubWorld(pname);
	lua_pushstring(L, sw.c_str());
	return 1;
}

int ModApiServer::l_list_subworlds(lua_State *L)
{
	NO_MAP_LOCK_REQUIRED;
	auto list = getServer(L)->listSubWorlds();
	lua_newtable(L);
	int i = 1;
	for (auto &name : list) {
		lua_pushstring(L, name.c_str());
		lua_rawseti(L, -2, i++);
	}
	return 1;
}
'''
    # Insert before Initialize so declarations/definitions are in the expected API section.
    marker = 'void ModApiServer::Initialize(lua_State *L, int top)'
    if marker not in s:
        raise SystemExit('l_server.cpp: Initialize anchor not found')
    s = s.replace(marker, code + '\n' + marker, 1)

for line in [
    '\tAPI_FCT(create_subworld);',
    '\tAPI_FCT(transfer_player);',
    '\tAPI_FCT(get_player_subworld);',
    '\tAPI_FCT(list_subworlds);',
]:
    if line not in s:
        marker = '\tAPI_FCT(serialize_roundtrip);'
        if marker not in s:
            raise SystemExit('l_server.cpp: registration anchor not found')
        s = s.replace(marker, marker + '\n' + line, 1)

p.write_text(s)
PY

echo "Multiworld changes applied."
echo "Now run:"
echo "  cmake -S . -B build"
echo "  cmake --build build -j2"

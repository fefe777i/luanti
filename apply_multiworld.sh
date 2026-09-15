#!/bin/bash
set -e

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_ROOT"

python3 - <<'PY'
from pathlib import Path

root = Path('.')

def patch(path, old, new, label):
    p = root / path
    s = p.read_text()
    if new in s:
        print(f"SKIP: {label} already applied")
        return
    if old not in s:
        raise SystemExit(f"ERROR: anchor not found for {label}: {path}")
    p.write_text(s.replace(old, new, 1))
    print(f"OK: {label}")

patch('src/server.h', '#include "server/clientiface.h"\n', '#include "server/clientiface.h"\n#include "subworld.h"\n', 'server.h include')

patch('src/server.h',
'''\tstd::vector<std::pair<std::string, std::string>> m_mapgen_init_files;\n''',
'''\tstd::vector<std::pair<std::string, std::string>> m_mapgen_init_files;\n\n\tstd::unordered_map<std::string, PlayerSubWorldState> m_player_subworld_states;\n''',
'server.h state member')

patch('src/server.h',
'''\tstd::string getWorldPath() const override { return m_path_world; }\n''',
'''\tstd::string getWorldPath() const override { return m_path_world; }\n\n\t// === Multiworld ===\n\tbool createSubWorld(const std::string &name);\n\tvoid transferPlayer(const std::string &playername, const std::string &subworld_name, v3f pos);\n\tstd::string getPlayerSubWorld(const std::string &playername);\n\tstd::vector<std::string> listSubWorlds();\n''',
'server.h Multiworld API')

patch('src/script/lua_api/l_server.h',
'''\t// serialize_roundtrip(obj)\n\tstatic int l_serialize_roundtrip(lua_State *L);\n''',
'''\t// serialize_roundtrip(obj)\n\tstatic int l_serialize_roundtrip(lua_State *L);\n\n\t// create_subworld(name)\n\tstatic int l_create_subworld(lua_State *L);\n\n\t// transfer_player(name, subworld_name, pos)\n\tstatic int l_transfer_player(lua_State *L);\n\n\t// get_player_subworld(name)\n\tstatic int l_get_player_subworld(lua_State *L);\n\n\t// list_subworlds()\n\tstatic int l_list_subworlds(lua_State *L);\n''',
'l_server.h declarations')

patch('src/server.cpp',
'''\nu16 Server::getProtocolVersionMin()\n''',
r'''\nbool Server::createSubWorld(const std::string &name)
{
	if (name.empty() || name == "." || name == ".." || name == "overworld" ||
		name.find('/') != std::string::npos || name.find('\\') != std::string::npos)
		return false;

	const std::string path = m_path_world + DIR_DELIM + name;
	if (isSubWorldDir(path))
		return true;
	if (fs::PathExists(path))
		return false;
	if (!fs::CreateDir(path))
		return false;

	const std::string worldmt = path + DIR_DELIM + "world.mt";
	return fs::safeWriteToFile(worldmt, "gameid = minetest\n");
}

void Server::transferPlayer(const std::string &playername,
		const std::string &subworld_name, v3f pos)
{
	PlayerSAO *sao = nullptr;
	for (session_t peer_id : m_clients.getClientIDs()) {
		RemoteClient *client = getClient(peer_id);
		if (client && client->getName() == playername) {
			sao = getPlayerSAO(peer_id);
			break;
		}
	}
	if (!sao)
		return;

	if (subworld_name != "overworld" &&
		!isSubWorldDir(m_path_world + DIR_DELIM + subworld_name))
		return;

	auto &state = m_player_subworld_states[playername];
	state.positions[state.current_subworld] = sao->getBasePosition();
	state.current_subworld = subworld_name;
	state.positions[subworld_name] = pos;
	sao->setBasePosition(pos);
	SendMovePlayer(sao);
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
	std::vector<std::string> result{"overworld"};
	for (const auto &node : fs::GetDirListing(m_path_world)) {
		if (!node.dir || node.name.empty() || node.name[0] == '.' || node.name == "overworld")
			continue;
		if (isSubWorldDir(m_path_world + DIR_DELIM + node.name))
			result.push_back(node.name);
	}
	return result;
}

u16 Server::getProtocolVersionMin()
''',
'server.cpp Multiworld implementation')

patch('src/script/lua_api/l_server.cpp',
'''void ModApiServer::Initialize(lua_State *L, int top)\n''',
r'''int ModApiServer::l_create_subworld(lua_State *L)
{
	NO_MAP_LOCK_REQUIRED;
	std::string name = luaL_checkstring(L, 1);
	lua_pushboolean(L, getServer(L)->createSubWorld(name));
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
	lua_pushstring(L, getServer(L)->getPlayerSubWorld(pname).c_str());
	return 1;
}

int ModApiServer::l_list_subworlds(lua_State *L)
{
	NO_MAP_LOCK_REQUIRED;
	auto list = getServer(L)->listSubWorlds();
	lua_newtable(L);
	int i = 1;
	for (const auto &name : list) {
		lua_pushstring(L, name.c_str());
		lua_rawseti(L, -2, i++);
	}
	return 1;
}

void ModApiServer::Initialize(lua_State *L, int top)
''',
'l_server.cpp functions')

patch('src/script/lua_api/l_server.cpp',
'''\tAPI_FCT(serialize_roundtrip);\n''',
'''\tAPI_FCT(serialize_roundtrip);\n\tAPI_FCT(create_subworld);\n\tAPI_FCT(transfer_player);\n\tAPI_FCT(get_player_subworld);\n\tAPI_FCT(list_subworlds);\n''',
'l_server.cpp registration')

patch('lib/lstrpack/CMakeLists.txt',
'''\tPRIVATE\n\t\t${LUA_INCLUDE_DIR}\n''',
'''\tPRIVATE\n\t\t${PROJECT_SOURCE_DIR}/lib/lua/src\n\t\t${LUA_INCLUDE_DIR}\n''',
'lstrpack Lua include fallback')

print('=== Multiworld patch complete ===')
PY

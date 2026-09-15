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
patch('src/server.h', '\tstd::vector<std::pair<std::string, std::string>> m_mapgen_init_files;\n', '\tstd::vector<std::pair<std::string, std::string>> m_mapgen_init_files;\n\n\tstd::unordered_map<std::string, PlayerSubWorldState> m_player_subworld_states;\n', 'server.h state member')
patch('src/server.h', '\tstd::string getWorldPath() const override { return m_path_world; }\n', '\tstd::string getWorldPath() const override { return m_path_world; }\n\n\t// === Multiworld ===\n\tbool createSubWorld(const std::string &name);\n\tvoid transferPlayer(const std::string &playername, const std::string &subworld_name, v3f pos);\n\tstd::string getPlayerSubWorld(const std::string &playername);\n\tstd::vector<std::string> listSubWorlds();\n', 'server.h Multiworld API')
patch('src/script/lua_api/l_server.h', '\t// serialize_roundtrip(obj)\n\tstatic int l_serialize_roundtrip(lua_State *L);\n', '\t// serialize_roundtrip(obj)\n\tstatic int l_serialize_roundtrip(lua_State *L);\n\n\t// create_subworld(name)\n\tstatic int l_create_subworld(lua_State *L);\n\n\t// transfer_player(name, subworld_name, pos)\n\tstatic int l_transfer_player(lua_State *L);\n\n\t// get_player_subworld(name)\n\tstatic int l_get_player_subworld(lua_State *L);\n\n\t// list_subworlds()\n\tstatic int l_list_subworlds(lua_State *L);\n', 'l_server.h declarations')
patch('src/server.cpp', 'u16 Server::getProtocolVersionMin()\n', '''bool Server::createSubWorld(const std::string &name)
{
\tif (name.empty() || name == "." || name == ".." || name == "overworld" ||
\t\tname.find('/') != std::string::npos || name.find('\\\\') != std::string::npos)
\t\treturn false;
\n\tconst std::string path = m_path_world + DIR_DELIM + name;
\tif (isSubWorldDir(path))
\t\treturn true;
\tif (fs::PathExists(path))
\t\treturn false;
\tif (!fs::CreateDir(path))
\t\treturn false;
\n\tconst std::string worldmt = path + DIR_DELIM + "world.mt";
\treturn fs::safeWriteToFile(worldmt, "gameid = minetest\\n");
}
\nvoid Server::transferPlayer(const std::string &playername,
\t\tconst std::string &subworld_name, v3f pos)
{
\tPlayerSAO *sao = nullptr;
\tfor (session_t peer_id : m_clients.getClientIDs()) {
\t\tRemoteClient *client = getClient(peer_id);
\t\tif (client && client->getName() == playername) {
\t\t\tsao = getPlayerSAO(peer_id);
\t\t\tbreak;
\t\t}
\t}
\tif (!sao)
\t\treturn;
\n\tif (subworld_name != "overworld" &&
\t\t!isSubWorldDir(m_path_world + DIR_DELIM + subworld_name))
\t\treturn;
\n\tauto &state = m_player_subworld_states[playername];
\tstate.positions[state.current_subworld] = sao->getBasePosition();
\tstate.current_subworld = subworld_name;
\tstate.positions[subworld_name] = pos;
\tsao->setBasePosition(pos);
}
\nstd::string Server::getPlayerSubWorld(const std::string &playername)
{
\tauto it = m_player_subworld_states.find(playername);
\tif (it == m_player_subworld_states.end())
\t\treturn "overworld";
\treturn it->second.current_subworld;
}
\nstd::vector<std::string> Server::listSubWorlds()
{
\tstd::vector<std::string> result{"overworld"};
\tfor (const auto &node : fs::GetDirListing(m_path_world)) {
\t\tif (!node.dir || node.name.empty() || node.name[0] == '.' || node.name == "overworld")
\t\t\tcontinue;
\t\tif (isSubWorldDir(m_path_world + DIR_DELIM + node.name))
\t\t\tresult.push_back(node.name);
\t}
\treturn result;
}
\nu16 Server::getProtocolVersionMin()
''', 'server.cpp Multiworld implementation')
patch('src/script/lua_api/l_server.cpp', 'void ModApiServer::Initialize(lua_State *L, int top)\n', '''int ModApiServer::l_create_subworld(lua_State *L)
{
\tNO_MAP_LOCK_REQUIRED;
\tstd::string name = luaL_checkstring(L, 1);
\tlua_pushboolean(L, getServer(L)->createSubWorld(name));
\treturn 1;
}
\nint ModApiServer::l_transfer_player(lua_State *L)
{
\tNO_MAP_LOCK_REQUIRED;
\tstd::string pname = luaL_checkstring(L, 1);
\tstd::string swname = luaL_checkstring(L, 2);
\tv3f pos = check_v3f(L, 3);
\tgetServer(L)->transferPlayer(pname, swname, pos);
\treturn 0;
}
\nint ModApiServer::l_get_player_subworld(lua_State *L)
{
\tNO_MAP_LOCK_REQUIRED;
\tstd::string pname = luaL_checkstring(L, 1);
\tlua_pushstring(L, getServer(L)->getPlayerSubWorld(pname).c_str());
\treturn 1;
}
\nint ModApiServer::l_list_subworlds(lua_State *L)
{
\tNO_MAP_LOCK_REQUIRED;
\tauto list = getServer(L)->listSubWorlds();
\tlua_newtable(L);
\tint i = 1;
\tfor (const auto &name : list) {
\t\tlua_pushstring(L, name.c_str());
\t\tlua_rawseti(L, -2, i++);
\t}
\treturn 1;
}
\nvoid ModApiServer::Initialize(lua_State *L, int top)
''', 'l_server.cpp functions')
patch('src/script/lua_api/l_server.cpp', '\tAPI_FCT(serialize_roundtrip);\n', '\tAPI_FCT(serialize_roundtrip);\n\tAPI_FCT(create_subworld);\n\tAPI_FCT(transfer_player);\n\tAPI_FCT(get_player_subworld);\n\tAPI_FCT(list_subworlds);\n', 'l_server.cpp registration')
patch('lib/lstrpack/CMakeLists.txt', '\tPRIVATE\n\t\t${LUA_INCLUDE_DIR}\n', '\tPRIVATE\n\t\t${PROJECT_SOURCE_DIR}/lib/lua/src\n\t\t${LUA_INCLUDE_DIR}\n', 'lstrpack Lua include fallback')
print('=== Multiworld patch complete ===')
PY

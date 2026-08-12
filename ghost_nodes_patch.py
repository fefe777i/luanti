def apply(path, old, new, must_find=1):
    with open(path, 'r') as f:
        content = f.read()
    count = content.count(old)
    if count != must_find:
        print(f"ПОМИЛКА в {path}: очікував {must_find} збігів, знайшов {count}")
        print(f"--- шукав: ---\n{old}\n--- ---")
        return False
    content = content.replace(old, new)
    with open(path, 'w') as f:
        f.write(content)
    print(f"OK: {path}")
    return True

ok = True

# ---------- src/client/client.h ----------

ok &= apply(
    "src/client/client.h",
    "class ParticleManager;\n",
    "class ParticleManager;\nclass WieldMeshSceneNode;\n"
)

ok &= apply(
    "src/client/client.h",
    "\tvoid sendDamage(u16 damage);\n\tvoid sendHudTouch(const std::string &hud_element_name);\n",
    "\tvoid sendDamage(u16 damage);\n\tvoid sendHudTouch(const std::string &hud_element_name);\n\n"
    "\t// Client-side-only \"ghost\" nodes (CSM), never touch the real map/server\n"
    "\tvoid setGhostNode(v3s16 pos, const std::string &node_name);\n"
    "\tvoid removeGhostNode(v3s16 pos);\n"
    "\tvoid clearGhostNodes();\n"
)

ok &= apply(
    "src/client/client.h",
    "\tstd::unique_ptr<ParticleManager> m_particle_manager;\n\tstd::unique_ptr<con::IConnection> m_con;\n",
    "\tstd::unique_ptr<ParticleManager> m_particle_manager;\n"
    "\tstd::map<v3s16, WieldMeshSceneNode*> m_ghost_nodes;\n"
    "\tstd::unique_ptr<con::IConnection> m_con;\n"
)

# ---------- src/client/client.cpp ----------

ok &= apply(
    "src/client/client.cpp",
    '#include "itemdef.h"\n',
    '#include "itemdef.h"\n#include "nodedef.h"\n'
)

ok &= apply(
    "src/client/client.cpp",
    "\tm_shutdown = true;\n\tif (m_con)\n\t\tm_con->Disconnect();\n\n\tdeleteAuthData();\n",
    "\tm_shutdown = true;\n\tif (m_con)\n\t\tm_con->Disconnect();\n\n\tclearGhostNodes();\n\n\tdeleteAuthData();\n"
)

ok &= apply(
    "src/client/client.cpp",
    "void Client::sendHudTouch(const std::string &hud_element_name)\n"
    "{\n\tNetworkPacket pkt(TOSERVER_HUD_TOUCH, 0);\n\tpkt << hud_element_name;\n\tSend(&pkt);\n}\n",

    "void Client::sendHudTouch(const std::string &hud_element_name)\n"
    "{\n\tNetworkPacket pkt(TOSERVER_HUD_TOUCH, 0);\n\tpkt << hud_element_name;\n\tSend(&pkt);\n}\n\n"

    "void Client::setGhostNode(v3s16 pos, const std::string &node_name)\n"
    "{\n"
    "\tcontent_t id;\n"
    "\tif (!ndef()->getId(node_name, id))\n"
    "\t\treturn; // unknown node name, ignore silently\n\n"
    "\t// Replace any existing ghost node at this position first\n"
    "\tremoveGhostNode(pos);\n\n"
    "\tauto *scenenode = new WieldMeshSceneNode(getSceneManager(), -1);\n\n"
    "\tItemStack item(node_name, 1, 0, idef());\n"
    "\tscenenode->setItem(item, this, false);\n\n"
    "\t// Semi-transparent white tint so the underlying node texture still\n"
    "\t// shows through, giving the classic \"ghost block\" preview look.\n"
    "\tscenenode->setColor(video::SColor(140, 255, 255, 255));\n\n"
    "\tscenenode->setPosition(intToFloat(pos, BS));\n"
    "\t// WieldMeshSceneNode is normally scaled down for hand display;\n"
    "\t// scale it back up to a full in-world node size.\n"
    "\tscenenode->setScale(v3f(1.5f, 1.5f, 1.5f));\n\n"
    "\tscenenode->drop(); // the scene manager already grabbed a reference\n\n"
    "\tm_ghost_nodes[pos] = scenenode;\n"
    "}\n\n"

    "void Client::removeGhostNode(v3s16 pos)\n"
    "{\n"
    "\tauto it = m_ghost_nodes.find(pos);\n"
    "\tif (it == m_ghost_nodes.end())\n"
    "\t\treturn;\n\n"
    "\tit->second->remove();\n"
    "\tm_ghost_nodes.erase(it);\n"
    "}\n\n"

    "void Client::clearGhostNodes()\n"
    "{\n"
    "\tfor (auto &it : m_ghost_nodes)\n"
    "\t\tit.second->remove();\n"
    "\tm_ghost_nodes.clear();\n"
    "}\n"
)

# ---------- src/script/lua_api/l_client.h ----------

ok &= apply(
    "src/script/lua_api/l_client.h",
    "\tstatic int l_get_csm_restrictions(lua_State *L);\n",
    "\tstatic int l_get_csm_restrictions(lua_State *L);\n\n"
    "\tstatic int l_set_ghost_node(lua_State *L);\n"
    "\tstatic int l_remove_ghost_node(lua_State *L);\n"
    "\tstatic int l_clear_ghost_nodes(lua_State *L);\n"
)

# ---------- src/script/lua_api/l_client.cpp ----------

ok &= apply(
    "src/script/lua_api/l_client.cpp",
    "\tlua_newtable(L);\n"
    "\tfor (int i = 0; flagdesc[i].name; i++) {\n"
    "\t\tsetboolfield(L, -1, flagdesc[i].name, !!(flags & flagdesc[i].flag));\n"
    "\t}\n"
    "\treturn 1;\n"
    "}\n\n"
    "void ModApiClient::Initialize(lua_State *L, int top)\n",

    "\tlua_newtable(L);\n"
    "\tfor (int i = 0; flagdesc[i].name; i++) {\n"
    "\t\tsetboolfield(L, -1, flagdesc[i].name, !!(flags & flagdesc[i].flag));\n"
    "\t}\n"
    "\treturn 1;\n"
    "}\n\n"

    "// set_ghost_node(pos, node_name)\n"
    "// Client-side-only visual node overlay: no server interaction, no\n"
    "// collision. Intended for build previews (schematics, WorldEdit-like\n"
    "// tools, etc).\n"
    "int ModApiClient::l_set_ghost_node(lua_State *L)\n"
    "{\n"
    "\tv3s16 pos = read_v3s16(L, 1);\n"
    "\tstd::string node_name = luaL_checkstring(L, 2);\n\n"
    "\tgetClient(L)->setGhostNode(pos, node_name);\n"
    "\treturn 0;\n"
    "}\n\n"

    "// remove_ghost_node(pos)\n"
    "int ModApiClient::l_remove_ghost_node(lua_State *L)\n"
    "{\n"
    "\tv3s16 pos = read_v3s16(L, 1);\n"
    "\tgetClient(L)->removeGhostNode(pos);\n"
    "\treturn 0;\n"
    "}\n\n"

    "// clear_ghost_nodes()\n"
    "int ModApiClient::l_clear_ghost_nodes(lua_State *L)\n"
    "{\n"
    "\tgetClient(L)->clearGhostNodes();\n"
    "\treturn 0;\n"
    "}\n\n"

    "void ModApiClient::Initialize(lua_State *L, int top)\n"
)

ok &= apply(
    "src/script/lua_api/l_client.cpp",
    "\tAPI_FCT(get_csm_restrictions);\n}\n",
    "\tAPI_FCT(get_csm_restrictions);\n"
    "\tAPI_FCT(set_ghost_node);\n"
    "\tAPI_FCT(remove_ghost_node);\n"
    "\tAPI_FCT(clear_ghost_nodes);\n"
    "}\n"
)

print()
if ok:
    print("=== УСПІХ: усі правки застосовано ===")
else:
    print("=== УВАГА: деякі правки НЕ застосовано, дивись помилки вище ===")

import sys

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

# builtin/game/register.lua
ok &= apply(
    "builtin/game/register.lua",
    'core.registered_on_player_receive_fields, core.register_on_player_receive_fields = make_registration_reverse()',
    'core.registered_on_player_receive_fields, core.register_on_player_receive_fields = make_registration_reverse()\ncore.registered_on_hud_touch, core.register_on_hud_touch = make_registration()'
)

# src/client/client.h
ok &= apply(
    "src/client/client.h",
    "\tvoid sendDamage(u16 damage);\n",
    "\tvoid sendDamage(u16 damage);\n\tvoid sendHudTouch(const std::string &hud_element_name);\n"
)

# src/client/client.cpp
ok &= apply(
    "src/client/client.cpp",
    "void Client::sendDamage(u16 damage)\n{\n\tNetworkPacket pkt(TOSERVER_DAMAGE, sizeof(u16));\n\tpkt << damage;\n\tSend(&pkt);\n}\n",
    "void Client::sendDamage(u16 damage)\n{\n\tNetworkPacket pkt(TOSERVER_DAMAGE, sizeof(u16));\n\tpkt << damage;\n\tSend(&pkt);\n}\n\nvoid Client::sendHudTouch(const std::string &hud_element_name)\n{\n\tNetworkPacket pkt(TOSERVER_HUD_TOUCH, 0);\n\tpkt << hud_element_name;\n\tSend(&pkt);\n}\n"
)

# src/client/game.cpp - part 1: poll each frame
ok &= apply(
    "src/client/game.cpp",
    "\tprocessKeyInput();\n\tprocessItemSelection(&runData.new_playeritem);\n}",
    "\tprocessKeyInput();\n\tprocessItemSelection(&runData.new_playeritem);\n\n\tif (g_touchcontrols) {\n\t\tstd::optional<std::string> touched = g_touchcontrols->getTouchedHudElement();\n\t\tif (touched)\n\t\t\tclient->sendHudTouch(*touched);\n\t}\n}"
)

# src/client/game.cpp - part 2: assign touchable on hud add (only if not already patched in step 1)
with open("src/client/game.cpp") as f:
    _content = f.read()
if "e->touchable = event->hudadd->touchable;" not in _content:
    ok &= apply(
        "src/client/game.cpp",
        "\te->hideable  = event->hudadd->hideable;",
        "\te->hideable  = event->hudadd->hideable;\n\te->touchable = event->hudadd->touchable;"
    )
else:
    print("Пропускаю: e->touchable вже є в game.cpp (застосовано на Кроці 1)")

# src/client/hud.cpp - part 1: reset rects
ok &= apply(
    "src/client/hud.cpp",
    "void Hud::drawLuaElements(const v3s16 &camera_offset, bool only_unhidable)\n{\n\tconst u32 text_height = g_fontengine->getTextHeight();\n\tgui::IGUIFont *const font = g_fontengine->getFont();\n\n\tstd::vector<HudElement*> elems;",
    "void Hud::drawLuaElements(const v3s16 &camera_offset, bool only_unhidable)\n{\n\tconst u32 text_height = g_fontengine->getTextHeight();\n\tgui::IGUIFont *const font = g_fontengine->getFont();\n\n\tif (g_touchcontrols && !only_unhidable)\n\t\tg_touchcontrols->resetTouchableHudRects();\n\n\tstd::vector<HudElement*> elems;"
)

# src/client/hud.cpp - part 2: register rect for touchable image
ok &= apply(
    "src/client/hud.cpp",
    "\t\t\t\tdraw2DImageFilterScaled(driver, texture, rect,\n\t\t\t\t\tcore::rect<s32>(core::position2d<s32>(0,0), imgsize),\n\t\t\t\t\tNULL, colors, true);\n\t\t\t\tbreak; }",
    "\t\t\t\tdraw2DImageFilterScaled(driver, texture, rect,\n\t\t\t\t\tcore::rect<s32>(core::position2d<s32>(0,0), imgsize),\n\t\t\t\t\tNULL, colors, true);\n\n\t\t\t\tif (e->touchable && g_touchcontrols)\n\t\t\t\t\tg_touchcontrols->registerTouchableHudRect(e->name, rect);\n\t\t\t\tbreak; }"
)

# src/gui/touchcontrols.h - method declarations
ok &= apply(
    "src/gui/touchcontrols.h",
    "\tvoid registerHotbarRect(u16 index, const recti &rect);\n\tstd::optional<u16> getHotbarSelection();\n",
    "\tvoid registerHotbarRect(u16 index, const recti &rect);\n\tstd::optional<u16> getHotbarSelection();\n\n\tvoid resetTouchableHudRects();\n\tvoid registerTouchableHudRect(const std::string &name, const recti &rect);\n\tstd::optional<std::string> getTouchedHudElement();\n"
)

# src/gui/touchcontrols.h - member storage
ok &= apply(
    "src/gui/touchcontrols.h",
    "\tstd::unordered_map<u16, recti> m_hotbar_rects;\n\tstd::optional<u16> m_hotbar_selection = std::nullopt;\n",
    "\tstd::unordered_map<u16, recti> m_hotbar_rects;\n\tstd::optional<u16> m_hotbar_selection = std::nullopt;\n\n\tstd::unordered_map<std::string, recti> m_touchable_hud_rects;\n\tstd::optional<std::string> m_touched_hud_element = std::nullopt;\n"
)

# src/gui/touchcontrols.h - private helper declaration
ok &= apply(
    "src/gui/touchcontrols.h",
    "\tbool isHotbarButton(const SEvent &event);\n",
    "\tbool isHotbarButton(const SEvent &event);\n\tbool isTouchableHudButton(const SEvent &event);\n"
)

# src/gui/touchcontrols.cpp - implement isTouchableHudButton + getTouchedHudElement
ok &= apply(
    "src/gui/touchcontrols.cpp",
    "std::optional<u16> TouchControls::getHotbarSelection()\n{\n\tauto selection = m_hotbar_selection;\n\tm_hotbar_selection = std::nullopt;\n\treturn selection;\n}\n",
    "std::optional<u16> TouchControls::getHotbarSelection()\n{\n\tauto selection = m_hotbar_selection;\n\tm_hotbar_selection = std::nullopt;\n\treturn selection;\n}\n\nbool TouchControls::isTouchableHudButton(const SEvent &event)\n{\n\tconst v2s32 touch_pos = v2s32(event.TouchInput.X, event.TouchInput.Y);\n\tfor (auto &[name, rect] : m_touchable_hud_rects) {\n\t\tif (rect.isPointInside(touch_pos)) {\n\t\t\tm_touched_hud_element = name;\n\t\t\treturn true;\n\t\t}\n\t}\n\treturn false;\n}\n\nstd::optional<std::string> TouchControls::getTouchedHudElement()\n{\n\tauto touched = m_touched_hud_element;\n\tm_touched_hud_element = std::nullopt;\n\treturn touched;\n}\n"
)

# src/gui/touchcontrols.cpp - wire into translateEvent
ok &= apply(
    "src/gui/touchcontrols.cpp",
    "\t\t// handle hotbar\n\t\tif (isHotbarButton(event))\n\t\t\t// already handled in isHotbarButton()\n\t\t\treturn;\n",
    "\t\t// handle hotbar\n\t\tif (isHotbarButton(event))\n\t\t\t// already handled in isHotbarButton()\n\t\t\treturn;\n\n\t\t// handle mod-defined touchable HUD buttons\n\t\tif (isTouchableHudButton(event))\n\t\t\t// already handled in isTouchableHudButton()\n\t\t\treturn;\n"
)

# src/gui/touchcontrols.cpp - implement reset/register
ok &= apply(
    "src/gui/touchcontrols.cpp",
    "void TouchControls::registerHotbarRect(u16 index, const recti &rect)\n{\n\tm_hotbar_rects[index] = rect;\n}\n",
    "void TouchControls::registerHotbarRect(u16 index, const recti &rect)\n{\n\tm_hotbar_rects[index] = rect;\n}\n\nvoid TouchControls::resetTouchableHudRects()\n{\n\tm_touchable_hud_rects.clear();\n}\n\nvoid TouchControls::registerTouchableHudRect(const std::string &name, const recti &rect)\n{\n\tm_touchable_hud_rects[name] = rect;\n}\n"
)

# src/network/clientopcodes.cpp
ok &= apply(
    "src/network/clientopcodes.cpp",
    '\t{ "TOSERVER_UPDATE_CLIENT_INFO", 2, true }, // 0x53\n',
    '\t{ "TOSERVER_UPDATE_CLIENT_INFO", 2, true }, // 0x53\n\t{ "TOSERVER_HUD_TOUCH",          0, true }, // 0x54\n'
)

# src/network/networkprotocol.h
ok &= apply(
    "src/network/networkprotocol.h",
    "\tTOSERVER_NUM_MSG_TYPES = 0x54,\n};",
    "\tTOSERVER_HUD_TOUCH = 0x54,\n\t/*\n\t\tstd::string hud_element_name\n\t\t-- Sent when the player taps a touchable HUD element on a\n\t\t-- touchscreen client.\n\t*/\n\n\tTOSERVER_NUM_MSG_TYPES = 0x55,\n};"
)

# src/network/serveropcodes.cpp
ok &= apply(
    "src/network/serveropcodes.cpp",
    '\t{ "TOSERVER_UPDATE_CLIENT_INFO",       TOSERVER_STATE_INGAME, &Server::handleCommand_UpdateClientInfo }, // 0x53\n',
    '\t{ "TOSERVER_UPDATE_CLIENT_INFO",       TOSERVER_STATE_INGAME, &Server::handleCommand_UpdateClientInfo }, // 0x53\n\t{ "TOSERVER_HUD_TOUCH",                TOSERVER_STATE_INGAME, &Server::handleCommand_HudTouch }, // 0x54\n'
)

# src/network/serverpackethandler.cpp
ok &= apply(
    "src/network/serverpackethandler.cpp",
    "\t\tPlayerHPChangeReason reason(PlayerHPChangeReason::FALL);\n\t\tplayersao->setHP((s32)playersao->getHP() - (s32)damage, reason, true);\n\t}\n}\n",
    "\t\tPlayerHPChangeReason reason(PlayerHPChangeReason::FALL);\n\t\tplayersao->setHP((s32)playersao->getHP() - (s32)damage, reason, true);\n\t}\n}\n\nvoid Server::handleCommand_HudTouch(NetworkPacket* pkt)\n{\n\tstd::string hud_element_name;\n\t*pkt >> hud_element_name;\n\n\tsession_t peer_id = pkt->getPeerId();\n\tRemotePlayer *player = m_env->getPlayer(peer_id);\n\tif (!player) {\n\t\twarningstream << FUNCTION_NAME << \": player is null\" << std::endl;\n\t\treturn;\n\t}\n\n\tPlayerSAO *playersao = player->getPlayerSAO();\n\tif (!playersao) {\n\t\twarningstream << FUNCTION_NAME << \": player SAO is null\" << std::endl;\n\t\treturn;\n\t}\n\n\tm_script->on_playerHudTouch(playersao, hud_element_name);\n}\n"
)

# src/script/cpp_api/s_player.h
ok &= apply(
    "src/script/cpp_api/s_player.h",
    "\tvoid on_playerReceiveFields(ServerActiveObject *player,\n\t\t\tconst std::string &formname, const StringMap &fields);\n",
    "\tvoid on_playerReceiveFields(ServerActiveObject *player,\n\t\t\tconst std::string &formname, const StringMap &fields);\n\tvoid on_playerHudTouch(ServerActiveObject *player,\n\t\t\tconst std::string &hud_element_name);\n"
)

# src/script/cpp_api/s_player.cpp
ok &= apply(
    "src/script/cpp_api/s_player.cpp",
    "\trunCallbacks(3, RUN_CALLBACKS_MODE_OR_SC);\n}\n\nvoid ScriptApiPlayer::on_authplayer",
    "\trunCallbacks(3, RUN_CALLBACKS_MODE_OR_SC);\n}\n\nvoid ScriptApiPlayer::on_playerHudTouch(ServerActiveObject *player,\n\t\tconst std::string &hud_element_name)\n{\n\tSCRIPTAPI_PRECHECKHEADER\n\n\t// Get core.registered_on_hud_touch\n\tlua_getglobal(L, \"core\");\n\tlua_getfield(L, -1, \"registered_on_hud_touch\");\n\t// param 1\n\tobjectrefGetOrCreate(L, player);\n\t// param 2\n\tlua_pushstring(L, hud_element_name.c_str());\n\trunCallbacks(2, RUN_CALLBACKS_MODE_OR_SC);\n}\n\nvoid ScriptApiPlayer::on_authplayer"
)

# src/server.h
ok &= apply(
    "src/server.h",
    "\tvoid handleCommand_UpdateClientInfo(NetworkPacket *pkt);\n",
    "\tvoid handleCommand_UpdateClientInfo(NetworkPacket *pkt);\n\tvoid handleCommand_HudTouch(NetworkPacket *pkt);\n"
)

print()
if ok:
    print("=== УСПІХ: усі правки застосовано ===")
else:
    print("=== УВАГА: деякі правки НЕ застосовано, дивись помилки вище ===")
    sys.exit(1)

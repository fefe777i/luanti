-- Luanti
-- Copyright (C) 2014 sapier
-- SPDX-License-Identifier: LGPL-2.1-or-later


local current_game, singleplayer_refresh_gamebar
local valid_disabled_settings = {
	["enable_damage"]=true,
	["creative_mode"]=true,
	["enable_server"]=true,
}

-- Name and port stored to persist when updating the formspec
local current_name = core.settings:get("name")
local current_port = core.settings:get("port")

-- Currently chosen game in gamebar for theming and filtering
function current_game()
	local gameid = core.settings:get("menu_last_game")
	local game = gameid and pkgmgr.find_by_gameid(gameid)
	-- Fall back to first game installed if one exists.
	if not game and #pkgmgr.games > 0 then

		-- If devtest is the first game in the list and there is another
		-- game available, pick the other game instead.
		local picked_game
		if pkgmgr.games[1].id == "devtest" and #pkgmgr.games > 1 then
			picked_game = 2
		else
			picked_game = 1
		end

		game = pkgmgr.games[picked_game]
		gameid = game.id
		core.settings:set("menu_last_game", gameid)
	end

	return game
end

-- Apply menu changes from given game
function apply_game(game)
	core.settings:set("menu_last_game", game.id)
	menudata.worldlist:set_filtercriteria(game.id)

	mm_game_theme.set_game(game)

	local index = filterlist.get_current_index(menudata.worldlist,
		tonumber(core.settings:get("mainmenu_last_selected_world")))
	if not index or index < 1 then
		local selected = core.get_textlist_index("sp_worlds")
		if selected ~= nil and selected < #menudata.worldlist:get_list() then
			index = selected
		else
			index = #menudata.worldlist:get_list()
		end
	end
	menu_worldmt_legacy(index)
end

function singleplayer_refresh_gamebar()

	local old_bar = ui.find_by_name("game_button_bar")
	if old_bar ~= nil then
		old_bar:delete()
	end

	-- Hide gamebar if no games are installed
	if #pkgmgr.games == 0 then
		return false
	end

	local function game_buttonbar_button_handler(fields)
		for _, game in ipairs(pkgmgr.games) do
			if fields["game_btnbar_" .. game.id] then
				apply_game(game)
				return true
			end
		end
	end

	local TOUCH_GUI = core.settings:get_bool("touch_gui")

	local gamebar_pos_y = MAIN_TAB_H
		+ TABHEADER_H -- tabheader included in formspec size
		+ (TOUCH_GUI and GAMEBAR_OFFSET_TOUCH or GAMEBAR_OFFSET_DESKTOP)

	local btnbar = buttonbar_create(
			"game_button_bar",
			{x = 0, y = gamebar_pos_y},
			{x = MAIN_TAB_W, y = GAMEBAR_H},
			"#000000",
			game_buttonbar_button_handler)

	for _, game in ipairs(pkgmgr.games) do
		local btn_name = "game_btnbar_" .. game.id

		local image = nil
		local text = nil
		local tooltip = core.formspec_escape(game.title)

		if (game.menuicon_path or "") ~= "" then
			image = core.formspec_escape(game.menuicon_path)
		else
			local part1 = game.id:sub(1,5)
			local part2 = game.id:sub(6,10)
			local part3 = game.id:sub(11)

			text = part1 .. "\n" .. part2
			if part3 ~= "" then
				text = text .. "\n" .. part3
			end
		end
		btnbar:add_button(btn_name, text, image, tooltip)
	end

	local plus_image = core.formspec_escape(defaulttexturedir .. "plus.png")
	btnbar:add_button("game_open_cdb", "", plus_image, fgettext("Install games from ContentDB"))
	return true
end

local function get_disabled_settings(game)
	if not game then
		return {}
	end

	local gameconfig = Settings(game.path .. "/game.conf")
	local disabled_settings = {}
	if gameconfig then
		local disabled_settings_str = (gameconfig:get("disabled_settings") or ""):split()
		for _, value in pairs(disabled_settings_str) do
			local state = false
			value = value:trim()
			if string.sub(value, 1, 1) == "!" then
				state = true
				value = string.sub(value, 2)
			end
			if valid_disabled_settings[value] then
				disabled_settings[value] = state
			else
				core.log("error", "Invalid disabled setting in game.conf: "..tostring(value))
			end
		end
	end
	return disabled_settings
end

local function classic_get_formspec(tabview, name, tabdata)

	-- Point the player to ContentDB when no games are found
	if #pkgmgr.games == 0 then
		local W = tabview.width
		local H = tabview.height

		local hypertext = "<global valign=middle halign=center size=18>" ..
				fgettext_ne("Luanti is a game-creation platform that allows you to play many different games.") .. "\n" ..
				fgettext_ne("Luanti doesn't come with a game by default.") .. " " ..
				fgettext_ne("You need to install a game before you can create a world.")

		local button_y = H * 2/3 - 0.6
		return table.concat({
			ws47_theme.STYLE_PREFIX,
			"box[0,0;", tostring(W), ",", tostring(H), ";", ws47_theme.COLOR_BG, "]",
			"hypertext[0.375,0;", W - 2*0.375, ",", button_y, ";ht;", core.formspec_escape(hypertext), "]",
			"button[5.25,", button_y, ";5,1.2;game_open_cdb;", fgettext("Install a game"), "]"})
	end

	local retval = ws47_theme.STYLE_PREFIX ..
		"box[0,0;" .. tostring(tabview.width) .. "," .. tostring(tabview.height) .. ";" .. ws47_theme.COLOR_BG .. "]"

	-- Player model with the chosen skin (left column, below the checkboxes).
	-- Hidden when hosting a server: the name/port fields use that space.
	if not core.settings:get_bool("enable_server") then
		retval = retval ..
			"box[0.375,2.75;4.5,3.95;" .. ws47_theme.COLOR_BG_2 .. "]" ..
			ws47_theme.player_model(0.45, 2.8, 4.35, 3.85)
	end

	local index = core.get_textlist_index("sp_worlds") or filterlist.get_current_index(menudata.worldlist,
				tonumber(core.settings:get("mainmenu_last_selected_world"))) or 0

	local list = menudata.worldlist:get_list()
	-- When changing tabs to a world list with fewer entries, the last index is selected (visually).
	-- However, the formspec fields lag behind, thus 'index > #list' can be a valid choice.
	local world = list and list[math.min(index, #list)]
	local game

	if world then
		game = pkgmgr.find_by_gameid(world.gameid)
	else
		game = current_game()
	end
	local disabled_settings = get_disabled_settings(game)

	local creative, damage, host = "", "", ""

	-- Y offsets for game settings checkboxes
	local y = 0.2
	local yo = 0.5625

	if world then
		if disabled_settings["creative_mode"] == nil then
			creative = "checkbox[0,"..y..";cb_creative_mode;".. fgettext("Creative Mode") .. ";" ..
				dump(core.settings:get_bool("creative_mode")) .. "]"
			y = y + yo
		end
		if disabled_settings["enable_damage"] == nil then
			damage = "checkbox[0,"..y..";cb_enable_damage;".. fgettext("Enable Damage") .. ";" ..
				dump(core.settings:get_bool("enable_damage")) .. "]"
			y = y + yo
		end
		if disabled_settings["enable_server"] == nil then
			host = "checkbox[0,"..y..";cb_server;".. fgettext("Host Server") ..";" ..
				dump(core.settings:get_bool("enable_server")) .. "]"
			y = y + yo
		end
	end

	retval = retval .. "container[5.25,4.875]"
	if world then
		retval = retval ..
				"button[0,0;3.225,0.8;world_delete;".. fgettext("Delete") .. "]" ..
				"button[3.325,0;3.225,0.8;world_configure;".. fgettext("Select Mods") .. "]"
	end
	retval = retval ..
			"button[6.65,0;3.225,0.8;world_create;".. fgettext("New") .. "]" ..
			"container_end[]" ..
			"container[0.375,0.375]" ..
			creative ..
			damage ..
			host ..
			"container_end[]" ..
			"container[5.25,0.375]" ..
			"label[0,0.2;".. fgettext("Select World:") .. "]"..
			"textlist[0,0.5;9.875,3.9;sp_worlds;" ..
			menu_render_worldlist() ..
			";" .. index .. "]" ..
			"container_end[]"

	if core.settings:get_bool("enable_server") and disabled_settings["enable_server"] == nil then
		retval = retval ..
				"button[10.1875,5.925;4.9375,0.8;play;".. fgettext("Host Game") .. "]" ..
				"container[0.375,0.375]" ..
				"checkbox[0,"..y..";cb_server_announce;" .. fgettext("Announce Server") .. ";" ..
				dump(core.settings:get_bool("server_announce")) .. "]"

		-- Reset y so that the text fields always start at the same position,
		-- regardless of whether some of the checkboxes are hidden.
		y = 0.2 + 4 * yo + 0.35

		retval = retval .. "field[0," .. y .. ";4.5,0.75;te_playername;" .. fgettext("Name") .. ";" ..
				core.formspec_escape(current_name) .. "]"

		y = y + 1.15 + 0.25

		retval = retval .. "pwdfield[0," .. y .. ";4.5,0.75;te_passwd;" .. fgettext("Password") .. "]"

		y = y + 1.15 + 0.25

		local bind_addr = core.settings:get("bind_address")
		if bind_addr ~= nil and bind_addr ~= "" then
			retval = retval ..
				"field[0," .. y .. ";3,0.75;te_serveraddr;" .. fgettext("Bind Address") .. ";" ..
				core.formspec_escape(core.settings:get("bind_address")) .. "]" ..
				-- TRANSLATORS: Network port
				"field[3.25," .. y .. ";1.25,0.75;te_serverport;" .. fgettext("Port") .. ";" ..
				core.formspec_escape(current_port) .. "]"
		else
			retval = retval ..
				"field[0," .. y .. ";4.5,0.75;te_serverport;" .. fgettext("Server Port") .. ";" ..
				core.formspec_escape(current_port) .. "]"
		end

		retval = retval .. "container_end[]"
	elseif world then
		retval = retval ..
				"button[10.1875,5.925;4.9375,0.8;play;" .. fgettext("Play Game") .. "]"
	end

	return retval
end

local function classic_button_handler(this, fields, name, tabdata)

	assert(name == "local")

	if fields.game_open_cdb then
		local maintab = ui.find_by_name("maintab")
		local dlg = create_contentdb_dlg("game")
		dlg:set_parent(maintab)
		maintab:hide()
		dlg:show()
		return true
	end

	if this.dlg_create_world_closed_at == nil then
		this.dlg_create_world_closed_at = 0
	end

	local world_doubleclick = false

	if fields["te_playername"] then
		current_name = fields["te_playername"]
	end

	if fields["te_serverport"] then
		current_port = fields["te_serverport"]
	end

	if fields["sp_worlds"] ~= nil then
		local event = core.explode_textlist_event(fields["sp_worlds"])
		local selected = core.get_textlist_index("sp_worlds")

		menu_worldmt_legacy(selected)

		if event.type == "DCL" then
			world_doubleclick = true
		end

		if event.type == "CHG" and selected ~= nil then
			core.settings:set("mainmenu_last_selected_world",
				menudata.worldlist:get_raw_index(selected))
			return true
		end
	end

	if menu_handle_key_up_down(fields,"sp_worlds","mainmenu_last_selected_world") then
		return true
	end

	if fields["cb_creative_mode"] then
		core.settings:set("creative_mode", fields["cb_creative_mode"])
		local selected = core.get_textlist_index("sp_worlds")
		menu_worldmt(selected, "creative_mode", fields["cb_creative_mode"])

		return true
	end

	if fields["cb_enable_damage"] then
		core.settings:set("enable_damage", fields["cb_enable_damage"])
		local selected = core.get_textlist_index("sp_worlds")
		menu_worldmt(selected, "enable_damage", fields["cb_enable_damage"])

		return true
	end

	if fields["cb_server"] then
		core.settings:set("enable_server", fields["cb_server"])

		return true
	end

	if fields["cb_server_announce"] then
		core.settings:set("server_announce", fields["cb_server_announce"])
		local selected = core.get_textlist_index("srv_worlds")
		menu_worldmt(selected, "server_announce", fields["cb_server_announce"])

		return true
	end

	if fields["play"] ~= nil or world_doubleclick or fields["key_enter"] then
		local enter_key_duration = core.get_us_time() - this.dlg_create_world_closed_at
		if world_doubleclick and enter_key_duration <= 200000 then -- 200 ms
			this.dlg_create_world_closed_at = 0
			return true
		end

		local selected = core.get_textlist_index("sp_worlds")
		gamedata.selected_world = menudata.worldlist:get_raw_index(selected)

		if selected == nil or gamedata.selected_world == 0 then
			return true
		end

		-- Update last game
		local world = menudata.worldlist:get_raw_element(gamedata.selected_world)
		local game_obj
		if world then
			game_obj = pkgmgr.find_by_gameid(world.gameid)
			core.settings:set("menu_last_game", game_obj.id)
		end

		local disabled_settings = get_disabled_settings(game_obj)
		for k, _ in pairs(valid_disabled_settings) do
			local v = disabled_settings[k]
			if v ~= nil then
				if k == "enable_server" and v == true then
					error("Setting 'enable_server' cannot be force-enabled! The game.conf needs to be fixed.")
				end
				core.settings:set_bool(k, disabled_settings[k])
			end
		end

		if core.settings:get_bool("enable_server") then
			gamedata.mode       = "host"
			gamedata.playername = fields["te_playername"]
			gamedata.password   = fields["te_passwd"]
			gamedata.port       = fields["te_serverport"]
			gamedata.address    = ""

			core.settings:set("port",gamedata.port)
			if fields["te_serveraddr"] ~= nil then
				core.settings:set("bind_address",fields["te_serveraddr"])
			end
		else
			gamedata.mode = "singleplayer"
		end

		core.start()
		return true
	end

	if fields["world_create"] ~= nil then
		this.dlg_create_world_closed_at = 0
		local create_world_dlg = create_create_world_dlg()
		create_world_dlg:set_parent(this)
		this:hide()
		create_world_dlg:show()
		return true
	end

	if fields["world_delete"] ~= nil then
		local selected = core.get_textlist_index("sp_worlds")
		if selected ~= nil and
			selected <= menudata.worldlist:size() then
			local world = menudata.worldlist:get_list()[selected]
			if world ~= nil and
				world.name ~= nil and
				world.name ~= "" then
				local index = menudata.worldlist:get_raw_index(selected)
				local delete_world_dlg = create_delete_world_dlg(world.name,index)
				delete_world_dlg:set_parent(this)
				this:hide()
				delete_world_dlg:show()
			end
		end

		return true
	end

	if fields["world_configure"] ~= nil then
		local selected = core.get_textlist_index("sp_worlds")
		if selected ~= nil then
			local configdialog =
				create_configure_world_dlg(
						menudata.worldlist:get_raw_index(selected))

			if (configdialog ~= nil) then
				configdialog:set_parent(this)
				this:hide()
				configdialog:show()
			end
		end

		return true
	end
end

--------------------------------------------------------------------------------
-- Slot menu: 6 world slots (tap an empty slot = create a world and start it,
-- tap a filled slot = play it, trash button = delete it).
-- Slots are plain neon squares: a plus when empty, the game icon when filled.
-- The old menu comes back with Settings -> Advanced -> "Classic singleplayer menu".
--------------------------------------------------------------------------------
local SLOT_COUNT = 6

local function use_classic_menu()
	return core.settings:get_bool("ws47_classic_menu")
end

local function slot_key(i)
	return "ws47_slot_" .. i
end

-- Returns the raw world list element stored in slot i (or nil if empty)
local function slot_world(i)
	local name = core.settings:get(slot_key(i))
	if not name or name == "" then
		return nil
	end
	for _, world in ipairs(menudata.worldlist:get_raw_list()) do
		if world.name == name then
			return world
		end
	end
	return nil
end

local function slots_formspec(tabview)
	local W = tabview.width
	local H = tabview.height
	local gap = 0.35
	local cols, rows = 3, 2

	-- squares: as big as fit
	local side = math.min((H - 0.3 - 0.375 - (rows - 1) * gap) / rows,
		(W - 0.75 - (cols - 1) * gap) / cols)
	local total_w = cols * side + (cols - 1) * gap
	local x_start = (W - total_w) / 2
	local y_start = 0.3

	local fs = {
		ws47_theme.STYLE_PREFIX,
		"box[0,0;", W, ",", H, ";", ws47_theme.COLOR_BG, "]",
	}

	local tex = function(name)
		return core.formspec_escape(defaulttexturedir .. name)
	end

	for i = 1, SLOT_COUNT do
		local col = (i - 1) % cols
		local row = math.floor((i - 1) / cols)
		local x = x_start + col * (side + gap)
		local y = y_start + row * (side + gap)
		local world = slot_world(i)

		-- neon frame: blue for a world, pink for an empty slot
		local frame = world and ws47_theme.COLOR_BLUE or ws47_theme.COLOR_PINK
		local glow = frame:sub(1, 7) .. "3a"
		local b = 0.07 -- frame thickness

		fs[#fs + 1] = ("box[%f,%f;%f,%f;%s]"):format(x - 0.1, y - 0.1, side + 0.2, side + 0.2, glow)
		fs[#fs + 1] = ("box[%f,%f;%f,%f;%s]"):format(x, y, side, side, frame)
		fs[#fs + 1] = ("box[%f,%f;%f,%f;#0a0620]"):format(x + b, y + b, side - 2 * b, side - 2 * b)

		if world then
			local game = pkgmgr.find_by_gameid(world.gameid)
			local icon
			if game and (game.menuicon_path or "") ~= "" then
				icon = core.formspec_escape(game.menuicon_path)
			else
				icon = tex("ws47_logo.png")
			end
			fs[#fs + 1] = ("style[slot_play_%d;bgimg=%s;bgimg_hovered=%s;bgimg_pressed=%s;border=false]")
				:format(i, icon, icon, icon)
			fs[#fs + 1] = ("button[%f,%f;%f,%f;slot_play_%d;]"):format(
				x + b, y + b, side - 2 * b, side - 2 * b, i)

			-- trash button in the corner (drawn after the slot button, so it is on top)
			fs[#fs + 1] = ("style[slot_del_%d;bgcolor=#7a1530;bgcolor_hovered=#ff3c5c;bgcolor_pressed=#ff3c5c]"):format(i)
			fs[#fs + 1] = ("image_button[%f,%f;0.75,0.75;%s;slot_del_%d;]"):format(
				x + side - 0.95, y + 0.2, tex("ws47_trash.png"), i)
		else
			fs[#fs + 1] = ("style[slot_new_%d;bgimg=%s;bgimg_hovered=%s;bgimg_pressed=%s;border=false]")
				:format(i, tex("ws47_slot_empty.png"), tex("ws47_slot_empty_hover.png"),
					tex("ws47_slot_empty_pressed.png"))
			fs[#fs + 1] = ("button[%f,%f;%f,%f;slot_new_%d;]"):format(
				x + b, y + b, side - 2 * b, side - 2 * b, i)
		end
	end

	return table.concat(fs)
end

-- Start the world with the given name in singleplayer mode
local function start_world(world_name)
	local raw_index = menudata.worldlist:raw_index_by_uid(world_name)
	if not raw_index or raw_index == 0 then
		return false
	end
	local world = menudata.worldlist:get_raw_element(raw_index)
	if not world then
		return false
	end

	local game_obj = pkgmgr.find_by_gameid(world.gameid)
	if game_obj then
		core.settings:set("menu_last_game", game_obj.id)
		menudata.worldlist:set_filtercriteria(game_obj.id)
	end

	-- Load creative/damage etc. of this world into the settings
	local list_index = filterlist.get_current_index(menudata.worldlist, raw_index)
	if list_index and list_index > 0 then
		menu_worldmt_legacy(list_index)
	end

	local disabled_settings = get_disabled_settings(game_obj)
	for k, _ in pairs(valid_disabled_settings) do
		local v = disabled_settings[k]
		if v ~= nil then
			if k == "enable_server" and v == true then
				error("Setting 'enable_server' cannot be force-enabled! The game.conf needs to be fixed.")
			end
			core.settings:set_bool(k, v)
		end
	end

	core.settings:set("mainmenu_last_selected_world", raw_index)
	gamedata.selected_world = raw_index
	gamedata.mode = "singleplayer"
	core.start()
	return true
end

-- Create a new world in slot i with default settings and start it
local function create_slot_world(slot)
	local game = current_game()
	if not game then
		return false
	end

	-- unique world name
	local worldname = "world_slot" .. slot
	local n = 1
	while menudata.worldlist:uid_exists_raw(worldname) do
		n = n + 1
		worldname = "world_slot" .. slot .. "_" .. n
	end

	local settings = {
		fixed_map_seed = core.settings:get("fixed_map_seed") or "",
	}
	local gameconfig = Settings(game.path .. "/game.conf")
	local mg = gameconfig and gameconfig:get("default_mapgen") or core.settings:get("mg_name")
	if mg and table.indexof(core.get_mapgen_names(), mg) > 0 then
		settings.mg_name = mg
	end

	local message = core.create_world(worldname, game.id, settings)
	if message ~= nil then
		gamedata.errormessage = message
		return true
	end

	core.settings:set("menu_last_game", game.id)
	menudata.worldlist:set_filtercriteria(game.id)
	menudata.worldlist:refresh()
	core.settings:set(slot_key(slot), worldname)

	start_world(worldname)
	return true
end

local function slots_button_handler(this, fields)
	for i = 1, SLOT_COUNT do
		if fields["slot_new_" .. i] then
			return create_slot_world(i)
		end

		if fields["slot_play_" .. i] then
			local world = slot_world(i)
			if world then
				start_world(world.name)
			end
			return true
		end

		if fields["slot_del_" .. i] then
			local world = slot_world(i)
			if world then
				local raw_index = menudata.worldlist:raw_index_by_uid(world.name)
				if raw_index and raw_index > 0 then
					local dlg = create_delete_world_dlg(world.name, raw_index)
					dlg:set_parent(this)
					this:hide()
					dlg:show()
				end
			end
			return true
		end
	end
	return false
end

local function get_formspec(tabview, name, tabdata)
	if #pkgmgr.games > 0 and not use_classic_menu() then
		return slots_formspec(tabview)
	end
	return classic_get_formspec(tabview, name, tabdata)
end

local function main_button_handler(this, fields, name, tabdata)
	if #pkgmgr.games > 0 and not use_classic_menu() then
		if fields.key_enter then
			return true
		end
		return slots_button_handler(this, fields)
	end
	return classic_button_handler(this, fields, name, tabdata)
end

local function on_change(type)
	if type == "ENTER" then
		local game = current_game()
		if game then
			apply_game(game)
		else
			mm_game_theme.set_engine()
		end
		mm_game_theme.clear_single("header")

		if use_classic_menu() then
			if singleplayer_refresh_gamebar() then
				ui.find_by_name("game_button_bar"):show()
			end
		else
			-- slot menu has no game bar
			local old_bar = ui.find_by_name("game_button_bar")
			if old_bar ~= nil then
				old_bar:delete()
			end
		end
	elseif type == "LEAVE" then
		menudata.worldlist:set_filtercriteria(nil)
		local gamebar = ui.find_by_name("game_button_bar")
		if gamebar then
			gamebar:hide()
		end
	end
end

--------------------------------------------------------------------------------
return {
	name = "local",
	caption = fgettext("Start Game"),
	cbf_formspec = get_formspec,
	cbf_button_handler = main_button_handler,
	on_change = on_change
}

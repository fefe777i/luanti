-- Workshop 47 / Мастерская 47
-- "Інші сервери": join any server by address and port, with saved servers.

local function trim(s)
	return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function init_defaults(tabdata)
	if tabdata.initialized then
		return
	end
	tabdata.initialized = true
	tabdata.address = core.settings:get("address") or ""
	tabdata.port = core.settings:get("remote_port") or "30000"
	tabdata.name = core.settings:get("name") or ""
	tabdata.pwd = ""
end

local function get_formspec(tabview, name, tabdata)
	init_defaults(tabdata)

	local items = {}
	for i, fav in ipairs(serverlistmgr.get_favorites()) do
		local title = (fav.name and fav.name ~= "") and fav.name or fav.address
		items[i] = core.formspec_escape(title .. "  (" .. fav.address .. ":" .. fav.port .. ")")
	end

	local fs = {
		ws47_theme.STYLE_PREFIX,
		"box[0,0;15.5,7.1;", ws47_theme.COLOR_BG, "]",

		-- saved servers
		"label[0.4,0.55;", fgettext("Збережені сервери"), "]",
		"box[0.3,0.9;6.9,5.9;", ws47_theme.COLOR_BG_2, "]",
		"textlist[0.4,1.0;6.7,5.7;sv_list;", table.concat(items, ","), ";",
			tostring(tabdata.selected or 0), ";false]",

		-- connection form
		"box[7.5,0.9;7.7,5.9;", ws47_theme.COLOR_BG_2, "]",
		"label[7.8,1.2;", fgettext("Адреса сервера"), "]",
		"field[7.8,1.4;5.2,0.8;te_address;;", core.formspec_escape(tabdata.address), "]",
		"label[13.2,1.2;", fgettext("Порт"), "]",
		"field[13.2,1.4;1.8,0.8;te_port;;", core.formspec_escape(tostring(tabdata.port)), "]",

		"label[7.8,2.6;", fgettext("Ім'я гравця"), "]",
		"field[7.8,2.8;7.2,0.8;te_name;;", core.formspec_escape(tabdata.name), "]",

		"label[7.8,4.0;", fgettext("Пароль"), "]",
		"pwdfield[7.8,4.2;7.2,0.8;te_pwd;]",

		"button[7.8,5.5;3.6,0.9;btn_connect;", fgettext("Підключитись"), "]",
		"button[11.5,5.5;1.8,0.9;btn_save;", fgettext("Зберегти"), "]",
		"button[13.4,5.5;1.6,0.9;btn_delete;", fgettext("Видалити"), "]",
	}
	return table.concat(fs)
end

-- returns address, port or nil after setting an error message
local function read_target(tabdata)
	local address = trim(tabdata.address)
	if address == "" then
		gamedata.errormessage = fgettext("Введи адресу сервера")
		return nil
	end
	local port = tonumber(trim(tabdata.port))
	if not port or port < 1 or port > 65535 or port % 1 ~= 0 then
		gamedata.errormessage = fgettext("Порт має бути числом від 1 до 65535")
		return nil
	end
	return address, port
end

local function connect(tabdata)
	local address, port = read_target(tabdata)
	if not address then
		return true
	end
	local player_name = trim(tabdata.name)
	if player_name == "" then
		gamedata.errormessage = fgettext("Введи ім'я гравця")
		return true
	end

	gamedata.playername = player_name
	gamedata.password = tabdata.pwd or ""
	gamedata.address = address
	gamedata.port = port
	gamedata.selected_world = 0

	core.settings:set("name", player_name)
	core.settings:set("address", address)
	core.settings:set("remote_port", tostring(port))

	core.start()
	return true
end

local function main_button_handler(tabview, fields, name, tabdata)
	init_defaults(tabdata)

	-- remember what was typed, the form is redrawn after some actions
	if fields.te_address ~= nil then tabdata.address = fields.te_address end
	if fields.te_port ~= nil then tabdata.port = fields.te_port end
	if fields.te_name ~= nil then tabdata.name = fields.te_name end
	if fields.te_pwd ~= nil then tabdata.pwd = fields.te_pwd end

	local favorites = serverlistmgr.get_favorites()

	if fields.sv_list then
		local event = core.explode_textlist_event(fields.sv_list)
		local fav = favorites[event.index]
		if fav and (event.type == "CHG" or event.type == "DCL") then
			tabdata.selected = event.index
			tabdata.address = fav.address
			tabdata.port = tostring(fav.port)
			if event.type == "DCL" then
				return connect(tabdata)
			end
			return true
		end
	end

	if fields.btn_save then
		local address, port = read_target(tabdata)
		if address then
			serverlistmgr.add_favorite({name = address, address = address, port = port})
			tabdata.selected = 1 -- the newest favorite is put first
		end
		return true
	end

	if fields.btn_delete then
		local fav = favorites[tabdata.selected or 0]
		if fav then
			serverlistmgr.delete_favorite(fav)
			tabdata.selected = nil
		end
		return true
	end

	if fields.btn_connect or fields.key_enter_field == "te_pwd"
			or fields.key_enter_field == "te_name"
			or fields.key_enter_field == "te_address" then
		return connect(tabdata)
	end

	return false
end

local function on_change(type)
	if type == "ENTER" then
		mm_game_theme.set_engine()
		mm_game_theme.clear_single("header")
	end
end

return {
	name = "servers",
	caption = fgettext("Інші сервери"),
	cbf_formspec = get_formspec,
	cbf_button_handler = main_button_handler,
	on_change = on_change
}
